#import "KayokoClipboardExecutor.h"
#include <stdint.h>
#include <time.h>

static const uint64_t KayokoDefaultStallNanos = 3ull * NSEC_PER_SEC;

static void KayokoArmStallTimer(dispatch_source_t timer, uint64_t delayNanos) {
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)delayNanos),
                              DISPATCH_TIME_FOREVER, 0);
}

@implementation KayokoClipboardExecutor {
    NSLock *_lock;
    dispatch_queue_t _workQueue;
    dispatch_source_t _watchdog;

    // Protected by _lock. Only one scheduled/running drain owns the slots.
    dispatch_block_t _pendingRead;
    dispatch_block_t _pendingWrite;
    BOOL _draining;
    NSString *_activeKind;
    uint64_t _generation;
    uint64_t _reportedGeneration;
    uint64_t _startedAt;
    uint64_t _stallNanos;
}

- (instancetype)init {
    return [self initWithStallInterval:3.0];
}

- (instancetype)initWithStallInterval:(NSTimeInterval)stallInterval {
    self = [super init];
    if (self) {
        _lock = [NSLock new];
        _stallNanos = (uint64_t)((stallInterval > 0.0 ? stallInterval : 3.0) * (double)NSEC_PER_SEC);
        _workQueue = dispatch_queue_create("codes.aurora.kayoko.clipboard.work", DISPATCH_QUEUE_SERIAL);
        // One reusable timer, independent of the queue that can block in IPC.
        _watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                           dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        __weak KayokoClipboardExecutor *weakSelf = self;
        dispatch_source_set_event_handler(_watchdog, ^{
            [weakSelf checkForStall];
        });
        dispatch_source_set_timer(_watchdog, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
        dispatch_resume(_watchdog);
    }
    return self;
}

- (void)dealloc {
    if (_watchdog != nil) {
        dispatch_source_cancel(_watchdog);
    }
}

- (void)submitRead:(dispatch_block_t)block {
    [self submit:block isWrite:NO];
}

- (void)submitWrite:(dispatch_block_t)block {
    [self submit:block isWrite:YES];
}

- (void)submit:(dispatch_block_t)block isWrite:(BOOL)isWrite {
    dispatch_block_t work = [block copy];
    // Releasing captures can invoke arbitrary dealloc code. Keep that outside the lock.
    __attribute__((objc_precise_lifetime)) dispatch_block_t displaced;
    [_lock lock];
    if (isWrite) {
        displaced = _pendingWrite;
        _pendingWrite = work;
    } else {
        displaced = _pendingRead;
        _pendingRead = work;
    }
    BOOL needsDrain = !_draining;
    _draining = YES;
    [_lock unlock];
    (void)displaced; // precise lifetime releases captured state only after unlocking

    if (needsDrain) {
        dispatch_async(_workQueue, ^{
            [self drain];
        });
    }
}

- (NSUInteger)pendingCount {
    [_lock lock];
    NSUInteger count = (_pendingRead != nil) + (_pendingWrite != nil);
    [_lock unlock];
    return count;
}

- (void)drain {
    for (;;) {
        @autoreleasepool {
            [_lock lock];
            BOOL isWrite = _pendingWrite != nil;
            __attribute__((objc_precise_lifetime)) dispatch_block_t work = isWrite ? _pendingWrite : _pendingRead;
            if (work == nil) {
                _draining = NO;
                [_lock unlock];
                return;
            }
            if (isWrite) {
                _pendingWrite = nil;
            } else {
                _pendingRead = nil;
            }
            NSString *kind = isWrite ? @"write" : @"read";
            uint64_t generation = ++_generation;
            _activeKind = kind;
            _startedAt = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            KayokoArmStallTimer(_watchdog, _stallNanos);
            [_lock unlock];

            BOOL threw = NO;
            @try {
                work();
            } @catch (id exception) {
                threw = YES;
            }

            [_lock lock];
            _activeKind = nil;
            dispatch_source_set_timer(_watchdog, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
            [_lock unlock];

            if (threw) {
                NSLog(@"Kayoko clipboard %@ #%llu raised an Objective-C exception; continuing with pending work.",
                      kind, (unsigned long long)generation);
            }
        }
    }
}

- (void)checkForStall {
    NSString *kind = nil;
    uint64_t generation = 0;
    [_lock lock];
    if (_activeKind != nil && _reportedGeneration != _generation) {
        // A delayed delivery from a previous operation must not report a new one
        // until that generation has crossed its own stall threshold.
        uint64_t elapsed = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - _startedAt;
        if (elapsed >= _stallNanos) {
            generation = _generation;
            _reportedGeneration = generation;
            kind = _activeKind;
        } else {
            KayokoArmStallTimer(_watchdog, _stallNanos - elapsed);
        }
    }
    [_lock unlock];

    if (kind != nil) {
        NSLog(@"Kayoko clipboard %@ #%llu was still running after 3 seconds (diagnostic only; no cancellation attempted).",
              kind, (unsigned long long)generation);
    }
}

@end
