#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <math.h>

static inline CGRect KayokoPanelFrame(CGRect screenBounds, CGFloat height) {
    CGFloat gap = CGRectGetWidth(screenBounds) * 0.01;
    return CGRectMake(CGRectGetMinX(screenBounds) + gap,
                      CGRectGetMaxY(screenBounds) - gap - height,
                      CGRectGetWidth(screenBounds) - 2 * gap, height);
}

static inline CGFloat KayokoBottomRadius(UIScreen *screen, CGFloat gap) {
    SEL selector = NSSelectorFromString(@"_displayCornerRadius");
    CGFloat radius = 0;
    if ([screen respondsToSelector:selector]) {
        radius = ((CGFloat (*)(id, SEL))objc_msgSend)(screen, selector);
    }
    // Preserve a safe rounded fallback on systems without the private getter.
    if (!isfinite(radius) || radius <= 0) return 35;
    return MAX(0, radius - gap);
}

static inline UIBezierPath *KayokoPanelPath(CGRect rect, CGFloat top, CGFloat bottom) {
    CGFloat limit = MIN(CGRectGetWidth(rect), CGRectGetHeight(rect)) / 2;
    top = MIN(MAX(0, top), limit);
    bottom = MIN(MAX(0, bottom), limit);
    CGFloat x = CGRectGetMinX(rect), y = CGRectGetMinY(rect);
    CGFloat r = CGRectGetMaxX(rect), b = CGRectGetMaxY(rect);
    const CGFloat c = 0.5522847498307936;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(x + top, y)];
    [path addLineToPoint:CGPointMake(r - top, y)];
    [path addCurveToPoint:CGPointMake(r, y + top) controlPoint1:CGPointMake(r - top + c * top, y) controlPoint2:CGPointMake(r, y + top - c * top)];
    [path addLineToPoint:CGPointMake(r, b - bottom)];
    [path addCurveToPoint:CGPointMake(r - bottom, b) controlPoint1:CGPointMake(r, b - bottom + c * bottom) controlPoint2:CGPointMake(r - bottom + c * bottom, b)];
    [path addLineToPoint:CGPointMake(x + bottom, b)];
    [path addCurveToPoint:CGPointMake(x, b - bottom) controlPoint1:CGPointMake(x + bottom - c * bottom, b) controlPoint2:CGPointMake(x, b - bottom + c * bottom)];
    [path addLineToPoint:CGPointMake(x, y + top)];
    [path addCurveToPoint:CGPointMake(x + top, y) controlPoint1:CGPointMake(x, y + top - c * top) controlPoint2:CGPointMake(x + top - c * top, y)];
    [path closePath];
    return path;
}
