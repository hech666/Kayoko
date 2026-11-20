//
//  PasteboardManager.h
//  Kayoko
//
//  Created by Alexandra Aurora Göttlicher
//

#import <UIKit/UIKit.h>
#import <rootless.h>

@class PasteboardItem;

#define kHistoryPath ROOT_PATH_NS(@"/var/mobile/Library/codes.aurora.kayoko/history.json")
#define kHistoryImagesPath ROOT_PATH_NS(@"/var/mobile/Library/codes.aurora.kayoko/images/")
static NSString* const kHistoryKeyHistory = @"history";
static NSString* const kHistoryKeyFavorites = @"favorites";
static NSString* const KayokoHistoryDidChangeNotification = @"KayokoHistoryDidChangeNotification";

@interface PasteboardManager : NSObject {
    // Accessed exclusively by the clipboard executor, never the UI thread.
    UIPasteboard* _pasteboard;
    NSUInteger _lastChangeCount;
}
@property(atomic, assign)NSUInteger maximumHistoryAmount;
@property(atomic, assign)BOOL saveText;
@property(atomic, assign)BOOL saveImages;
@property(atomic, assign)BOOL automaticallyPaste;
+ (instancetype)sharedInstance;
- (void)pullPasteboardChanges;
- (void)reloadHistoryAsync;
- (void)prepareForPasteWithCompletion:(void (^)(BOOL ready))completion;
- (void)addPasteboardItem:(PasteboardItem *)item toHistoryWithKey:(NSString *)historyKey;
- (void)updatePasteboardWithItem:(PasteboardItem *)item fromHistoryWithKey:(NSString *)historyKey shouldAutoPaste:(BOOL)shouldAutoPaste;
- (void)removePasteboardItem:(PasteboardItem *)item fromHistoryWithKey:(NSString *)historyKey shouldRemoveImage:(BOOL)shouldRemoveImage;
- (NSMutableArray *)getItemsFromHistoryWithKey:(NSString *)historyKey;
- (PasteboardItem *)getLatestHistoryItem;
- (UIImage *)getImageForItem:(PasteboardItem *)item;
@end

@interface SBApplication : NSObject
@property(nonatomic, readonly)NSString* bundleIdentifier;
@end

@interface UIApplication (Private)
- (SBApplication *)_accessibilityFrontMostApplication;
@end
