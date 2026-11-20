// Kayoko: asynchronous pasteboard access. Never wait for pasteboard IPC on main.
#import "PasteboardManager.h"
#import "PasteboardItem.h"
#import "KayokoClipboardExecutor.h"
#import "KayokoHistoryStore.h"
#import "../Utils/ImageUtil.h"
#import "../Preferences/NotificationKeys.h"
#import "../Preferences/PreferenceKeys.h"
#import <dispatch/dispatch.h>
#import <math.h>

@interface PasteboardManager () {
    KayokoClipboardExecutor *_clipboardExecutor;
    KayokoHistoryStore *_historyStore;
    BOOL _captureScheduled;
    BOOL _receivedInitialChange;
}
- (NSDictionary *)recordForItem:(PasteboardItem *)item;
- (void)captureWithBundle:(NSString *)bundle saveText:(BOOL)text saveImages:(BOOL)images limit:(NSUInteger)limit;
@end

@implementation PasteboardManager
+ (instancetype)sharedInstance {
    static PasteboardManager *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] initPrivate]; });
    return instance;
}
- (instancetype)init { return [PasteboardManager sharedInstance]; }
- (instancetype)initPrivate {
    if ((self = [super init])) {
        // UIPasteboard creation AND changeCount can perform IPC. Both are lazy
        // on the executor, not in dispatch_once during SpringBoard startup.
        _lastChangeCount = 0;
        _maximumHistoryAmount = kPreferenceKeyMaximumHistoryAmountDefaultValue;
        _saveText = kPreferenceKeySaveTextDefaultValue;
        _saveImages = kPreferenceKeySaveImagesDefaultValue;
        _clipboardExecutor = [KayokoClipboardExecutor new];
        _historyStore = [[KayokoHistoryStore alloc] initWithPath:kHistoryPath imagesPath:kHistoryImagesPath];
        __weak typeof(self) weakSelf = self;
        _historyStore.didChange = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (weakSelf) [[NSNotificationCenter defaultCenter] postNotificationName:KayokoHistoryDidChangeNotification object:weakSelf];
            });
        };
        _historyStore.didCommit = ^{
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                (CFStringRef)kNotificationKeyCoreReload, NULL, NULL, YES);
        };
        [_historyStore reloadAsync];
    }
    return self;
}

- (void)reloadHistoryAsync { [_historyStore reloadAsync]; }

- (NSDictionary *)recordForItem:(PasteboardItem *)item {
    if (![item.content isKindOfClass:NSString.class] || item.content.length == 0) return nil;
    return @{ kItemKeyBundleIdentifier: [item.bundleIdentifier copy] ?: @"com.apple.springboard",
              kItemKeyContent: [item.content copy],
              kItemKeyImageName: [item.imageName copy] ?: @"",
              kItemKeyHasLink: @(item.hasLink) };
}

- (void)pullPasteboardChanges {
    // Coalesce even before requesting main-thread foreground-app metadata.
    @synchronized (self) {
        if (_captureScheduled) return;
        _captureScheduled = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @synchronized (self) { self->_captureScheduled = NO; }
        NSString *bundle = @"com.apple.springboard";
        // UIKit/foreground-application queries stay on main; content does not.
        UIApplication *app = UIApplication.sharedApplication;
        if ([app respondsToSelector:@selector(_accessibilityFrontMostApplication)]) {
            NSString *front = [[app _accessibilityFrontMostApplication] bundleIdentifier];
            if (front.length) bundle = [front copy];
        }
        BOOL text = self.saveText, images = self.saveImages;
        NSUInteger limit = MIN(self.maximumHistoryAmount, (NSUInteger)10000);
        if (!text && !images) return;
        [self->_clipboardExecutor submitRead:^{
            [self captureWithBundle:bundle saveText:text saveImages:images limit:limit];
        }];
    });
}

- (void)captureWithBundle:(NSString *)bundle saveText:(BOOL)text saveImages:(BOOL)images limit:(NSUInteger)limit {
    NSAssert(!NSThread.isMainThread, @"Clipboard reads must not run on main");
    @autoreleasepool {
        if (!_pasteboard) _pasteboard = [UIPasteboard generalPasteboard];
        NSInteger generation = _pasteboard.changeCount;
        if (_receivedInitialChange && generation == (NSInteger)_lastChangeCount) return;
        // Fetch each representation only once. Prefer images over accompanying
        // text, matching the original behavior, without reading images for text.
        BOOL hasImages = _pasteboard.hasImages;
        NSArray *strings = text && !hasImages ? [_pasteboard.strings copy] : nil;
        NSArray *pictures = images && hasImages ? [_pasteboard.images copy] : nil;
        if (_pasteboard.changeCount != generation) {
            [self pullPasteboardChanges]; // clipboard changed while reading: retry latest only
            return;
        }
        NSMutableArray *records = [NSMutableArray array];
        NSMutableArray *newFiles = [NSMutableArray array];
        for (id value in strings) {
            if (records.count >= 64) break;
            if (![value isKindOfClass:NSString.class] || [value length] == 0 || [value length] > 2 * 1024 * 1024) continue;
            PasteboardItem *item = [[PasteboardItem alloc] initWithBundleIdentifier:bundle andContent:value withImageNamed:nil];
            NSDictionary *record = [self recordForItem:item];
            if (record) [records addObject:record];
        }
        for (id value in pictures) {
            if (records.count >= 64) break;
            @autoreleasepool {
                if (![value isKindOfClass:UIImage.class]) continue;
                UIImage *image = value;
                // Do not inflate huge images in SpringBoard. Limit encoding work
                // and skip unsupported CI-only payloads rather than risking OOM.
                CGImageRef cg = image.CGImage;
                if (!cg || (double)CGImageGetWidth(cg) * CGImageGetHeight(cg) > 24000000.0) {
                    NSLog(@"[KayokoClipboard] skipped oversized/unsupported image");
                    continue;
                }
                BOOL alpha = [ImageUtil imageHasAlpha:image];
                NSData *data = alpha ? UIImagePNGRepresentation([ImageUtil getRotatedImageFromImage:image]) : UIImageJPEGRepresentation(image, 0.9);
                if (data.length == 0 || data.length > 32 * 1024 * 1024) continue;
                NSString *name = [NSUUID.UUID.UUIDString stringByAppendingString:alpha ? @".png" : @".jpg"];
                NSString *path = [kHistoryImagesPath stringByAppendingPathComponent:name];
                [[NSFileManager defaultManager] createDirectoryAtPath:kHistoryImagesPath withIntermediateDirectories:YES attributes:nil error:NULL];
                if (![data writeToFile:path options:NSDataWritingAtomic error:NULL]) continue;
                [newFiles addObject:path];
                PasteboardItem *item = [[PasteboardItem alloc] initWithBundleIdentifier:bundle andContent:name withImageNamed:name];
                [records addObject:[self recordForItem:item]];
            }
        }
        // Avoid committing a stale snapshot after a long image encoding step.
        if (_pasteboard.changeCount != generation) {
            for (NSString *path in newFiles) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            [self pullPasteboardChanges];
            return;
        }
        _lastChangeCount = generation;
        _receivedInitialChange = YES;
        if (records.count) [_historyStore addRecords:records toKey:kHistoryKeyHistory limit:limit];
    }
}

- (void)addPasteboardItem:(PasteboardItem *)item toHistoryWithKey:(NSString *)key {
    NSDictionary *record = [self recordForItem:item];
    if (record) [_historyStore addRecords:@[record] toKey:[key copy] limit:MIN(self.maximumHistoryAmount, (NSUInteger)10000)];
}

- (void)removePasteboardItem:(PasteboardItem *)item fromHistoryWithKey:(NSString *)key shouldRemoveImage:(BOOL)removeImage {
    if (item.content.length) [_historyStore removeContent:[item.content copy] fromKey:[key copy] removeImage:removeImage];
}

- (BOOL)writeRecordToPasteboard:(NSDictionary *)record {
    NSAssert(!NSThread.isMainThread, @"Clipboard writes must not run on main");
    if (!_pasteboard) _pasteboard = UIPasteboard.generalPasteboard;
    NSString *imageName = record[kItemKeyImageName];
    if (imageName.length) {
        if (![imageName.lastPathComponent isEqualToString:imageName]) return NO;
        UIImage *image = [UIImage imageWithContentsOfFile:[kHistoryImagesPath stringByAppendingPathComponent:imageName]];
        if (!image) return NO; // leave clipboard/history untouched if image missing
        [_pasteboard setImage:image];
    } else {
        NSString *text = record[kItemKeyContent];
        if (!text.length) return NO;
        [_pasteboard setString:text];
    }
    // Do not read a fresh changeCount and label it as our write: an external
    // copy can race this setter. Capture/dedup handles our notification safely.
    return YES;
}

- (void)updatePasteboardWithItem:(PasteboardItem *)item fromHistoryWithKey:(NSString *)key shouldAutoPaste:(BOOL)autoPaste {
    NSDictionary *record = [self recordForItem:item];
    if (!record) return;
    BOOL requestPaste = self.automaticallyPaste && autoPaste;
    NSUInteger limit = MIN(self.maximumHistoryAmount, (NSUInteger)10000);
    NSString *historyKey = [key copy];
    CFAbsoluteTime requestedAt = CFAbsoluteTimeGetCurrent();
    [_clipboardExecutor submitWrite:^{
        if (CFAbsoluteTimeGetCurrent() - requestedAt > 2.0) {
            NSLog(@"[KayokoClipboard] dropped stale queued clipboard write");
            return;
        }
        if (![self writeRecordToPasteboard:record]) return;
        // Keep source history/favorites and image. Deduplication of the resulting
        // capture is storage-only and cannot cause another clipboard write.
        if ([historyKey isEqualToString:kHistoryKeyHistory])
            [self->_historyStore addRecords:@[record] toKey:kHistoryKeyHistory limit:limit];
        if (requestPaste && self.automaticallyPaste && CFAbsoluteTimeGetCurrent() - requestedAt <= 2.0) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            (CFStringRef)kNotificationKeyHelperPaste, NULL, NULL, YES);
    }];
}

- (void)prepareForPasteWithCompletion:(void (^)(BOOL))completion {
    // Helper's manual/automatic paste used to call string/image synchronously on
    // the App main thread. This shares the same bounded background executor.
    CFAbsoluteTime requestedAt = CFAbsoluteTimeGetCurrent();
    [_clipboardExecutor submitWrite:^{
        BOOL ready = NO;
        @try {
            if (CFAbsoluteTimeGetCurrent() - requestedAt > 2.0) return;
            if (!self->_pasteboard) self->_pasteboard = UIPasteboard.generalPasteboard;
            ready = self->_pasteboard.hasStrings || self->_pasteboard.hasImages;
            if (!ready) {
                NSDictionary *record = [[self->_historyStore snapshotForKey:kHistoryKeyHistory] firstObject];
                ready = record && [self writeRecordToPasteboard:record];
            }
        } @catch (NSException *exception) {
            NSLog(@"[KayokoClipboard] paste preparation failed (%@)", exception.name);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(ready); });
    }];
}

- (NSMutableArray *)getItemsFromHistoryWithKey:(NSString *)key {
    // No file reads, JSON decoding, or synchronous queue waits in UI callbacks.
    return [[_historyStore snapshotForKey:key] mutableCopy];
}

- (PasteboardItem *)getLatestHistoryItem {
    NSDictionary *record = [[_historyStore snapshotForKey:kHistoryKeyHistory] firstObject];
    return record ? [PasteboardItem itemFromDictionary:record] : nil;
}

- (UIImage *)getImageForItem:(PasteboardItem *)item {
    NSString *name = item.imageName;
    if (!name.length || ![name.lastPathComponent isEqualToString:name]) return nil;
    return [UIImage imageWithContentsOfFile:[kHistoryImagesPath stringByAppendingPathComponent:name]];
}
@end
