//
//  GameViewController.m
//  pong
//
//  Created by Andy Vandijck on 02/10/2025.
//

#import "GameViewController.h"
#import "Renderer.h"
#import "PongView.h"

@implementation GameViewController
{
    MTKView *_view;

    Renderer *_renderer;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    NSView *container = self.view;
    PongView *pong = [[PongView alloc] initWithFrame:container.bounds];
    pong.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Remove any existing subviews
    for (NSView *sub in [container.subviews copy]) {
        [sub removeFromSuperview];
    }
    [container addSubview:pong];

    [pong startGame];
}

@end
