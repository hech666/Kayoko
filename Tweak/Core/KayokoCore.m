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
    if (CFAbsoluteTimeGetCurrent() < squidShowSuppressHideUntil) {
        return;
    }
    if (kayokoView && ![kayokoView isHidden]) {
        [kayokoView hide];
    }
}

/**
 * Reloads the history.
 */
static void reload() {
    if (kayokoView && ![kayokoView isHidden]) {
        [kayokoView reload];
    }
}

#pragma mark - Preferences

/**
 * Loads the user's preferences.
 */
static void load_preferences() {
    preferences = [[NSUserDefaults alloc] initWithSuiteName:kPreferencesIdentifier];

    [preferences registerDefaults:@{
        kPreferenceKeyEnabled: @(kPreferenceKeyEnabledDefaultValue),
        kPreferenceKeyMaximumHistoryAmount: @(kMaximumHistoryAmountDefaultValue),
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
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)hide, (CFStringRef)kNotificationKeyLegacyCoreHide, NULL, (CFNotificationSuspensionBehavior)kNilOptions);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)reload, (CFStringRef)kNotificationKeyCoreReload, NULL, (CFNotificationSuspensionBehavior)kNilOptions);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)load_preferences, (CFStringRef)kNotificationKeyPreferencesReload, NULL, (CFNotificationSuspensionBehavior)kNilOptions);

    install_squid_compatibility_hook(0);
}
