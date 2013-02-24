//
//  DPFilledPathView.m
//  DPValueMeterView
//
//  Created by Pierre Dulac on 27/01/13.
//  Copyright (c) 2013 Pierre Dulac. All rights reserved.
//

#import "DPMeterView.h"

#import <QuartzCore/QuartzCore.h>
#import <CoreMotion/CoreMotion.h>


@interface DPMeterView ()

@property (nonatomic, readonly) CAGradientLayer* gradientLayer;
@property (nonatomic, strong) CMMotionManager* motionManager;
@property (nonatomic, strong) CADisplayLink* motionDisplayLink;
@property (nonatomic) float motionLastYaw;

- (void)commonInit;
- (NSArray *)gradientLocations:(CGFloat)progress;
- (void)initialGradientOrientation;
- (void)motionRefresh:(id)sender;

@end


@implementation DPMeterView

+ (Class)layerClass
{
    return [CAGradientLayer class];
}

- (CAGradientLayer *)gradientLayer
{
    return (CAGradientLayer*)self.layer;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return nil;
    }
    
    [self commonInit];
    
    return self;
}

- (id)initWithFrame:(CGRect)frame shape:(CGPathRef)shape
{
    return [self initWithFrame:frame shape:shape gravity:NO];
}

- (id)initWithFrame:(CGRect)frame shape:(CGPathRef)shape gravity:(BOOL)gravity
{
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }
    
    [self commonInit];
    
    // use the shape as a mask
    [self setShape:shape];
    
    // gravity motion
    if (gravity) {
        [self startGravity];            
    }

    return self;
}

- (void)commonInit
{
    self.backgroundColor = [UIColor clearColor];
    self.trackTintColor = [UIColor greenColor];
    self.progressTintColor = [UIColor blueColor];
    
    [self initialGradientOrientation];
    self.gradientLayer.locations = @[@0.f, @0.f];
    self.progress = 0.f;
}

- (void)initialGradientOrientation
{
    self.gradientLayer.startPoint = CGPointMake(0.5f, 1.f);
    self.gradientLayer.endPoint = CGPointMake(0.5f, 0.f);
}

- (void)didMoveToWindow
{
    self.gradientLayer.contentsScale = [UIScreen mainScreen].scale;
}


#pragma mark - Setters & Getters

- (void)setShape:(CGPathRef)shape
{
    CAShapeLayer* maskLayer = [CAShapeLayer layer];
    maskLayer.path = shape;
    self.gradientLayer.mask = maskLayer;
}

- (CGRect)shapeBounds
{
    return CGPathGetPathBoundingBox([(CAShapeLayer *)self.gradientLayer.mask path]);
}

- (void)updateGradientColors
{
    self.gradientLayer.colors = [[NSArray alloc] initWithObjects:
                                 (id)self.progressTintColor.CGColor,
                                 (id)self.trackTintColor.CGColor, nil];
    [self.gradientLayer setNeedsDisplay];
}

- (void)setTrackTintColor:(UIColor *)trackTintColor
{
    if (trackTintColor != _trackTintColor) {
        _trackTintColor = trackTintColor;
        [self updateGradientColors];
    }
}

- (void)setProgressTintColor:(UIColor *)progressTintColor
{
    if (progressTintColor != _progressTintColor) {
        _progressTintColor = progressTintColor;
        [self updateGradientColors];
    }
}


#pragma mark - Progress

- (CGFloat)rescaledProgress:(CGFloat)progress
{
    // make sure again that it's a percentage
    CGFloat pinnedProgress = MIN(MAX(progress, 0.f), 1.f);
    
    // get the bounding box of the mask shape
    CGRect bounds = [self shapeBounds];
    
    if (CGRectIsEmpty(bounds)) {
        return pinnedProgress;
    }
    
    // rescale the progress against the shape height
    CGFloat scaledProgress = pinnedProgress * CGRectGetHeight(bounds);
    
    // translate the progress to the beginning of the shape
    // NB: the coordinates of Apple are (0,0) at the top left
    scaledProgress += (self.bounds.size.height - CGRectGetMaxY(bounds));
    
    // convert into a percentage
    scaledProgress /= self.bounds.size.height;
    
    return scaledProgress;
}

- (NSArray *)gradientLocations:(CGFloat)progress
{
    CGFloat rescaledProgress = [self rescaledProgress:progress];
    return @[[NSNumber numberWithFloat:rescaledProgress], [NSNumber numberWithFloat:rescaledProgress]];
}

- (void)setProgress:(CGFloat)progress
{
    [self setProgress:progress animated:NO];
}

- (void)setProgress:(CGFloat)progress animated:(BOOL)animated
{
    CGFloat pinnedProgress = MIN(MAX(progress, 0.f), 1.f);
    NSArray* newLocations = [self gradientLocations:pinnedProgress];
    
    if (animated)
    {
        NSTimeInterval duration = 0.5;
        [UIView animateWithDuration:duration animations:^{
            CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"locations"];
            animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            animation.duration = duration;
            animation.delegate = self;
            animation.fromValue = self.gradientLayer.locations;
            animation.toValue = newLocations;
            [self.gradientLayer addAnimation:animation forKey:@"animateLocations"];
        }];
    }
    else
    {
        [self.gradientLayer setNeedsDisplay];
    }
    
    self.gradientLayer.locations = newLocations;
    _progress = pinnedProgress;
}

- (void)minus:(CGFloat)delta
{
    [self minus:delta animated:NO];
}

- (void)minus:(CGFloat)delta animated:(BOOL)animated
{
    [self setProgress:(self.progress - delta) animated:animated];
}

- (void)add:(CGFloat)delta
{
    [self add:delta animated:NO];
}

- (void)add:(CGFloat)delta animated:(BOOL)animated
{
    [self setProgress:(self.progress + delta) animated:animated];
}


#pragma mark - Gravity Motion

- (CGFloat)currentYaw
{
    return 0.5f - self.gradientLayer.startPoint.x;
}

- (void)motionRefresh:(id)sender
{
    // retrieve data
    double yaw = self.motionManager.deviceMotion.attitude.yaw;
    
    // ensure that yaw stays between [-PI/2, +PI/2]
    // TODO find a better way to do that, and why it doesn't work if the device is face down..
    if (yaw < -M_PI_2) yaw += M_PI_2;
    if (yaw > M_PI_2) yaw -= M_PI_2;
    
    // damping coefficient
    float d = 2.0;
    yaw /= d;
    
    if (self.motionLastYaw == 0) {
        self.motionLastYaw = yaw;
    }
    
    // kalman filtering
    static float q = 0.1;   // process noise
    static float r = 0.1;   // sensor noise
    static float p = 0.1;   // estimated error
    static float k = 0.2;   // kalman filter gain
    
    float x = self.motionLastYaw;
    p = p + q;
    k = p / (p + r);
    x = x + k*(yaw - x);
    p = (1 - k)*p;
    self.motionLastYaw = x;
    
    // compute the horizon yaw
    float m = sin(x);
    
    // update starting & ending point of the gradient
    self.gradientLayer.startPoint = CGPointMake(0.5f-m, 1.f);
    self.gradientLayer.endPoint = CGPointMake(0.5f, 0.f);
    
    [self.gradientLayer setNeedsDisplay];
}

- (BOOL)isGravityActive
{
    return self.motionDisplayLink != nil;
}

- (void)startGravity
{
    if ( ! [self isGravityActive]) {
        self.motionManager = [[CMMotionManager alloc] init];
        self.motionManager.deviceMotionUpdateInterval = 0.02; // 50 Hz
        
        self.motionLastYaw = 0;
        self.motionDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(motionRefresh:)];
        [self.motionDisplayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    }
    if ([self.motionManager isDeviceMotionAvailable])
        [self.motionManager startDeviceMotionUpdates];
}

- (void)stopGravity
{
    if ([self isGravityActive]) {
        [self.motionDisplayLink invalidate];
        self.motionDisplayLink = nil;
        self.motionLastYaw = 0;
        
        // reset the gradient orientation
        [self initialGradientOrientation];
        
        self.motionManager = nil;   // release the motion manager memory
    }
    if ([self.motionManager isDeviceMotionActive])
        [self.motionManager stopDeviceMotionUpdates];
}

@end
