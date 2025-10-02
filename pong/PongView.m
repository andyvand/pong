#import "PongView.h"

@interface PongView ()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) NSTimeInterval lastTimestamp;
@property (nonatomic) NSRect leftPaddle;
@property (nonatomic) NSRect rightPaddle;
@property (nonatomic) NSRect ball;
@property (nonatomic) NSPoint ballVelocity;
@property (nonatomic) NSInteger leftScore;
@property (nonatomic) NSInteger rightScore;
@property (nonatomic) BOOL isRunning;
@property (nonatomic) BOOL movingUp;
@property (nonatomic) BOOL movingDown;
@end

@implementation PongView

static const CGFloat kPaddleWidth = 10.0;
static const CGFloat kPaddleHeight = 90.0;
static const CGFloat kPaddleInset = 16.0;
static const CGFloat kBallSize = 14.0;
static const CGFloat kInitialBallSpeed = 260.0;
static const CGFloat kMaxBallSpeed = 720.0;
static const CGFloat kBallSpeedIncrement = 24.0;
static const CGFloat kAIMaxSpeed = 260.0;
static const CGFloat kPlayerSpeed = 480.0;

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        [self commonInit];
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self commonInit];
}

- (BOOL)isFlipped { return YES; }

- (BOOL)acceptsFirstResponder { return YES; }

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self.window makeFirstResponder:self];
}

- (void)commonInit {
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.blackColor.CGColor;

    [self resetState];

    // Enable tracking for mouse dragging
    NSTrackingArea *tracking = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                            options:NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                                              owner:self
                                                           userInfo:nil];
    [self addTrackingArea:tracking];
}

- (void)resetState {
    CGFloat midY = NSHeight(self.bounds) * 0.5;
    _leftPaddle = NSMakeRect(kPaddleInset, midY - kPaddleHeight * 0.5, kPaddleWidth, kPaddleHeight);
    _rightPaddle = NSMakeRect(NSWidth(self.bounds) - kPaddleInset - kPaddleWidth, midY - kPaddleHeight * 0.5, kPaddleWidth, kPaddleHeight);
    _ball = NSMakeRect(NSWidth(self.bounds) * 0.5 - kBallSize * 0.5, midY - kBallSize * 0.5, kBallSize, kBallSize);

    CGFloat angle = ((arc4random_uniform(41) - 20) * M_PI / 180.0); // -20..20 deg
    CGFloat dirX = (arc4random_uniform(2) == 0) ? -1.0 : 1.0;
    _ballVelocity = NSMakePoint(cos(angle) * kInitialBallSpeed * dirX, sin(angle) * kInitialBallSpeed);
}

- (void)startGame {
    if (self.isRunning) return;
    self.isRunning = YES;
    self.lastTimestamp = CACurrentMediaTime();
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0/120.0
                                                  target:self
                                                selector:@selector(step)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)pauseGame {
    self.isRunning = NO;
    [self.timer invalidate];
    self.timer = nil;
    self.movingUp = NO;
    self.movingDown = NO;
}

- (void)resetGame {
    [self pauseGame];
    self.leftScore = 0;
    self.rightScore = 0;
    [self resetState];
    self.movingUp = NO;
    self.movingDown = NO;
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    // Move the right paddle with the mouse
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat newY = loc.y - kPaddleHeight * 0.5;
    newY = fmax(0, fmin(newY, NSHeight(self.bounds) - kPaddleHeight));
    _rightPaddle.origin.y = newY;
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event { [self startGame]; }
- (void)rightMouseDown:(NSEvent *)event { [self pauseGame]; }

- (void)keyDown:(NSEvent *)event {
    // Handle arrow keys via keyCode and WASD via characters
    switch (event.keyCode) {
        case 126: // Up arrow
            self.movingUp = YES;
            return;
        case 125: // Down arrow
            self.movingDown = YES;
            return;
        default:
            break;
    }
    NSString *chars = event.charactersIgnoringModifiers.lowercaseString;
    if ([chars containsString:@"w"]) { self.movingUp = YES; return; }
    if ([chars containsString:@"s"]) { self.movingDown = YES; return; }
    [super keyDown:event];
}

- (void)keyUp:(NSEvent *)event {
    switch (event.keyCode) {
        case 126: // Up arrow
            self.movingUp = NO;
            return;
        case 125: // Down arrow
            self.movingDown = NO;
            return;
        default:
            break;
    }
    NSString *chars = event.charactersIgnoringModifiers.lowercaseString;
    if ([chars containsString:@"w"]) { self.movingUp = NO; return; }
    if ([chars containsString:@"s"]) { self.movingDown = NO; return; }
    [super keyUp:event];
}

- (void)step {
    if (!self.isRunning) return;
    NSTimeInterval now = CACurrentMediaTime();
    NSTimeInterval dt = now - self.lastTimestamp;
    self.lastTimestamp = now;

    // Keyboard-controlled player movement
    CGFloat playerY = _rightPaddle.origin.y;
    CGFloat delta = kPlayerSpeed * dt;
    if (self.movingUp) { playerY -= delta; }
    if (self.movingDown) { playerY += delta; }
    playerY = fmax(0, fmin(playerY, NSHeight(self.bounds) - kPaddleHeight));
    _rightPaddle.origin.y = playerY;

    // Move ball
    _ball.origin.x += self.ballVelocity.x * dt;
    _ball.origin.y += self.ballVelocity.y * dt;

    // Wall collisions
    if (NSMinY(_ball) <= 0) {
        _ball.origin.y = 0;
        self.ballVelocity = NSMakePoint(self.ballVelocity.x, -self.ballVelocity.y);
    } else if (NSMaxY(_ball) >= NSHeight(self.bounds)) {
        _ball.origin.y = NSHeight(self.bounds) - NSHeight(_ball);
        self.ballVelocity = NSMakePoint(self.ballVelocity.x, -self.ballVelocity.y);
    }

    // AI movement (left paddle)
    [self updateAIWithDeltaTime:dt targetY:NSMidY(_ball) ballMovingLeft:(self.ballVelocity.x < 0)];

    // Paddle collisions
    if (NSIntersectsRect(_ball, _rightPaddle) && self.ballVelocity.x > 0) {
        _ball.origin.x = NSMinX(_rightPaddle) - NSWidth(_ball);
        [self reflectFromPaddleCenterY:NSMidY(_rightPaddle)];
    }
    if (NSIntersectsRect(_ball, _leftPaddle) && self.ballVelocity.x < 0) {
        _ball.origin.x = NSMaxX(_leftPaddle);
        [self reflectFromPaddleCenterY:NSMidY(_leftPaddle)];
    }

    // Scoring
    if (NSMaxX(_ball) < 0) {
        self.rightScore += 1;
        [self serveTowardRight:YES];
    } else if (NSMinX(_ball) > NSWidth(self.bounds)) {
        self.leftScore += 1;
        [self serveTowardRight:NO];
    }

    [self setNeedsDisplay:YES];
}

- (void)updateAIWithDeltaTime:(NSTimeInterval)dt targetY:(CGFloat)targetY ballMovingLeft:(BOOL)ballMovingLeft {
    CGFloat desired = ballMovingLeft ? targetY - kPaddleHeight * 0.5 : NSHeight(self.bounds) * 0.5 - kPaddleHeight * 0.5;
    CGFloat distance = desired - _leftPaddle.origin.y;
    CGFloat maxStep = kAIMaxSpeed * dt;
    CGFloat step = fmax(-maxStep, fmin(maxStep, distance));
    _leftPaddle.origin.y = fmax(0, fmin(_leftPaddle.origin.y + step, NSHeight(self.bounds) - kPaddleHeight));
}

- (void)reflectFromPaddleCenterY:(CGFloat)centerY {
    CGFloat ballCenterY = NSMidY(_ball);
    CGFloat offset = (ballCenterY - centerY) / (kPaddleHeight * 0.5); // -1..1
    offset = fmax(-1, fmin(1, offset));

    CGFloat speed = hypot(self.ballVelocity.x, self.ballVelocity.y) + kBallSpeedIncrement;
    speed = fmin(speed, kMaxBallSpeed);

    CGFloat maxAngle = 50.0 * M_PI / 180.0;
    CGFloat angle = offset * maxAngle;
    CGFloat signX = (self.ballVelocity.x > 0) ? -1.0 : 1.0;

    self.ballVelocity = NSMakePoint(cos(angle) * speed * signX, sin(angle) * speed);
}

- (void)serveTowardRight:(BOOL)towardRight {
    _ball.origin.x = NSWidth(self.bounds) * 0.5 - kBallSize * 0.5;
    _ball.origin.y = NSHeight(self.bounds) * 0.5 - kBallSize * 0.5;

    CGFloat angle = ((arc4random_uniform(41) - 20) * M_PI / 180.0);
    CGFloat dirX = towardRight ? 1.0 : -1.0;
    self.ballVelocity = NSMakePoint(cos(angle) * kInitialBallSpeed * dirX, sin(angle) * kInitialBallSpeed);
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = self.bounds;
    [NSColor.blackColor setFill];
    NSRectFill(bounds);

    // Center dashed line
    CGFloat dashHeight = 10.0;
    CGFloat dashSpacing = 8.0;
    CGFloat x = NSMidX(bounds) - 1.5;
    for (CGFloat y = 0; y < NSHeight(bounds); y += dashHeight + dashSpacing) {
        NSRect dash = NSMakeRect(x, y, 3.0, dashHeight);
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.35] setFill];
        NSRectFill(dash);
    }

    // Paddles
    [[NSColor whiteColor] setFill];
    NSBezierPath *leftPaddlePath = [NSBezierPath bezierPathWithRoundedRect:_leftPaddle xRadius:4 yRadius:4];
    [leftPaddlePath fill];
    NSBezierPath *rightPaddlePath = [NSBezierPath bezierPathWithRoundedRect:_rightPaddle xRadius:4 yRadius:4];
    [rightPaddlePath fill];

    // Ball
    NSBezierPath *ballPath = [NSBezierPath bezierPathWithOvalInRect:_ball];
    [ballPath fill];

    // Score
    NSDictionary *attrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:48 weight:NSFontWeightBold],
                             NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:1 alpha:0.9] };

    NSString *leftText = [NSString stringWithFormat:@"%ld", (long)self.leftScore];
    NSString *rightText = [NSString stringWithFormat:@"%ld", (long)self.rightScore];

    NSSize rightSize = [rightText sizeWithAttributes:attrs];

    [leftText drawAtPoint:NSMakePoint(20, 10) withAttributes:attrs];
    [rightText drawAtPoint:NSMakePoint(NSWidth(bounds) - rightSize.width - 20, 10) withAttributes:attrs];
}

@end

