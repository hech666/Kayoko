#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Foundation-only, asynchronous JSON history store.
 *
 * didChange runs on the private background queue after a successful write or
 * every completed reload. didCommit runs on that queue only after a successful
 * disk mutation and after the interprocess file lock has been released. Keep
 * didCommit separate from reload-triggered didChange: a CoreReload receiver
 * should call reloadAsync, which must not repost CoreReload.
 */
@interface KayokoHistoryStore : NSObject

@property (nonatomic, copy, nullable) dispatch_block_t didChange;
@property (nonatomic, copy, nullable) dispatch_block_t didCommit;

- (instancetype)initWithPath:(NSString *)path imagesPath:(NSString *)imagesPath;

/// Returns immutable copies from the in-memory cache; never performs I/O or waits.
- (NSArray<NSDictionary *> *)snapshotForKey:(NSString *)key;

/// Reloads from disk asynchronously and publishes didChange on completion.
- (void)reloadAsync;

/// Adds a newest-first batch, deduplicates by content, then truncates once.
- (void)addRecords:(NSArray<NSDictionary *> *)records
             toKey:(NSString *)key
             limit:(NSUInteger)limit;

/// Removes all matching content from one collection and optionally prunes unused images.
- (void)removeContent:(NSString *)content
              fromKey:(NSString *)key
           removeImage:(BOOL)removeImage;

@end

NS_ASSUME_NONNULL_END
