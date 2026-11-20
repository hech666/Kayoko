#import <Foundation/Foundation.h>
#import "../Manager/KayokoClipboardExecutor.h"
#include <stdio.h>
#include <stdlib.h>

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); \
        exit(EXIT_FAILURE); \
    } \
} while (0)

static dispatch_time_t AfterMilliseconds(int64_t milliseconds) {
    return dispatch_time(DISPATCH_TIME_NOW, milliseconds * NSEC_PER_MSEC);
}

static void TestBlockedRead(void) {
    KayokoClipboardExecutor *executor = [KayokoClipboardExecutor new];
    dispatch_semaphore_t readStarted = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseRead = dispatch_semaphore_create(0);
    dispatch_semaphore_t readFinished = dispatch_semaphore_create(0);
    dispatch_semaphore_t writeStarted = dispatch_semaphore_create(0);
    dispatch_semaphore_t allSubmitted = dispatch_semaphore_create(0);
    dispatch_semaphore_t batchFinished = dispatch_semaphore_create(0);
    dispatch_semaphore_t recovered = dispatch_semaphore_create(0);

    // Use a separate producer so a regression that blocks submit fails a finite wait.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [executor submitRead:^{
            CHECK(![NSThread isMainThread]);
            dispatch_semaphore_signal(readStarted);
            CHECK(dispatch_semaphore_wait(releaseRead, AfterMilliseconds(15000)) == 0);
            dispatch_semaphore_signal(readFinished);
        }];
        CHECK(dispatch_semaphore_wait(readStarted, AfterMilliseconds(5000)) == 0);
        CHECK(executor.pendingCount == 0);

        for (NSUInteger i = 0; i < 2048; i++) {
            [executor submitRead:^{ CHECK(NO && "superseded read ran"); }];
        }
        CHECK(executor.pendingCount == 1);
        [executor submitWrite:^{ CHECK(NO && "superseded write ran"); }];
        [executor submitRead:^{
            CHECK(![NSThread isMainThread]);
            CHECK(dispatch_semaphore_wait(writeStarted, DISPATCH_TIME_NOW) == 0);
            dispatch_semaphore_signal(batchFinished);
        }];
        // Submitted after the latest read, but the executor must run this first.
        [executor submitWrite:^{
            CHECK(![NSThread isMainThread]);
            CHECK(dispatch_semaphore_wait(readFinished, DISPATCH_TIME_NOW) == 0);
            dispatch_semaphore_signal(writeStarted);
            @throw [NSException exceptionWithName:@"ClipboardExecutorTestException"
                                           reason:@"Intentional test exception" userInfo:nil];
        }];
        dispatch_semaphore_signal(allSubmitted);
    });

    CHECK(dispatch_semaphore_wait(allSubmitted, AfterMilliseconds(5000)) == 0);
    CHECK(executor.pendingCount == 2);
    // Cross the production watchdog threshold without releasing the read. A
    // diagnostic must not run pending work concurrently or cancel the read.
    CHECK(dispatch_semaphore_wait(batchFinished, AfterMilliseconds(3500)) != 0);
    CHECK(executor.pendingCount == 2);
    dispatch_semaphore_signal(releaseRead);
    CHECK(dispatch_semaphore_wait(batchFinished, AfterMilliseconds(5000)) == 0);
    CHECK(executor.pendingCount == 0);

    [executor submitWrite:^{
        CHECK(![NSThread isMainThread]);
        dispatch_semaphore_signal(recovered);
    }];
    CHECK(dispatch_semaphore_wait(recovered, AfterMilliseconds(5000)) == 0);
    CHECK(executor.pendingCount == 0);
}

int main(void) {
    @autoreleasepool {
        CHECK([NSThread isMainThread]);
        TestBlockedRead();
        puts("ClipboardExecutorTests passed");
    }
    return EXIT_SUCCESS;
}
