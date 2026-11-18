#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdbool.h>
#include <string.h>

// Included after PreferenceKeys.h and the Helper's configuration globals.
static void (*kayoko_dictation_original_legacy)(id, SEL, id, id);
static void (*kayoko_dictation_original_modern)(id, SEL, id, id, bool);
static bool (*kayoko_dictation_original_visibility)(id, SEL);
static BOOL kayoko_dictation_legacy_installed;
static BOOL kayoko_dictation_modern_installed;
static BOOL kayoko_dictation_visibility_installed;

static BOOL kayoko_dictation_active(void) {
    return pfEnabled && pfActivationMethod == kActivationMethodDictationKey;
}

static void kayoko_dictation_request_history(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kNotificationKeyCoreShow, NULL, NULL, YES);
}

static void kayoko_dictation_legacy_pressed(id receiver, SEL selector, id item, id event) {
    if (kayoko_dictation_active()) {
        kayoko_dictation_request_history();
    } else if (kayoko_dictation_original_legacy) {
        kayoko_dictation_original_legacy(receiver, selector, item, event);
    }
}

static void kayoko_dictation_modern_pressed(id receiver, SEL selector, id item, id event, bool isRunningButton) {
    // Never swallow the stop button of an already running dictation session.
    if (kayoko_dictation_active() && !isRunningButton) {
        kayoko_dictation_request_history();
    } else if (kayoko_dictation_original_modern) {
        kayoko_dictation_original_modern(receiver, selector, item, event, isRunningButton);
    }
}

static bool kayoko_dictation_should_show(id receiver, SEL selector) {
    if (kayoko_dictation_active()) return true;
    return kayoko_dictation_original_visibility ? kayoko_dictation_original_visibility(receiver, selector) : false;
}

static char kayoko_dictation_type_code(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return *type;
}

static BOOL kayoko_dictation_method_matches(Class cls, SEL selector, BOOL modern) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != (modern ? 5 : 4)) return NO;
    char type[128] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (kayoko_dictation_type_code(type) != 'v') return NO;
    for (unsigned int index = 2; index < 4; index++) {
        method_getArgumentType(method, index, type, sizeof(type));
        if (kayoko_dictation_type_code(type) != '@') return NO;
    }
    if (modern) {
        method_getArgumentType(method, 4, type, sizeof(type));
        char flag = kayoko_dictation_type_code(type);
        if (flag != 'B' && flag != 'c') return NO;
    }
    return YES;
}

static void kayoko_dictation_install_hooks(void) {
    Class dock = objc_getClass("UISystemKeyboardDockController");
    SEL legacy = NSSelectorFromString(@"dictationItemButtonWasPressed:withEvent:");
    SEL modern = NSSelectorFromString(@"dictationItemButtonWasPressed:withEvent:isRunningButton:");
    if (!kayoko_dictation_legacy_installed && kayoko_dictation_method_matches(dock, legacy, NO)) {
        MSHookMessageEx(dock, legacy, (IMP)kayoko_dictation_legacy_pressed, (IMP *)&kayoko_dictation_original_legacy);
        kayoko_dictation_legacy_installed = YES;
    }
    if (!kayoko_dictation_modern_installed && kayoko_dictation_method_matches(dock, modern, YES)) {
        MSHookMessageEx(dock, modern, (IMP)kayoko_dictation_modern_pressed, (IMP *)&kayoko_dictation_original_modern);
        kayoko_dictation_modern_installed = YES;
    }
    Class impl = objc_getClass("UIKeyboardImpl");
    SEL visibility = NSSelectorFromString(@"shouldShowDictationKey");
    Method method = impl ? class_getInstanceMethod(impl, visibility) : NULL;
    if (!kayoko_dictation_visibility_installed && method && method_getNumberOfArguments(method) == 2) {
        char type[128] = {0};
        method_getReturnType(method, type, sizeof(type));
        char code = kayoko_dictation_type_code(type);
        if (code == 'B' || code == 'c') {
            MSHookMessageEx(impl, visibility, (IMP)kayoko_dictation_should_show, (IMP *)&kayoko_dictation_original_visibility);
            kayoko_dictation_visibility_installed = YES;
        }
    }
}
