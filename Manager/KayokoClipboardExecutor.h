#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

NS_ASSUME_NONNULL_BEGIN

@interface KayokoClipboardExecutor : NSObject

- (instancetype)init;

// Test/configuration initializer. The default interval is three seconds.
- (instancetype)initWithStallInterval:(NSTimeInterval)stallInterval;

// Submission never waits for running work. A new block replaces any pending
// block of the same kind; the executor takes pending writes before reads.
- (void)submitRead:(dispatch_block_t)block;
- (void)submitWrite:(dispatch_block_t)block;

// Snapshot of the pending slots, excluding work already taken by the worker.
@property (nonatomic, readonly) NSUInteger pendingCount;

@end

NS_ASSUME_NONNULL_END
