//
//  KayokoHelper.m
//  Kayoko
//
//  Created by Alexandra Aurora Göttlicher
//

#import "KayokoHelper.h"
#import <substrate.h>
#import <libSandy.h>
#import "../../Manager/PasteboardManager.h"
#import "../../Manager/PasteboardItem.h"
#import "../../Preferences/NotificationKeys.h"
#import "../../Preferences/PreferenceKeys.h"
#import "KayokoDictationActivation.h"

static void load_preferences(void);
static void kayoko_helper_install_activation_hooks(void);

#pragma mark - UIKeyboardAutocorrectionController class hooks

/**
 * Updates the prediction bar with the original or custom items.
 *
 * This method usage only works on iOS 14 or lower.
 *
 * @param textSuggestionList The list that is used to update the prediciton bar with.
 */
static void (* orig_UIKeyboardAutocorrectionController_setTextSuggestionList)(UIKeyboardAutocorrectionController* self, SEL _cmd, TIAutocorrectionList* textSuggestionList);
static void override_UIKeyboardAutocorrectionController_setTextSuggestionList(UIKeyboardAutocorrectionController* self, SEL _cmd, TIAutocorrectionList* textSuggestionList) {
    if (pfEnabled && pfActivationMethod == kActivationMethodPredictionBar && shouldShowCustomSuggestions) {
        orig_UIKeyboardAutocorrectionController_setTextSuggestionList(self, _cmd, createAutocorrectionList());
    } else {
        orig_UIKeyboardAutocorrectionController_setTextSuggestionList(self, _cmd, textSuggestionList);
    }
}

/**
 * Updates the prediction bar with the original or custom items.
 *
 * This method usage only works on iOS 15 or above.
 *
 * @param autoCorrectionList The list that is used to update the prediciton bar with.
 */
static void (* orig_UIKeyboardAutocorrectionController_setAutocorrectionList)(UIKeyboardAutocorrectionController* self, SEL _cmd, TIAutocorrectionList* autoCorrectionList);
static void override_UIKeyboardAutocorrectionController_setAutocorrectionList(UIKeyboardAutocorrectionController* self, SEL _cmd, TIAutocorrectionList* autoCorrectionList) {
    if (pfEnabled && pfActivationMethod == kActivationMethodPredictionBar && shouldShowCustomSuggestions) {
        orig_UIKeyboardAutocorrectionController_setAutocorrectionList(self, _cmd, createAutocorrectionList());
    } else {
        orig_UIKeyboardAutocorrectionController_setAutocorrectionList(self, _cmd, autoCorrectionList);
    }
}

/**
 * Creates a list with custom prediction bar items.
 *
 * Each item has Kayoko's package id set as its bundle identifier to identify them later on.
 *
 * @return The list of custom items.
 */
static TIAutocorrectionList* createAutocorrectionList() {
    NSArray* labels = @[@"历史记录", @"复制", @"粘贴"];
    NSMutableArray* candidates = [[NSMutableArray alloc] init];
    for (NSString* label in labels) {
        TIZephyrCandidate* candidate = [[objc_getClass("TIZephyrCandidate") alloc] init];
        [candidate setLabel:label];
        [candidate setFromBundleId:@"codes.aurora.kayoko"];
        [candidates addObject:candidate];
    }

    return [objc_getClass("TIAutocorrectionList") listWithAutocorrection:nil predictions:candidates emojiList:nil];
}

#pragma mark - UIPredictionViewController class hooks

/**
 * Handles the selection of a prediction bar item.
 *
 * @see createAutocorrectionList to learn how the items are identified.
 *
 * @param predictionView The prediction bar on which the item was selected.
 * @param candidate The item that was selected.
 */
static void (* orig_UIPredictionViewController_predictionView_didSelectCandidate)(UIPredictionViewController* self, SEL _cmd, TUIPredictionView* predictionView, TIZephyrCandidate* candidate);
static void override_UIPredictionViewController_predictionView_didSelectCandidate(UIPredictionViewController* self, SEL _cmd, TUIPredictionView* predictionView, TIZephyrCandidate* candidate) {
    if (pfEnabled && pfActivationMethod == kActivationMethodPredictionBar && [candidate respondsToSelector:@selector(fromBundleId)] && [[candidate fromBundleId] isEqualToString:@"codes.aurora.kayoko"]) {
        if ([[candidate label] isEqualToString:@"历史记录"]) {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)kNotificationKeyCoreShow, nil, nil, YES);
        } else if ([[candidate label] isEqualToString:@"复制"]) {
            if (@available(iOS 15.0, *)) {
                UIKBInputDelegateManager* delegateManager = [[objc_getClass("UIKeyboardImpl") activeInstance] inputDelegateManager];
                UITextRange* range = [delegateManager selectedTextRange];
                NSString* text = [delegateManager textInRange:range];

                if (![text isEqualToString:@""]) {
                    [[UIPasteboard generalPasteboard] setString:text];
                }
            } else {
                id delegate = [[objc_getClass("UIKeyboardImpl") activeInstance] inputDelegate];
                UITextRange* range = [delegate selectedTextRange];
                NSString* text = [delegate textInRange:range];

                if (![text isEqualToString:@""]) {
                    [[UIPasteboard generalPasteboard] setString:text];
                }
            }
        } else if ([[candidate label] isEqualToString:@"粘贴"]) {
            paste();
        }
    } else {
        orig_UIPredictionViewController_predictionView_didSelectCandidate(self, _cmd, predictionView, candidate);
    }
}

/**
 * Makes the prediction bar always visible.
 *
 * @param delegate
 * @param inputViews
 *
 * @return Whether the prediction bar should be visible or not.
 */
static BOOL (*kayoko_helper_original_prediction_visibility)(UIPredictionViewController *, SEL, id, id);
static BOOL override_UIPredictionViewController_isVisibleForInputDelegate_inputViews(UIPredictionViewController* self, SEL _cmd, id delegate, id inputViews) {
    if (pfEnabled && pfActivationMethod == kActivationMethodPredictionBar) return YES;
    return kayoko_helper_original_prediction_visibility(self, _cmd, delegate, inputViews);
}

#pragma mark - UIKeyboardLayoutStar class hooks

/**
 * Updates the prediction bar with the custom items once the user entered the numeric keyboard.
 *
 * @param name The name of the keyplane that was switched to.
 */
static void (* orig_UIKeyboardLayoutStar_setKeyplaneName)(UIKeyboardLayoutStar* self, SEL _cmd, NSString* name);
static void override_UIKeyboardLayoutStar_setKeyplaneName(UIKeyboardLayoutStar* self, SEL _cmd, NSString* name) {
    orig_UIKeyboardLayoutStar_setKeyplaneName(self, _cmd, name);

    if (!pfEnabled || pfActivationMethod != kActivationMethodPredictionBar) return;
    shouldShowCustomSuggestions = [name isEqualToString:@"numbers-and-punctuation"] || [name isEqualToString:@"numbers-and-punctuation-alternate"];

    if (@available(iOS 15.0, *)) {
        [[[objc_getClass("UIKeyboardImpl") activeInstance] autocorrectionController] setAutocorrectionList:nil];
    } else {
        [[[objc_getClass("UIKeyboardImpl") activeInstance] autocorrectionController] setTextSuggestionList:nil];
    }
}

/**
 * Shows the history with the dictation button.
 *
 * This method usage only works on devices with the old keyboard.
 * The modern keyboard has a specific dictation icon on the so-called "Keyboard Dock".
 *
 * @param point
 *
 * @return The key that was pressed.
 */
static UIKBTree* (* orig_UIKeyboardLayoutStar_keyHitTest)(UIKeyboardLayoutStar* self, SEL _cmd, CGPoint point);
static UIKBTree* override_UIKeyboardLayoutStar_keyHitTest(UIKeyboardLayoutStar* self, SEL _cmd, CGPoint point) {
    UIKBTree* orig = orig_UIKeyboardLayoutStar_keyHitTest(self, _cmd, point);

    // Unset the original action and tell the core to show the history.
    if (kayoko_dictation_active() && [[orig name] isEqualToString:@"Dictation-Key"]) {
        [[orig properties] setValue:@(0) forKey:@"KBinteractionType"];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)kNotificationKeyCoreShow, nil, nil, YES);
    }

    return orig;
}

/**
 * Hides the history when they keyboard was dismissed, if the history is already visible.
 */
static void (* orig_UIKeyboardLayoutStar_didMoveToWindow)(UIKeyboardLayoutStar* self, SEL _cmd);
static void override_UIKeyboardLayoutStar_didMoveToWindow(UIKeyboardLayoutStar* self, SEL _cmd) {
    orig_UIKeyboardLayoutStar_didMoveToWindow(self, _cmd);
    if (self.window == nil) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)kNotificationKeyCoreHide, nil, nil, YES);
    }
}

#pragma mark - UIKeyboardImpl class hooks

/**
 * Notes that the app became active.
 *
 * Knowing that, we can prevent pasting from happening in apps that became inactive.
 */
static void (* orig_UIKeyboardImpl_applicationDidBecomeActive)(UIKeyboardImpl* self, SEL _cmd, BOOL didBecomeActive);
static void override_UIKeyboardImpl_applicationDidBecomeActive(UIKeyboardImpl* self, SEL _cmd, BOOL didBecomeActive) {
    orig_UIKeyboardImpl_applicationDidBecomeActive(self, _cmd, didBecomeActive);
    applicationIsInForeground = YES;
    load_preferences();
    kayoko_helper_install_activation_hooks();
}

/**
 * Notes that the app became inactive.
 *
 * @see applicationDidBecomeActive why to save the state of an app.
 */
static void (* orig_UIKeyboardImpl_applicationWillResignActive)(UIKeyboardImpl* self, SEL _cmd, BOOL willResignActive);
static void override_UIKeyboardImpl_applicationWillResignActive(UIKeyboardImpl* self, SEL _cmd, BOOL willResignActive) {
    orig_UIKeyboardImpl_applicationWillResignActive(self, _cmd, willResignActive);
    applicationIsInForeground = NO;
}

#pragma mark - Notification callbacks

/**
 * Pastes the last copied item from the history.
 */
static void paste() {
    if (!applicationIsInForeground || !pfEnabled || !pfAutomaticallyPaste) {
        return;
    }

    UIPasteboard* pasteboard = [UIPasteboard generalPasteboard];

    // Get the latest copied item if the pasteboard cleared itself.
    // The pasteboard clears itself after inactivity.
    if (![pasteboard string] && ![pasteboard image]) {
        PasteboardItem* item = [[PasteboardManager sharedInstance] getLatestHistoryItem];
        if (!item) {
            return;
        }

        if (![[item imageName] isEqualToString:@""]) {
            [pasteboard setImage:[[PasteboardManager sharedInstance] getImageForItem:item]];
        } else {
            [pasteboard setString:[item content]];
        }
    }

    [[UIApplication sharedApplication] sendAction:@selector(paste:) to:nil from:nil forEvent:nil];
}

#pragma mark - Preferences

/**
 * Loads the user's preferences.
 */
static void load_preferences(void) {
    // Obtain sandbox access before opening the preferences file.
    libSandy_applyProfile("Kayoko");
    preferences = [[NSUserDefaults alloc] initWithSuiteName:kPreferencesIdentifier];
    [preferences synchronize];

#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
    NSString *path = ROOT_PATH_NS(@"/var/mobile/Library/Preferences/codes.aurora.kayoko.preferences.plist");
#else
    NSString *path = @"/var/mobile/Library/Preferences/codes.aurora.kayoko.preferences.plist";
#endif
    NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:path];
    id enabled = snapshot ? snapshot[kPreferenceKeyEnabled] : [preferences objectForKey:kPreferenceKeyEnabled];
    id activation = snapshot ? snapshot[kPreferenceKeyActivationMethod] : [preferences objectForKey:kPreferenceKeyActivationMethod];
    id automatic = snapshot ? snapshot[kPreferenceKeyAutomaticallyPaste] : [preferences objectForKey:kPreferenceKeyAutomaticallyPaste];
    pfEnabled = [enabled respondsToSelector:@selector(boolValue)] ? [enabled boolValue] : kPreferenceKeyEnabledDefaultValue;
    pfActivationMethod = [activation respondsToSelector:@selector(unsignedIntegerValue)] ? [activation unsignedIntegerValue] : kPreferenceKeyActivationMethodDefaultValue;
    if (pfActivationMethod != kActivationMethodDictationKey) pfActivationMethod = kActivationMethodPredictionBar;
    pfAutomaticallyPaste = [automatic respondsToSelector:@selector(boolValue)] ? [automatic boolValue] : kPreferenceKeyAutomaticallyPasteDefaultValue;
}

static void kayoko_helper_preferences_changed(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        load_preferences();
        kayoko_helper_install_activation_hooks();
    });
}

static BOOL kayoko_helper_prediction_installed;
static BOOL kayoko_helper_legacy_key_installed;
static void kayoko_helper_install_activation_hooks(void) {
    if (pfEnabled && pfActivationMethod == kActivationMethodPredictionBar && !kayoko_helper_prediction_installed) {
        if (@available(iOS 15.0, *)) {
            MSHookMessageEx(objc_getClass("UIKeyboardAutocorrectionController"), @selector(setAutocorrectionList:), (IMP)&override_UIKeyboardAutocorrectionController_setAutocorrectionList, (IMP *)&orig_UIKeyboardAutocorrectionController_setAutocorrectionList);
        } else {
            MSHookMessageEx(objc_getClass("UIKeyboardAutocorrectionController"), @selector(setTextSuggestionList:), (IMP)&override_UIKeyboardAutocorrectionController_setTextSuggestionList, (IMP *)&orig_UIKeyboardAutocorrectionController_setTextSuggestionList);
        }
        MSHookMessageEx(objc_getClass("UIPredictionViewController"), @selector(isVisibleForInputDelegate:inputViews:), (IMP)&override_UIPredictionViewController_isVisibleForInputDelegate_inputViews, (IMP *)&kayoko_helper_original_prediction_visibility);
        MSHookMessageEx(objc_getClass("UIKeyboardLayoutStar"), @selector(setKeyplaneName:), (IMP)&override_UIKeyboardLayoutStar_setKeyplaneName, (IMP *)&orig_UIKeyboardLayoutStar_setKeyplaneName);
        MSHookMessageEx(objc_getClass("UIPredictionViewController"), @selector(predictionView:didSelectCandidate:), (IMP)&override_UIPredictionViewController_predictionView_didSelectCandidate, (IMP *)&orig_UIPredictionViewController_predictionView_didSelectCandidate);
        kayoko_helper_prediction_installed = YES;
    }
    if (pfEnabled && pfActivationMethod == kActivationMethodDictationKey) {
        kayoko_dictation_install_hooks();
        Class layout = objc_getClass("UIKeyboardLayoutStar");
        SEL hit = @selector(keyHitTest:);
        if (!kayoko_helper_legacy_key_installed && layout && class_getInstanceMethod(layout, hit)) {
            MSHookMessageEx(layout, hit, (IMP)&override_UIKeyboardLayoutStar_keyHitTest, (IMP *)&orig_UIKeyboardLayoutStar_keyHitTest);
            kayoko_helper_legacy_key_installed = YES;
        }
    }

}

#pragma mark - Constructor

/**
 * Initializes the helper.
 *
 * First it loads the preferences and continues if Kayoko is enabled.
 * Secondly it checks if the helper should run in the injected process.
 * Finally it sets up the hooks.
 */
__attribute((constructor)) static void initialize() {
    load_preferences();

    if (![NSProcessInfo processInfo]) {
        return;
    }

    NSString* processName = [[NSProcessInfo processInfo] processName];
    BOOL isSpringBoard = [@"SpringBoard" isEqualToString:processName];

    BOOL shouldLoad = NO;
    NSArray* args = [[objc_getClass("NSProcessInfo") processInfo] arguments];
    NSUInteger count = [args count];
    if (count != 0) {
        NSString* executablePath = args[0];
        if (executablePath) {
            NSString* processName = [executablePath lastPathComponent];
            BOOL isApplication = [executablePath rangeOfString:@"/Application/"].location != NSNotFound || [executablePath rangeOfString:@"/Applications/"].location != NSNotFound;
            BOOL isFileProvider = [[processName lowercaseString] rangeOfString:@"fileprovider"].location != NSNotFound;
            BOOL skip = [processName isEqualToString:@"AdSheet"] ||
                        [processName isEqualToString:@"CoreAuthUI"] ||
                        [processName isEqualToString:@"InCallService"] ||
                        [processName isEqualToString:@"MessagesNotificationViewService"] ||
                        [executablePath rangeOfString:@".appex/"].location != NSNotFound;
            if ((!isFileProvider && isApplication && !skip) || isSpringBoard) {
                shouldLoad = YES;
            }
        }
    }

	if (!shouldLoad) {
        return;
    }

    kayoko_helper_install_activation_hooks();

    MSHookMessageEx(objc_getClass("UIKeyboardLayoutStar"), @selector(didMoveToWindow), (IMP)&override_UIKeyboardLayoutStar_didMoveToWindow, (IMP *)&orig_UIKeyboardLayoutStar_didMoveToWindow);
    MSHookMessageEx(objc_getClass("UIKeyboardImpl"), @selector(applicationDidBecomeActive:), (IMP)&override_UIKeyboardImpl_applicationDidBecomeActive, (IMP *)&orig_UIKeyboardImpl_applicationDidBecomeActive);
    MSHookMessageEx(objc_getClass("UIKeyboardImpl"), @selector(applicationWillResignActive:), (IMP)&override_UIKeyboardImpl_applicationWillResignActive, (IMP *)&orig_UIKeyboardImpl_applicationWillResignActive);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)paste, (CFStringRef)kNotificationKeyHelperPaste, NULL, (CFNotificationSuspensionBehavior)kNilOptions);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, kayoko_helper_preferences_changed, (CFStringRef)kNotificationKeyPreferencesReload, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
