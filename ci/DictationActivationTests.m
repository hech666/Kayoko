#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#include <stdbool.h>

static BOOL pfEnabled;
static NSUInteger pfActivationMethod;
static NSUInteger const kActivationMethodDictationKey = 1;
static NSString *const kNotificationKeyCoreShow = @"codes.aurora.kayoko.core.show";
static NSUInteger requests, legacyCalls, modernCalls, installs, checks;
static id lastItem, lastEvent;
static bool lastRunning;
#define CHECK(x) do { checks++; if (!(x)) { NSLog(@"FAIL line %d: %s", __LINE__, #x); exit(1); } } while (0)
static void kayoko_test_post(CFNotificationCenterRef center, CFStringRef name, const void *object, CFDictionaryRef userInfo, Boolean immediate) {
    CHECK([(__bridge NSString *)name isEqualToString:kNotificationKeyCoreShow]);
    requests++;
}
static void MSHookMessageEx(Class cls, SEL selector, IMP hook, IMP *original) {
    Method method = class_getInstanceMethod(cls, selector);
    CHECK(method != NULL);
    *original = method_setImplementation(method, hook);
    installs++;
}
#define CFNotificationCenterPostNotification kayoko_test_post
#import "../Tweak/Helper/KayokoDictationActivation.h"
#undef CFNotificationCenterPostNotification

@interface UISystemKeyboardDockController : NSObject
- (void)dictationItemButtonWasPressed:(id)item withEvent:(id)event;
- (void)dictationItemButtonWasPressed:(id)item withEvent:(id)event isRunningButton:(bool)running;
@end
@implementation UISystemKeyboardDockController
- (void)dictationItemButtonWasPressed:(id)item withEvent:(id)event {
    legacyCalls++; lastItem=item; lastEvent=event;
}
- (void)dictationItemButtonWasPressed:(id)item withEvent:(id)event isRunningButton:(bool)running {
    modernCalls++; lastItem=item; lastEvent=event; lastRunning=running;
}
@end
@interface UIKeyboardImpl : NSObject
- (bool)shouldShowDictationKey;
@end
@implementation UIKeyboardImpl
- (bool)shouldShowDictationKey { return false; }
@end
@interface KayokoInvalidDock : NSObject
- (NSInteger)wrongResult:(id)item withEvent:(id)event;
- (void)wrongFlag:(id)item withEvent:(id)event flag:(double)flag;
- (void)wrongObject:(NSInteger)item withEvent:(id)event;
@end
@implementation KayokoInvalidDock
- (NSInteger)wrongResult:(id)item withEvent:(id)event { return 0; }
- (void)wrongFlag:(id)item withEvent:(id)event flag:(double)flag {}
- (void)wrongObject:(NSInteger)item withEvent:(id)event {}
@end
int main(void) {
 @autoreleasepool {
    CHECK(!kayoko_dictation_method_matches(Nil, @selector(description), NO));
    CHECK(!kayoko_dictation_method_matches(KayokoInvalidDock.class, @selector(wrongResult:withEvent:), NO));
    CHECK(!kayoko_dictation_method_matches(KayokoInvalidDock.class, @selector(wrongFlag:withEvent:flag:), YES));
    CHECK(!kayoko_dictation_method_matches(KayokoInvalidDock.class, @selector(wrongObject:withEvent:), NO));
    kayoko_dictation_install_hooks(); CHECK(installs==3);
    kayoko_dictation_install_hooks(); CHECK(installs==3);
    id item=[NSObject new], event=[NSObject new];
    UISystemKeyboardDockController *dock=[UISystemKeyboardDockController new];
    UIKeyboardImpl *keyboard=[UIKeyboardImpl new];
    pfEnabled=YES; pfActivationMethod=1;
    CHECK([keyboard shouldShowDictationKey]);
    [dock dictationItemButtonWasPressed:item withEvent:event isRunningButton:false];
    CHECK(requests==1 && modernCalls==0);
    [dock dictationItemButtonWasPressed:item withEvent:event];
    CHECK(requests==2 && legacyCalls==0);
    [dock dictationItemButtonWasPressed:item withEvent:event isRunningButton:true];
    CHECK(requests==2 && modernCalls==1 && lastRunning && lastItem==item && lastEvent==event);
    pfEnabled=NO;
    CHECK(![keyboard shouldShowDictationKey]);
    [dock dictationItemButtonWasPressed:item withEvent:event isRunningButton:false];
    CHECK(requests==2 && modernCalls==2 && !lastRunning && lastItem==item && lastEvent==event);
    [dock dictationItemButtonWasPressed:item withEvent:event];
    CHECK(requests==2 && legacyCalls==1 && lastItem==item && lastEvent==event);
    pfEnabled=YES; pfActivationMethod=0;
    CHECK(![keyboard shouldShowDictationKey]);
    [dock dictationItemButtonWasPressed:item withEvent:event isRunningButton:false];
    [dock dictationItemButtonWasPressed:item withEvent:event];
    CHECK(requests==2 && modernCalls==3 && legacyCalls==2);
    pfActivationMethod=1;
    [dock dictationItemButtonWasPressed:item withEvent:event isRunningButton:false];
    CHECK(requests==3 && modernCalls==3);
    NSLog(@"PASS: %lu checks, modern/legacy ABI, running-stop forwarding, mode switches, idempotent hooks", (unsigned long)checks);
 }
 return 0;
}
