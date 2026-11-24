//
//  KayokoCore.m
//  Kayoko
//
//  Created by Alexandra Aurora Göttlicher
//

#import "KayokoCore.h"
#import <substrate.h>
#import <objc/runtime.h>
#import <os/log.h>
#import "../../Manager/PasteboardManager.h"
#import "Views/KayokoView.h"
#import "Views/KayokoGeometry.h"
#import "../../Preferences/PreferenceKeys.h"
#import "../../Preferences/NotificationKeys.h"
#import "../TapOutsideDismiss.h"

#ifndef APELIN_BUILD_ID
#define APELIN_BUILD_ID "unknown"
#endif

#pragma mark - UIStatusBarWindow class hooks

/**
 * Sets up the history view.
 *
 * Using the status bar's window is hacky, yet it's present on SpringBoard and in apps.
 * It's important to note that it runs on the SpringBoard process too, which gives us file system read/write.
 *
 * @param frame
 */
static id (* orig_UIStatusBarWindow_initWithFrame)(UIStatusBarWindow* self, SEL _cmd, CGRect frame);
static id override_UIStatusBarWindow_initWithFrame(UIStatusBarWindow* self, SEL _cmd, CGRect frame) {
    UIStatusBarWindow *window = orig_UIStatusBarWindow_initWithFrame(self, _cmd, frame);
    if (window && !kayokoView) {
        UIScreen *screen = window.screen ?: UIScreen.mainScreen;
        CGRect panelFrame = KayokoPanelFrame(screen.bounds, kHeight);
        kayokoView = [[KayokoView alloc] initWithFrame:panelFrame];
        [kayokoView setAutomaticallyPaste:pfAutomaticallyPaste];
        [window addSubview:kayokoView];
    }
    return window;
}

#pragma mark - Notification callbacks

/**
 * Receives the notification that the pasteboard changed from the daemon and pulls the new changes.
 */
static void pasteboard_changed() {
    [[PasteboardManager sharedInstance] pullPasteboardChanges];
}

/**
 * Shows the history after the status-bar window has created the panel.
 * Darwin callbacks may arrive before UIKit finishes creating UIStatusBarWindow.
 */
static CFAbsoluteTime squidShowSuppressHideUntil = 0;

static void show_on_main_thread(NSUInteger attempt) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            show_on_main_thread(attempt);
        });
        return;
    }

    if (kayokoView) {
        if ([kayokoView isHidden]) {
            [kayokoView show];
        }
        return;
    }

    // The action can arrive before UIStatusBarWindow has finished loading.
    if (attempt < 10) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                show_on_main_thread(attempt + 1);
            });
    }
}

static void show() {
    show_on_main_thread(0);
}

#pragma mark - SquidGesturePro compatibility

static BOOL squidCompatibilityHookInstalled = NO;
static void (*orig_SGActionStore_showCopyVaultHistory)(id self, SEL _cmd);

static void hook_SGActionStore_showCopyVaultHistory(id self, SEL _cmd) {
    if (orig_SGActionStore_showCopyVaultHistory) {
        orig_SGActionStore_showCopyVaultHistory(self, _cmd);
    }

    // Squid 2.7.x exposes this stable selector for its clipboard-history action.
    // Suppress the keyboard-dismiss hide callback that may follow this gesture.
    squidShowSuppressHideUntil = CFAbsoluteTimeGetCurrent() + 1.0;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (CFStringRef)kNotificationKeyCoreShow, NULL, NULL, YES);
}

static void install_squid_compatibility_hook(NSUInteger attempt) {
    if (squidCompatibilityHookInstalled) {
        return;
    }

    Class actionStore = objc_getClass("SGActionStore");
    SEL selector = NSSelectorFromString(@"sg_showCopyVaultHistory");
    if (actionStore && class_getInstanceMethod(actionStore, selector)) {
        MSHookMessageEx(actionStore, selector, (IMP)&hook_SGActionStore_showCopyVaultHistory,
            (IMP *)&orig_SGActionStore_showCopyVaultHistory);
        squidCompatibilityHookInstalled = YES;
        return;
    }

    // Squid may load after Kayoko's constructor.
    if (attempt < 10) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                install_squid_compatibility_hook(attempt + 1);
            });
    }
}

/**
 * Hides the history.
 */
static void hide() {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ hide(); });
        return;
    }
    if (CFAbsoluteTimeGetCurrent() < squidShowSuppressHideUntil) {
        return;
    }
    if (kayokoView && ![kayokoView isHidden]) {
        [kayokoView hide];
    } else {
        // Hide is an idempotent state transition. The App helper may still hold
        // an old visibility hint after SpringBoard recreated the panel.
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            (CFStringRef)kNotificationKeyPanelDidHide, NULL, NULL, YES);
    }
}

static void hide_outside() {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ hide_outside(); });
        return;
    }
    if (kayokoView && ![kayokoView isHidden]) {
        [kayokoView hide];
    } else {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            (CFStringRef)kNotificationKeyPanelDidHide, NULL, NULL, YES);
    }
}

#pragma mark - Tap outside to dismiss

/**
 * Dismisses the panel when a touch lands outside of it.
 *
 * The panel lives inside SpringBoard's UIStatusBarWindow. On the home screen that
 * window receives touches and can dismiss the panel itself. In a foreground third
 * party app the touch may be delivered to the app's own key window instead, which
 * KayokoHelper handles via a Darwin notification (see KayokoHelper.m).
 */
static UIView* (* orig_UIWindow_hitTest)(UIWindow* self, SEL _cmd, CGPoint point, UIEvent* event);
static UIView* override_UIWindow_hitTest(UIWindow* self, SEL _cmd, CGPoint point, UIEvent* event) {
    UIView* result = orig_UIWindow_hitTest(self, _cmd, point, event);
    if (kayokoView && ![kayokoView isHidden] && kayokoView.alpha > 0.01 && kayokoView.window) {
        CGPoint pointInPanel = [kayokoView convertPoint:[self convertPoint:point toView:nil] fromView:nil];
        if (KayokoTapOutsideShouldDismiss(kayokoView.bounds, pointInPanel)) {
            [kayokoView hide];
            return nil;
        }
    }
    return result;
}

/**
 * Hook for UIStatusBarWindow's own hitTest implementation (if it overrides the
 * base UIWindow method), so touches on the status bar window itself also dismiss.
 */
static UIView* (* orig_UIStatusBarWindow_hitTest)(UIStatusBarWindow* self, SEL _cmd, CGPoint point, UIEvent* event);
static UIView* override_UIStatusBarWindow_hitTest(UIStatusBarWindow* self, SEL _cmd, CGPoint point, UIEvent* event) {
    UIView* result = orig_UIStatusBarWindow_hitTest(self, _cmd, point, event);
    if (kayokoView && ![kayokoView isHidden] && kayokoView.alpha > 0.01 && kayokoView.window) {
        CGPoint pointInPanel = [kayokoView convertPoint:[self convertPoint:point toView:nil] fromView:nil];
        if (KayokoTapOutsideShouldDismiss(kayokoView.bounds, pointInPanel)) {
            [kayokoView hide];
            return nil;
        }
    }
    return result;
}

/**
 * Installs the tap-outside-to-dismiss hooks.
 */
static void install_tap_outside_to_dismiss_hooks(void) {
    Class windowClass = objc_getClass("UIWindow");
    if (!windowClass) {
        return;
    }
    SEL hitSelector = @selector(hitTest:withEvent:);
    if (class_getInstanceMethod(windowClass, hitSelector)) {
        MSHookMessageEx(windowClass, hitSelector, (IMP)&override_UIWindow_hitTest, (IMP *)&orig_UIWindow_hitTest);
    }

    Class statusBarWindowClass = objc_getClass("UIStatusBarWindow");
    if (statusBarWindowClass && statusBarWindowClass != windowClass) {
        Method ownMethod = class_getInstanceMethod(statusBarWindowClass, hitSelector);
        Method baseMethod = class_getInstanceMethod(windowClass, hitSelector);
        // Only hook separately if UIStatusBarWindow really overrides hitTest.
        if (ownMethod && baseMethod && ownMethod != baseMethod) {
            MSHookMessageEx(statusBarWindowClass, hitSelector, (IMP)&override_UIStatusBarWindow_hitTest, (IMP *)&orig_UIStatusBarWindow_hitTest);
        }
    }
}

/**
 * Reloads the history.
 */
static void reload() {
    [[PasteboardManager sharedInstance] reloadHistoryAsync];
}

#pragma mark - Preferences

/**
 * Loads the user's preferences.
 */
static void load_preferences() {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ load_preferences(); });
        return;
    }
    preferences = [[NSUserDefaults alloc] initWithSuiteName:kPreferencesIdentifier];

    [preferences registerDefaults:@{
        kPreferenceKeyEnabled: @(kPreferenceKeyEnabledDefaultValue),
        kPreferenceKeyMaximumHistoryAmount: @(kPreferenceKeyMaximumHistoryAmountDefaultValue),
        kPreferenceKeySaveText: @(kPreferenceKeySaveTextDefaultValue),
        kPreferenceKeySaveImages: @(kPreferenceKeySaveImagesDefaultValue),
        kPreferenceKeyAutomaticallyPaste: @(kPreferenceKeyAutomaticallyPasteDefaultValue)
    }];

    pfEnabled = [[preferences objectForKey:kPreferenceKeyEnabled] boolValue];
    pfMaximumHistoryAmount = [[preferences objectForKey:kPreferenceKeyMaximumHistoryAmount] unsignedIntegerValue];
    pfSaveText = [[preferences objectForKey:kPreferenceKeySaveText] boolValue];
    pfSaveImages = [[preferences objectForKey:kPreferenceKeySaveImages] boolValue];
    pfAutomaticallyPaste = [[preferences objectForKey:kPreferenceKeyAutomaticallyPaste] boolValue];

    [[PasteboardManager sharedInstance] setMaximumHistoryAmount:pfMaximumHistoryAmount];
    [[PasteboardManager sharedInstance] setSaveText:pfSaveText];
    [[PasteboardManager sharedInstance] setSaveImages:pfSaveImages];
    [[PasteboardManager sharedInstance] setAutomaticallyPaste:pfAutomaticallyPaste];

    [kayokoView setAutomaticallyPaste:pfAutomaticallyPaste];
}

#pragma mark - Constructor

/**
 * Initializes the core.
 *
 * First it loads the preferences and continues if Kayoko is enabled.
 * Secondly it sets up the hooks.
 * Finally it registers the notification callbacks.
 */
__attribute((constructor)) static void initialize() {
    os_log_t apelinLog = os_log_create("codes.aurora.kayoko", "apelin");
    os_log(apelinLog, "ApelinLoaded %{public}s", APELIN_BUILD_ID);

    load_preferences();

    if (!pfEnabled) {
        return;
    }

    MSHookMessageEx(objc_getClass("UIStatusBarWindow"), @selector(initWithFrame:), (IMP)&override_UIStatusBarWindow_initWithFrame, (IMP *)&orig_UIStatusBarWindow_initWithFrame);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)pasteboard_changed, (CFStringRef)kNotificationKeyObserverPasteboardChanged, NULL, (CFNotificationSuspensionBehavior)kNilOptions);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)show, (CFStringRef)kNotificationKeyCoreShow, NULL, (CFNotificationSuspensionBehavior)kNilOptions);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)show, (CFStringRef)kNotificationKeyLegacyCoreShow, NULL, (CFNotificationSuspensionBehavior)kNilOptions);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)hide, (CFStringRef)kNotificationKeyCoreHide, NULL, (CFNotificationSuspensionBehavior)kNilOptions);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)hide_outside, (CFStringRef)kNotificationKeyCoreHideOutside, NULL, (CFNotificationSuspensionBehavior)kNilOptions);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)hide, (CFStringRef)kNotificationKeyLegacyCoreHide, NULL, (CFNotificationSuspensionBehavior)kNilOptions);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)reload, (CFStringRef)kNotificationKeyCoreReload, NULL, (CFNotificationSuspensionBehavior)kNilOptions);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)load_preferences, (CFStringRef)kNotificationKeyPreferencesReload, NULL, (CFNotificationSuspensionBehavior)kNilOptions);

    [[NSNotificationCenter defaultCenter] addObserverForName:KayokoHistoryDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (kayokoView && !kayokoView.hidden) [kayokoView reload];
    }];
    install_tap_outside_to_dismiss_hooks();
    install_squid_compatibility_hook(0);
}
