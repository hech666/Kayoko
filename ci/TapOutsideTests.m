#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

static NSUInteger checks;
#define CHECK(x) do { checks++; if (!(x)) { NSLog(@"FAIL line %d: %s", __LINE__, #x); exit(1); } } while (0)

#import "../Tweak/TapOutsideDismiss.h"

int main(void) {
 @autoreleasepool {
    // iPhone 15 Pro (393x852) screen geometry.
    CGRect bounds = CGRectMake(0, 0, 393, 852);
    CGRect panel = KayokoTapOutsidePanelFrame(bounds, kKayokoPanelHeight);

    // Gap is 1% of width on each side, panel sits at the bottom.
    CHECK(fabs(CGRectGetMinX(panel) - 3.93) < 0.001);
    CHECK(fabs(CGRectGetWidth(panel) - (393 - 2 * 3.93)) < 0.001);
    CHECK(fabs(CGRectGetHeight(panel) - kKayokoPanelHeight) < 0.001);
    CHECK(fabs(CGRectGetMaxY(panel) - (852 - 3.93)) < 0.001);

    // Points inside the panel do not dismiss.
    CHECK(!KayokoTapOutsideShouldDismiss(panel, CGPointMake(CGRectGetMidX(panel), CGRectGetMidY(panel))));
    // Points at the very top edge of the panel are inside.
    CHECK(!KayokoTapOutsideShouldDismiss(panel, CGPointMake(CGRectGetMidX(panel), CGRectGetMinY(panel) + 1)));
    // Points outside (above the panel, in the top corners) dismiss.
    CHECK(KayokoTapOutsideShouldDismiss(panel, CGPointMake(5, 100)));
    CHECK(KayokoTapOutsideShouldDismiss(panel, CGPointMake(300, 200)));
    // Points to the left/right of the panel dismiss.
    CHECK(KayokoTapOutsideShouldDismiss(panel, CGPointMake(1, CGRectGetMidY(panel))));
    CHECK(KayokoTapOutsideShouldDismiss(panel, CGPointMake(392, CGRectGetMidY(panel))));
    // Point below the panel dismisses.
    CHECK(KayokoTapOutsideShouldDismiss(panel, CGPointMake(CGRectGetMidX(panel), 851)));

    // The panel height constant must be positive and sane.
    CHECK(kKayokoPanelHeight > 0 && kKayokoPanelHeight < bounds.size.height);

    // Landscape geometry still puts the panel at the bottom of the short edge.
    CGRect land = CGRectMake(0, 0, 852, 393);
    CGRect landPanel = KayokoTapOutsidePanelFrame(land, kKayokoPanelHeight);
    CHECK(fabs(CGRectGetMaxY(landPanel) - (393 - 8.52)) < 0.001);

    NSLog(@"PASS: %lu checks, panel frame geometry, inside/outside dismissal, landscape", (unsigned long)checks);
 }
 return 0;
}
