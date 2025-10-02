//
//  Renderer.m
//  pong
//
//  Created by Andy Vandijck on 02/10/2025.
//

#import <simd/simd.h>
#import <ModelIO/ModelIO.h>

#import "Renderer.h"

// Include header shared between C code here, which executes Metal API commands, and .metal files
#import "ShaderTypes.h"

// The renderer works with MaxBuffersInFlight at the same time.
#define MaxBuffersInFlight 3

@implementation Renderer
{
    dispatch_semaphore_t _inFlightSemaphore;
    id <MTLDevice> _device;

    id <MTLBuffer> _dynamicUniformBuffer[MaxBuffersInFlight];
    id <MTLRenderPipelineState> _pipelineState;
    id <MTLDepthStencilState> _depthState;
    id <MTLTexture> _colorMap;
    MTLVertexDescriptor *_mtlVertexDescriptor;

    uint8_t _uniformBufferIndex;

    matrix_float4x4 _projectionMatrix;

    float _rotation;

    MTKMesh *_mesh;

    id<MTL4CommandQueue> _commandQueue4;
    id<MTL4CommandAllocator> _commandAllocators[MaxBuffersInFlight];
    id<MTL4CommandBuffer> _commandBuffer;
    id<MTL4ArgumentTable> _argumentTable;
    id<MTLResidencySet> _residencySet;
    id<MTLSharedEvent> _sharedEvent;
    uint64_t _currentFrameIndex;
}

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
{
    self = [super init];
    if(self)
    {
        _device = view.device;
        _inFlightSemaphore = dispatch_semaphore_create(MaxBuffersInFlight);
        [self _loadMetalWithView:view];
        [self _loadAssets];
    }

    return self;
}

- (void)_loadMetalWithView:(nonnull MTKView *)view;
{
    /// Load Metal state objects and initialize renderer dependent view properties

    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    view.sampleCount = 1;

    _mtlVertexDescriptor = [[MTLVertexDescriptor alloc] init];

    _mtlVertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormatFloat3;
    _mtlVertexDescriptor.attributes[VertexAttributePosition].offset = 0;
    _mtlVertexDescriptor.attributes[VertexAttributePosition].bufferIndex = BufferIndexMeshPositions;

    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].format = MTLVertexFormatFloat2;
    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].offset = 0;
    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].bufferIndex = BufferIndexMeshGenerics;

    _mtlVertexDescriptor.layouts[BufferIndexMeshPositions].stride = 12;
    _mtlVertexDescriptor.layouts[BufferIndexMeshPositions].stepRate = 1;
    _mtlVertexDescriptor.layouts[BufferIndexMeshPositions].stepFunction = MTLVertexStepFunctionPerVertex;

    _mtlVertexDescriptor.layouts[BufferIndexMeshGenerics].stride = 8;
    _mtlVertexDescriptor.layouts[BufferIndexMeshGenerics].stepRate = 1;
    _mtlVertexDescriptor.layouts[BufferIndexMeshGenerics].stepFunction = MTLVertexStepFunctionPerVertex;

    id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

    id<MTL4Compiler> compiler = [_device newCompilerWithDescriptor:[MTL4CompilerDescriptor new]
                                                            error:nil];

    MTL4LibraryFunctionDescriptor *vertexFunction = [MTL4LibraryFunctionDescriptor new];
    vertexFunction.library = defaultLibrary;
    vertexFunction.name = @"vertexShader";
    MTL4LibraryFunctionDescriptor *fragmentFunction = [MTL4LibraryFunctionDescriptor new];
    fragmentFunction.library = defaultLibrary;
    fragmentFunction.name = @"fragmentShader";

    MTL4RenderPipelineDescriptor *pipelineStateDescriptor = [MTL4RenderPipelineDescriptor new];
    pipelineStateDescriptor.label = @"MyPipeline";
    pipelineStateDescriptor.rasterSampleCount = view.sampleCount;
    pipelineStateDescriptor.vertexFunctionDescriptor = vertexFunction;
    pipelineStateDescriptor.fragmentFunctionDescriptor = fragmentFunction;
    pipelineStateDescriptor.vertexDescriptor = _mtlVertexDescriptor;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;

    NSError *error = NULL;
    _pipelineState = [compiler newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                compilerTaskOptions:nil
                                                              error:&error];

    if (!_pipelineState)
    {
        NSLog(@"Failed to created pipeline state, error %@", error);
    }

    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = YES;
    _depthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];

    for(NSUInteger i = 0; i < MaxBuffersInFlight; i++)
    {
        _dynamicUniformBuffer[i] = [_device newBufferWithLength:sizeof(Uniforms)
                                                        options:MTLResourceStorageModeShared];

        _dynamicUniformBuffer[i].label = @"UniformBuffer";
    }
    
    _commandQueue4 = [_device newMTL4CommandQueue];
    _commandBuffer = [_device newCommandBuffer];
    MTL4ArgumentTableDescriptor *atd = [MTL4ArgumentTableDescriptor new];
    atd.maxBufferBindCount = 3;
    atd.maxTextureBindCount = 1;
    _argumentTable = [_device newArgumentTableWithDescriptor:atd error:nil];
    MTLResidencySetDescriptor *residencySetDesc = [MTLResidencySetDescriptor new];
    _residencySet = [_device newResidencySetWithDescriptor:residencySetDesc error:nil];
    for(uint32_t i = 0 ; i < MaxBuffersInFlight ; i++)
    {
        _commandAllocators[i] = [_device newCommandAllocator];
    }
    [_commandQueue4 addResidencySet:_residencySet];
    
    /// Run MaxBuffersInFlight ahead to simplify checking for completed frames
    _currentFrameIndex = MaxBuffersInFlight;
    _sharedEvent = [_device newSharedEvent];
    [_sharedEvent setSignaledValue:MaxBuffersInFlight-1];
}

- (void)_loadAssets
{
    /// Load assets into metal objects

    NSError *error;

    MTKMeshBufferAllocator *metalAllocator = [[MTKMeshBufferAllocator alloc]
                                              initWithDevice: _device];

    MDLMesh *mdlMesh = [MDLMesh newBoxWithDimensions:(vector_float3){4, 4, 4}
                                            segments:(vector_uint3){2, 2, 2}
                                        geometryType:MDLGeometryTypeTriangles
                                       inwardNormals:NO
                                           allocator:metalAllocator];

    MDLVertexDescriptor *mdlVertexDescriptor =
    MTKModelIOVertexDescriptorFromMetal(_mtlVertexDescriptor);

    mdlVertexDescriptor.attributes[VertexAttributePosition].name  = MDLVertexAttributePosition;
    mdlVertexDescriptor.attributes[VertexAttributeTexcoord].name  = MDLVertexAttributeTextureCoordinate;

    mdlMesh.vertexDescriptor = mdlVertexDescriptor;

    _mesh = [[MTKMesh alloc] initWithMesh:mdlMesh
                                   device:_device
                                    error:&error];

    if(!_mesh || error)
    {
        NSLog(@"Error creating MetalKit mesh %@", error.localizedDescription);
    }

    MTKTextureLoader* textureLoader = [[MTKTextureLoader alloc] initWithDevice:_device];

    NSDictionary *textureLoaderOptions =
    @{
      MTKTextureLoaderOptionTextureUsage       : @(MTLTextureUsageShaderRead),
      MTKTextureLoaderOptionTextureStorageMode : @(MTLStorageModePrivate)
      };

    _colorMap = [textureLoader newTextureWithName:@"ColorMap"
                                      scaleFactor:1.0
                                           bundle:nil
                                          options:textureLoaderOptions
                                            error:&error];

    if(!_colorMap || error)
    {
        NSLog(@"Error creating texture %@", error.localizedDescription);
    }
    
    
    for(NSUInteger i = 0; i < MaxBuffersInFlight; i++)
    {
        [_residencySet addAllocation:_dynamicUniformBuffer[i]];
    }
    [_residencySet addAllocation:_colorMap];
    for (NSUInteger bufferIndex = 0; bufferIndex < _mesh.vertexBuffers.count; bufferIndex++)
    {
        MTKMeshBuffer *vertexBuffer = _mesh.vertexBuffers[bufferIndex];
        if((NSNull*)vertexBuffer != [NSNull null])
        {
            [_residencySet addAllocation:vertexBuffer.buffer];
        }
    }
    
    for(MTKSubmesh *submesh in _mesh.submeshes)
    {
        [_residencySet addAllocation:submesh.indexBuffer.buffer];
    }
    [_residencySet commit];
}

- (void)_updateGameState
{
    /// Update any game state before encoding renderint commands to our drawable

    Uniforms * uniforms = (Uniforms*)_dynamicUniformBuffer[_uniformBufferIndex].contents;

    uniforms->projectionMatrix = _projectionMatrix;

    vector_float3 rotationAxis = {1, 1, 0};
    matrix_float4x4 modelMatrix = matrix4x4_rotation(_rotation, rotationAxis);
    matrix_float4x4 viewMatrix = matrix4x4_translation(0.0, 0.0, -8.0);

    uniforms->modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix);

    _rotation += .01;
}

- (void)drawInMTKView:(nonnull MTKView *)view
{
    /// Per frame updates here
    _uniformBufferIndex = (_uniformBufferIndex + 1) % MaxBuffersInFlight;
    
    /// Wait for previous work to complete to be able to reset and reuse the allocator.
    uint32_t subFrameIndex = _currentFrameIndex % MaxBuffersInFlight;
    id<MTL4CommandAllocator> commandAllocatorForFrame = _commandAllocators[subFrameIndex];
    uint64_t previousValueToWaitFor = _currentFrameIndex - MaxBuffersInFlight;
    [_sharedEvent waitUntilSignaledValue:previousValueToWaitFor timeoutMS:10];
    [commandAllocatorForFrame reset];
    [_commandBuffer beginCommandBufferWithAllocator:commandAllocatorForFrame];

    [self _updateGameState];

    /// Delay getting the currentMTL4RenderPassDescriptor until absolutely needed. This avoids
    ///   holding onto the drawable and blocking the display pipeline any longer than necessary
    MTL4RenderPassDescriptor* renderPassDescriptor = view.currentMTL4RenderPassDescriptor;

    if(renderPassDescriptor != nil)
    {
        /// Final pass rendering code here
        id<MTL4RenderCommandEncoder> renderEncoder =
            [_commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

        [renderEncoder pushDebugGroup:@"DrawBox"];

        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeBack];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setDepthStencilState:_depthState];

        [renderEncoder setArgumentTable:_argumentTable atStages:MTLRenderStageVertex | MTLRenderStageFragment];
        [_argumentTable setAddress:_dynamicUniformBuffer[_uniformBufferIndex].gpuAddress atIndex:BufferIndexUniforms];
        
        for (NSUInteger bufferIndex = 0; bufferIndex < _mesh.vertexBuffers.count; bufferIndex++)
        {
            MTKMeshBuffer *vertexBuffer = _mesh.vertexBuffers[bufferIndex];
            if((NSNull*)vertexBuffer != [NSNull null])
            {
                [_argumentTable setAddress:vertexBuffer.buffer.gpuAddress + vertexBuffer.offset atIndex:bufferIndex];
            }
        }
        [_argumentTable setTexture:_colorMap.gpuResourceID atIndex:TextureIndexColor];
        
        for(MTKSubmesh *submesh in _mesh.submeshes)
        {
            [renderEncoder drawIndexedPrimitives:submesh.primitiveType
                                      indexCount:submesh.indexCount
                                       indexType:submesh.indexType
                                     indexBuffer:submesh.indexBuffer.buffer.gpuAddress + submesh.indexBuffer.offset
                               indexBufferLength:submesh.indexBuffer.buffer.length - submesh.indexBuffer.offset];
        }


        [renderEncoder popDebugGroup];

        [renderEncoder endEncoding];

        [_commandBuffer useResidencySet:((CAMetalLayer *)view.layer).residencySet];
        [_commandBuffer endCommandBuffer];
        
        id<CAMetalDrawable> drawable = view.currentDrawable;
        [_commandQueue4 waitForDrawable:drawable];
        [_commandQueue4 commit:&_commandBuffer count:1];
        
        uint64_t futureValueToWaitFor = _currentFrameIndex;
        [_commandQueue4 signalEvent:_sharedEvent value:futureValueToWaitFor];
        _currentFrameIndex++;
        
        [_commandQueue4 signalDrawable:drawable];
        [drawable present];
    }
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    /// Respond to drawable size or orientation changes here

    float aspect = size.width / (float)size.height;
    _projectionMatrix = matrix_perspective_right_hand(65.0f * (M_PI / 180.0f), aspect, 0.1f, 100.0f);
}

#pragma mark Matrix Math Utilities

matrix_float4x4 matrix4x4_translation(float tx, float ty, float tz)
{
    return (matrix_float4x4) {{
        { 1,   0,  0,  0 },
        { 0,   1,  0,  0 },
        { 0,   0,  1,  0 },
        { tx, ty, tz,  1 }
    }};
}

static matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis)
{
    axis = vector_normalize(axis);
    float ct = cosf(radians);
    float st = sinf(radians);
    float ci = 1 - ct;
    float x = axis.x, y = axis.y, z = axis.z;

    return (matrix_float4x4) {{
        { ct + x * x * ci,     y * x * ci + z * st, z * x * ci - y * st, 0},
        { x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0},
        { x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0},
        {                   0,                   0,                   0, 1}
    }};
}

matrix_float4x4 matrix_perspective_right_hand(float fovyRadians, float aspect, float nearZ, float farZ)
{
    float ys = 1 / tanf(fovyRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);

    return (matrix_float4x4) {{
        { xs,   0,          0,  0 },
        {  0,  ys,          0,  0 },
        {  0,   0,         zs, -1 },
        {  0,   0, nearZ * zs,  0 }
    }};
}

@end
