#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <errno.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>
#import "../Manager/KayokoHistoryStore.h"

static NSUInteger checks = 0;
#define CHECK(c) do { checks++; if (!(c)) { NSLog(@"FAIL %s:%d: %s", __FILE__, __LINE__, #c); exit(1); } } while (0)
#define WAIT_SEM(s) do { checks++; if (dispatch_semaphore_wait((s), dispatch_time(DISPATCH_TIME_NOW, 10LL * NSEC_PER_SEC)) != 0) { NSLog(@"FAIL timeout waiting for async history operation"); exit(1); } } while (0)

static NSString * const H = @"history";
static NSString * const F = @"favorites";
static NSString * const C = @"content";
static NSString * const B = @"bundle_identifier";
static NSString * const I = @"image_name";
static NSString * const L = @"has_link";

static NSDictionary *Record(NSString *content, NSString *image) {
    return @{ B: @"test.bundle", C: content, I: image ?: @"", L: @NO };
}
static NSString *TempDirectory(void) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSError *error = nil;
    CHECK([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]);
    return path;
}
static void WriteDefaults(NSString *path) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{H:@[], F:@[]} options:0 error:NULL];
    CHECK([data writeToFile:path atomically:YES]);
}
static BOOL WaitForContent(KayokoHistoryStore *store, NSString *key, NSString *content,
                           dispatch_semaphore_t changed) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while ([deadline timeIntervalSinceNow] > 0) {
        for (NSDictionary *item in [store snapshotForKey:key]) if ([item[C] isEqualToString:content]) return YES;
        if (dispatch_semaphore_wait(changed, dispatch_time(DISPATCH_TIME_NOW, 200LL * NSEC_PER_MSEC)) == 0) continue;
    }
    return NO;
}
static BOOL WaitForCount(KayokoHistoryStore *store, NSString *key, NSUInteger count,
                         dispatch_semaphore_t changed) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while ([deadline timeIntervalSinceNow] > 0) {
        if ([store snapshotForKey:key].count == count) return YES;
        if (dispatch_semaphore_wait(changed, dispatch_time(DISPATCH_TIME_NOW, 200LL * NSEC_PER_MSEC)) == 0) continue;
    }
    return NO;
}
static void ExplicitReload(KayokoHistoryStore *store, dispatch_semaphore_t changed) {
    [store reloadAsync];
    WAIT_SEM(changed);
}
static void TestInitialAsyncAndSnapshot(void) {
    NSString *dir = TempDirectory(), *path = [dir stringByAppendingPathComponent:@"history.json"];
    NSData *existing = [NSJSONSerialization dataWithJSONObject:@{H:@[@{B:@"b",C:@"already",I:@"",L:@NO}], F:@[]} options:0 error:NULL];
    CHECK([existing writeToFile:path atomically:YES]);
    KayokoHistoryStore *store = [[KayokoHistoryStore alloc] initWithPath:path imagesPath:[dir stringByAppendingPathComponent:@"images"]];
    dispatch_semaphore_t changed = dispatch_semaphore_create(0);
    store.didChange = ^{ dispatch_semaphore_signal(changed); };
    [store reloadAsync];
    CHECK(WaitForContent(store, H, @"already", changed));
    NSArray *snapshot = [store snapshotForKey:H];
    CHECK(snapshot.count == 1);
    CHECK(![snapshot isKindOfClass:NSMutableArray.class]);
    BOOL threw = NO;
    @try { [(NSMutableArray *)snapshot addObject:Record(@"bad", @"")]; }
    @catch (NSException *exception) { threw = YES; }
    CHECK(threw);
    CHECK([store snapshotForKey:H].count == 1);
    ExplicitReload(store, changed);
    CHECK([store snapshotForKey:H].count == 1);
}

static void TestMalformedRecoveryAndInvalidSchemas(void) {
    NSString *dir = TempDirectory(), *path = [dir stringByAppendingPathComponent:@"history.json"];
    NSData *bad = [@"{not valid json" dataUsingEncoding:NSUTF8StringEncoding];
    CHECK([bad writeToFile:path atomically:YES]);
    KayokoHistoryStore *store = [[KayokoHistoryStore alloc] initWithPath:path imagesPath:dir];
    dispatch_semaphore_t changed = dispatch_semaphore_create(0);
    store.didChange = ^{ dispatch_semaphore_signal(changed); };
    [store reloadAsync];
    WAIT_SEM(changed);
    NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:NULL];
    NSString *backup = nil;
    for (NSString *name in files) if ([name hasPrefix:@"history.json.corrupt-"]) { backup = [dir stringByAppendingPathComponent:name]; break; }
    CHECK(backup != nil);
    CHECK([[NSData dataWithContentsOfFile:backup] isEqualToData:bad]);
    NSDictionary *recovered = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:NULL];
    CHECK([recovered[H] isKindOfClass:NSArray.class] && [recovered[F] isKindOfClass:NSArray.class]);

    // Valid rows survive; invalid rows are dropped and malformed string fields get safe defaults.
    NSString *schemaPath = [dir stringByAppendingPathComponent:@"schema.json"];
    NSDictionary *schema = @{H:@[@{C:@"https://example.test", B:@17, I:[NSNull null], L:@"bad"}, @42], F:@[]};
    NSData *schemaData = [NSJSONSerialization dataWithJSONObject:schema options:0 error:NULL];
    CHECK([schemaData writeToFile:schemaPath atomically:YES]);
    KayokoHistoryStore *schemaStore = [[KayokoHistoryStore alloc] initWithPath:schemaPath imagesPath:dir];
    dispatch_semaphore_t schemaChanged = dispatch_semaphore_create(0);
    schemaStore.didChange = ^{ dispatch_semaphore_signal(schemaChanged); };
    [schemaStore reloadAsync];
    CHECK(WaitForContent(schemaStore, H, @"https://example.test", schemaChanged));
    NSDictionary *clean = [schemaStore snapshotForKey:H].firstObject;
    CHECK([clean[B] isEqualToString:@""] && [clean[I] isEqualToString:@""]);
    CHECK([clean[L] boolValue]);
    CHECK([schemaStore snapshotForKey:H].count == 1);

    // A non-dictionary root is preserved as evidence and reset to safe defaults.
    NSString *rootPath = [dir stringByAppendingPathComponent:@"root.json"];
    NSData *rootBad = [NSJSONSerialization dataWithJSONObject:@[@"wrong root"] options:0 error:NULL];
    CHECK([rootBad writeToFile:rootPath atomically:YES]);
    KayokoHistoryStore *rootStore = [[KayokoHistoryStore alloc] initWithPath:rootPath imagesPath:dir];
    dispatch_semaphore_t rootChanged = dispatch_semaphore_create(0);
    rootStore.didChange = ^{ dispatch_semaphore_signal(rootChanged); };
    [rootStore reloadAsync];
    WAIT_SEM(rootChanged);
    CHECK([rootStore snapshotForKey:H].count == 0 && [rootStore snapshotForKey:F].count == 0);
    NSArray *rootFiles = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:NULL];
    BOOL rootPreserved = NO;
    for (NSString *name in rootFiles) if ([name hasPrefix:@"root.json.corrupt-"]) rootPreserved = YES;
    CHECK(rootPreserved);
}

static void TestBatchDedupeAndBound(void) {
    NSString *dir = TempDirectory(), *path = [dir stringByAppendingPathComponent:@"history.json"];
    WriteDefaults(path);
    KayokoHistoryStore *store = [[KayokoHistoryStore alloc] initWithPath:path imagesPath:dir];
    dispatch_semaphore_t changed = dispatch_semaphore_create(0), committed = dispatch_semaphore_create(0);
    store.didChange = ^{ dispatch_semaphore_signal(changed); };
    ExplicitReload(store, changed);
    store.didCommit = ^{ dispatch_semaphore_signal(committed); };
    [store addRecords:@[Record(@"a", @""), Record(@"a", @"duplicate"), Record(@"b", @""), Record(@"c", @""), Record(@"d", @"")] toKey:H limit:3];
    WAIT_SEM(committed);
    NSArray *items = [store snapshotForKey:H];
    CHECK(items.count == 3);
    CHECK([items[0][C] isEqualToString:@"a"] && [items[0][I] isEqualToString:@""]);
    CHECK([items[1][C] isEqualToString:@"b"] && [items[2][C] isEqualToString:@"c"]);
    // No-op removal must not write or invoke didCommit.
    [store removeContent:@"absent" fromKey:H removeImage:YES];
    CHECK(dispatch_semaphore_wait(committed, dispatch_time(DISPATCH_TIME_NOW, 150LL * NSEC_PER_MSEC)) != 0);
}

static void TestConcurrentStores(void) {
    NSString *dir = TempDirectory(), *path = [dir stringByAppendingPathComponent:@"history.json"];
    WriteDefaults(path);
    KayokoHistoryStore *a = [[KayokoHistoryStore alloc] initWithPath:path imagesPath:dir];
    KayokoHistoryStore *b = [[KayokoHistoryStore alloc] initWithPath:path imagesPath:dir];
    dispatch_semaphore_t changedA = dispatch_semaphore_create(0), changedB = dispatch_semaphore_create(0);
    a.didChange = ^{ dispatch_semaphore_signal(changedA); };
    b.didChange = ^{ dispatch_semaphore_signal(changedB); };
    ExplicitReload(a, changedA);
    ExplicitReload(b, changedB);
    dispatch_semaphore_t committed = dispatch_semaphore_create(0);
    a.didCommit = ^{ dispatch_semaphore_signal(committed); };
    b.didCommit = ^{ dispatch_semaphore_signal(committed); };
    dispatch_group_t group = dispatch_group_create();
    for (NSUInteger worker = 0; worker < 2; worker++) {
        KayokoHistoryStore *store = worker == 0 ? a : b;
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            for (NSUInteger n = 0; n < 10; n++) {
                NSString *content = [NSString stringWithFormat:@"worker-%lu-item-%lu", (unsigned long)worker, (unsigned long)n];
                [store addRecords:@[Record(content, @"")] toKey:H limit:100];
            }
        });
    }
    CHECK(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10LL * NSEC_PER_SEC)) == 0);
    for (NSUInteger n = 0; n < 20; n++) WAIT_SEM(committed);
    [a reloadAsync];
    CHECK(WaitForCount(a, H, 20, changedA));
    [b reloadAsync];
    CHECK(WaitForCount(b, H, 20, changedB));
}

static void TestImageReferencePruning(void) {
    NSString *dir = TempDirectory(), *path = [dir stringByAppendingPathComponent:@"history.json"];
    NSString *images = [dir stringByAppendingPathComponent:@"images"];
    CHECK([NSFileManager.defaultManager createDirectoryAtPath:images withIntermediateDirectories:YES attributes:nil error:NULL]);
    WriteDefaults(path);
    NSString *imagePath = [images stringByAppendingPathComponent:@"shared.png"];
    CHECK([[NSData dataWithBytes:"png" length:3] writeToFile:imagePath atomically:YES]);
    KayokoHistoryStore *store = [[KayokoHistoryStore alloc] initWithPath:path imagesPath:images];
    dispatch_semaphore_t changed = dispatch_semaphore_create(0), committed = dispatch_semaphore_create(0);
    store.didChange = ^{ dispatch_semaphore_signal(changed); };
    ExplicitReload(store, changed);
    store.didCommit = ^{ dispatch_semaphore_signal(committed); };
    [store addRecords:@[Record(@"history image", @"shared.png")] toKey:H limit:20]; WAIT_SEM(committed);
    [store addRecords:@[Record(@"favorite image", @"shared.png")] toKey:F limit:20]; WAIT_SEM(committed);
    [store removeContent:@"history image" fromKey:H removeImage:YES]; WAIT_SEM(committed);
    CHECK([NSFileManager.defaultManager fileExistsAtPath:imagePath]);
    [store removeContent:@"favorite image" fromKey:F removeImage:YES]; WAIT_SEM(committed);
    CHECK(![NSFileManager.defaultManager fileExistsAtPath:imagePath]);

    // Traversal-like names are not allowed to reach outside imagesPath.
    NSString *outside = [dir stringByAppendingPathComponent:@"keep.txt"];
    CHECK([[NSData dataWithBytes:"keep" length:4] writeToFile:outside atomically:YES]);
    [store addRecords:@[Record(@"traversal", @"../keep.txt")] toKey:H limit:20]; WAIT_SEM(committed);
    [store removeContent:@"traversal" fromKey:H removeImage:YES]; WAIT_SEM(committed);
    CHECK([NSFileManager.defaultManager fileExistsAtPath:outside]);
}

int main(void) {
    @autoreleasepool {
        TestInitialAsyncAndSnapshot();
        TestMalformedRecoveryAndInvalidSchemas();
        TestBatchDedupeAndBound();
        TestConcurrentStores();
        TestImageReferencePruning();
        NSLog(@"PASS: %lu history-store checks", (unsigned long)checks);
    }
    return 0;
}
