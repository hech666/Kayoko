#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <UIKit/UIKit.h>
#import "../Manager/PasteboardManager.h"
#import "../Manager/PasteboardItem.h"
#import "../Utils/ImageUtil.h"

static NSUInteger checks;
#define CHECK(x) do { checks++; if (!(x)) { NSLog(@"FAIL line %d: %s", __LINE__, #x); exit(1); } } while (0)
static dispatch_semaphore_t entered, releaseRead;
static BOOL blockRead;
static NSUInteger creations, stringReads, stringWrites;
static NSString *storedText;
static BOOL Pump(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && until.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    return condition();
}
@implementation UIApplication
+ (instancetype)sharedApplication { static id app; static dispatch_once_t once; dispatch_once(&once, ^{ app = [self new]; }); return app; }
@end
@implementation UIImage
- (CGImageRef)CGImage { return NULL; }
+ (instancetype)imageWithContentsOfFile:(NSString *)path { return nil; }
@end
NSData *UIImagePNGRepresentation(UIImage *image) { return nil; }
NSData *UIImageJPEGRepresentation(UIImage *image, CGFloat q) { return nil; }
@implementation ImageUtil
+ (BOOL)imageHasAlpha:(UIImage *)image { return NO; }
+ (UIImage *)getRotatedImageFromImage:(UIImage *)image { return image; }
+ (UIImage *)getImageWithImage:(UIImage *)image scaledToSize:(CGSize)size { return image; }
@end
@implementation UIPasteboard
+ (instancetype)generalPasteboard {
    CHECK(!NSThread.isMainThread);
    static UIPasteboard *board; static dispatch_once_t once;
    dispatch_once(&once, ^{ board = [self new]; creations++; });
    return board;
}
- (BOOL)hasStrings { CHECK(!NSThread.isMainThread); return storedText.length > 0; }
- (BOOL)hasImages { CHECK(!NSThread.isMainThread); return NO; }
- (NSArray *)strings {
    CHECK(!NSThread.isMainThread); stringReads++;
    if (blockRead) { dispatch_semaphore_signal(entered); CHECK(dispatch_semaphore_wait(releaseRead, dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC)) == 0); }
    return storedText ? @[storedText] : @[];
}
- (void)setString:(NSString *)s { CHECK(!NSThread.isMainThread); CHECK(s.length > 0); storedText = [s copy]; stringWrites++; self.changeCount++; }
- (NSString *)string { CHECK(!NSThread.isMainThread); return storedText; }
@end

int main(void) { @autoreleasepool {
    entered = dispatch_semaphore_create(0); releaseRead = dispatch_semaphore_create(0);
    PasteboardManager *manager = PasteboardManager.sharedInstance;
    CHECK(creations == 0); // singleton init has no pasteboard IPC
    manager.maximumHistoryAmount = 200; manager.saveText = YES; manager.saveImages = YES;
    manager.automaticallyPaste = NO;
    storedText = @"external-copy"; blockRead = YES;
    [manager pullPasteboardChanges];
    CHECK(Pump(^BOOL { return dispatch_semaphore_wait(entered, DISPATCH_TIME_NOW) == 0; }, 3));
    CFAbsoluteTime before = CFAbsoluteTimeGetCurrent();
    for (NSUInteger i=0; i<500; i++) [manager pullPasteboardChanges];
    NSArray *snapshot = [manager getItemsFromHistoryWithKey:kHistoryKeyHistory];
    CHECK(snapshot != nil && CFAbsoluteTimeGetCurrent()-before < 0.2);
    __block BOOL uiTick = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ uiTick = YES; });
    CHECK(Pump(^BOOL { return uiTick; }, 0.5)); // main still runs while strings blocks
    CHECK(stringReads == 1);
    blockRead = NO; dispatch_semaphore_signal(releaseRead);
    CHECK(Pump(^BOOL { return [manager getItemsFromHistoryWithKey:kHistoryKeyHistory].count == 1; }, 3));

    PasteboardItem *favorite = [[PasteboardItem alloc] initWithBundleIdentifier:@"tests" andContent:@"keep-favorite" withImageNamed:nil];
    [manager addPasteboardItem:favorite toHistoryWithKey:kHistoryKeyFavorites];
    CHECK(Pump(^BOOL { return [manager getItemsFromHistoryWithKey:kHistoryKeyFavorites].count == 1; }, 3));
    NSUInteger priorWrites = stringWrites;
    [manager updatePasteboardWithItem:favorite fromHistoryWithKey:kHistoryKeyFavorites shouldAutoPaste:NO];
    CHECK(Pump(^BOOL { return stringWrites > priorWrites; }, 3));
    CHECK(stringWrites == priorWrites+1 && [storedText isEqualToString:@"keep-favorite"]);
    CHECK([manager getItemsFromHistoryWithKey:kHistoryKeyFavorites].count == 1);
    PasteboardItem *missing = [[PasteboardItem alloc] initWithBundleIdentifier:@"tests" andContent:@"missing.png" withImageNamed:@"missing.png"];
    [manager updatePasteboardWithItem:missing fromHistoryWithKey:kHistoryKeyHistory shouldAutoPaste:NO];
    __block BOOL ready = NO, completed = NO;
    [manager prepareForPasteWithCompletion:^(BOOL ok) { CHECK(NSThread.isMainThread); ready=ok; completed=YES; }];
    CHECK(Pump(^BOOL { return completed; }, 3));
    CHECK(ready && stringWrites == priorWrites+1); // missing image leaves clipboard intact
    CHECK([manager getLatestHistoryItem] != nil);
    NSLog(@"PASS: %lu checks; real manager with blocked clipboard, responsive main, single write, favorite and missing-image safety", (unsigned long)checks);
} return 0; }
