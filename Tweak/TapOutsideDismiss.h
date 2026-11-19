//
//  TapOutsideDismiss.h
//  Kayoko
//
//  Shared tap-outside-to-dismiss geometry and decision helpers.
//
//  Used by KayokoCore (SpringBoard) and KayokoHelper (apps) so the panel
//  dismisses when the user taps outside of it, both on the home screen and
//  while a third party app is in the foreground.
//

#import <CoreGraphics/CoreGraphics.h>

static CGFloat const kKayokoPanelHeight = 420;

/**
 * Computes the panel frame in screen coordinates.
 *
 * Mirrors KayokoPanelFrame(KayokoGeometry.h) used by the core to lay out the
 * panel at the bottom of the screen with a small gap on the sides.
 */
static inline CGRect KayokoTapOutsidePanelFrame(CGRect screenBounds, CGFloat height) {
    CGFloat gap = CGRectGetWidth(screenBounds) * 0.01;
    return CGRectMake(CGRectGetMinX(screenBounds) + gap,
                      CGRectGetMaxY(screenBounds) - gap - height,
                      CGRectGetWidth(screenBounds) - 2 * gap,
                      height);
}

/**
 * Returns YES when a touch at the given point (in the panel's coordinate
 * space) falls outside of the panel and should dismiss it.
 */
static inline BOOL KayokoTapOutsideShouldDismiss(CGRect panelFrame, CGPoint point) {
    return !CGRectContainsPoint(panelFrame, point);
}
