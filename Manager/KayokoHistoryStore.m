#import "KayokoHistoryStore.h"
#import <fcntl.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <unistd.h>
#include <errno.h>

static NSString * const KayokoHistoryKey = @"history";
static NSString * const KayokoFavoritesKey = @"favorites";
static NSString * const KayokoBundleKey = @"bundle_identifier";
static NSString * const KayokoContentKey = @"content";
static NSString * const KayokoImageKey = @"image_name";
static NSString * const KayokoHasLinkKey = @"has_link";
static NSString * const KayokoHistoryStoreErrorDomain = @"KayokoHistoryStore";

@interface KayokoHistoryStore () {
    NSString *_path;
    NSString *_imagesPath;
    dispatch_queue_t _queue;
    NSLock *_cacheLock;
    NSArray<NSDictionary *> *_historyCache;
    NSArray<NSDictionary *> *_favoritesCache;
    dispatch_block_t _didChange;
    dispatch_block_t _didCommit;
}
- (NSDictionary *)readDocumentLockedNeedsWrite:(BOOL *)needsWrite corrupt:(BOOL *)corrupt error:(NSError **)error;
- (BOOL)writeDocumentLocked:(NSDictionary *)document preservingCorrupt:(BOOL)corrupt error:(NSError **)error;
@end

@implementation KayokoHistoryStore

- (instancetype)initWithPath:(NSString *)path imagesPath:(NSString *)imagesPath {
    self = [super init];
    if (self) {
        _path = [path copy];
        _imagesPath = [imagesPath copy];
        _queue = dispatch_queue_create("codes.aurora.kayoko.history-store", DISPATCH_QUEUE_SERIAL);
        _cacheLock = [[NSLock alloc] init];
        _historyCache = @[];
        _favoritesCache = @[];
        [self reloadAsync];
    }
    return self;
}

- (void)setDidChange:(dispatch_block_t)block {
    @synchronized (self) { _didChange = [block copy]; }
}
- (dispatch_block_t)didChange {
    @synchronized (self) { return [_didChange copy]; }
}
- (void)setDidCommit:(dispatch_block_t)block {
    @synchronized (self) { _didCommit = [block copy]; }
}
- (dispatch_block_t)didCommit {
    @synchronized (self) { return [_didCommit copy]; }
}

- (NSArray<NSDictionary *> *)snapshotForKey:(NSString *)key {
    [_cacheLock lock];
    NSArray *source = [key isEqualToString:KayokoHistoryKey] ? _historyCache :
                      ([key isEqualToString:KayokoFavoritesKey] ? _favoritesCache : @[]);
    NSArray *snapshot = [[NSArray alloc] initWithArray:source copyItems:YES];
    [_cacheLock unlock];
    return snapshot;
}

- (void)reloadAsync {
    dispatch_async(_queue, ^{
        NSError *error = nil;
        BOOL needsWrite = NO, corrupt = NO, committed = NO;
        int fd = [self acquireFileLock];
        if (fd < 0) return;
        NSDictionary *document = [self readDocumentLockedNeedsWrite:&needsWrite corrupt:&corrupt error:&error];
        if (document && needsWrite) {
            committed = [self writeDocumentLocked:document preservingCorrupt:corrupt error:&error];
            if (!committed) document = nil;
        }
        [self releaseFileLock:fd];
        if (!document) return;
        [self publishDocument:document];
        [self notifyChange];
        if (committed) [self notifyCommit];
    });
}

- (void)addRecords:(NSArray<NSDictionary *> *)records toKey:(NSString *)key limit:(NSUInteger)limit {
    if (![key isEqualToString:KayokoHistoryKey] && ![key isEqualToString:KayokoFavoritesKey]) return;
    NSMutableArray<NSDictionary *> *incoming = [NSMutableArray array];
    NSMutableSet<NSString *> *incomingContents = [NSMutableSet set];
    for (id candidate in records) {
        if (![candidate isKindOfClass:NSDictionary.class]) continue;
        id rawContent = candidate[KayokoContentKey];
        if (![rawContent isKindOfClass:NSString.class]) continue;
        NSDictionary *record = [self normalizedRecord:candidate];
        NSString *content = record[KayokoContentKey];
        if ([incomingContents containsObject:content]) continue;
        [incomingContents addObject:content];
        [incoming addObject:record];
    }
    if (incoming.count == 0) return;

    dispatch_async(_queue, ^{
        NSError *error = nil;
        BOOL needsWrite = NO, corrupt = NO;
        int fd = [self acquireFileLock];
        if (fd < 0) return;
        NSMutableDictionary *document = [[self readDocumentLockedNeedsWrite:&needsWrite corrupt:&corrupt error:&error] mutableCopy];
        if (!document) { [self releaseFileLock:fd]; return; }
        NSArray<NSDictionary *> *old = document[key];
        NSMutableArray<NSDictionary *> *combined = [NSMutableArray arrayWithArray:incoming];
        for (NSDictionary *record in old) {
            if (![incomingContents containsObject:record[KayokoContentKey]]) [combined addObject:record];
        }
        if (combined.count > limit) [combined removeObjectsInRange:NSMakeRange(limit, combined.count - limit)];
        if ([combined isEqualToArray:old]) { [self releaseFileLock:fd]; return; }
        document[key] = [combined copy];
        BOOL written = [self writeDocumentLocked:document preservingCorrupt:corrupt error:&error];
        [self releaseFileLock:fd];
        if (!written) return;
        [self publishDocument:document];
        [self notifyChange];
        [self notifyCommit];
    });
}

- (void)removeContent:(NSString *)content fromKey:(NSString *)key removeImage:(BOOL)removeImage {
    if (![content isKindOfClass:NSString.class] ||
        (![key isEqualToString:KayokoHistoryKey] && ![key isEqualToString:KayokoFavoritesKey])) return;
    NSString *wanted = [content copy];
    dispatch_async(_queue, ^{
        NSError *error = nil;
        BOOL needsWrite = NO, corrupt = NO;
        int fd = [self acquireFileLock];
        if (fd < 0) return;
        NSMutableDictionary *document = [[self readDocumentLockedNeedsWrite:&needsWrite corrupt:&corrupt error:&error] mutableCopy];
        if (!document) { [self releaseFileLock:fd]; return; }
        NSArray<NSDictionary *> *old = document[key];
        NSMutableArray<NSDictionary *> *remaining = [NSMutableArray array];
        NSMutableSet<NSString *> *candidateImages = [NSMutableSet set];
        for (NSDictionary *record in old) {
            if ([record[KayokoContentKey] isEqualToString:wanted]) {
                NSString *image = record[KayokoImageKey];
                if (removeImage && image.length) [candidateImages addObject:image];
            } else {
                [remaining addObject:record];
            }
        }
        if (remaining.count == old.count) { [self releaseFileLock:fd]; return; }
        document[key] = [remaining copy];
        BOOL written = [self writeDocumentLocked:document preservingCorrupt:corrupt error:&error];
        if (written && removeImage) {
            NSArray *allRecords = [document[KayokoHistoryKey] arrayByAddingObjectsFromArray:document[KayokoFavoritesKey]];
            NSMutableSet<NSString *> *referenced = [NSMutableSet set];
            for (NSDictionary *record in allRecords) {
                NSString *image = record[KayokoImageKey];
                if (image.length) [referenced addObject:image];
            }
            for (NSString *image in candidateImages) {
                if (![referenced containsObject:image]) [self deleteImageNamedLocked:image];
            }
        }
        [self releaseFileLock:fd];
        if (!written) return;
        [self publishDocument:document];
        [self notifyChange];
        [self notifyCommit];
    });
}

#pragma mark - Disk and cache internals

- (int)acquireFileLock {
    NSString *directory = [_path stringByDeletingLastPathComponent];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES attributes:nil error:&error]) return -1;
    NSString *lockPath = [_path stringByAppendingString:@".lock"];
    int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
    if (fd < 0) return -1;
    while (flock(fd, LOCK_EX) != 0) {
        if (errno == EINTR) continue;
        close(fd);
        return -1;
    }
    return fd;
}

- (void)releaseFileLock:(int)fd {
    flock(fd, LOCK_UN);
    close(fd);
}

- (NSDictionary *)readDocumentLockedNeedsWrite:(BOOL *)needsWrite corrupt:(BOOL *)corrupt error:(NSError **)error {
    if (needsWrite) *needsWrite = NO;
    if (corrupt) *corrupt = NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:_path]) {
        if (needsWrite) *needsWrite = YES;
        return [self defaultDocument];
    }
    NSData *data = [NSData dataWithContentsOfFile:_path options:0 error:error];
    if (!data) return nil;
    NSError *parseError = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
    BOOL badSchema = ![parsed isKindOfClass:NSDictionary.class];
    if (!badSchema) {
        id history = parsed[KayokoHistoryKey], favorites = parsed[KayokoFavoritesKey];
        badSchema = (history && ![history isKindOfClass:NSArray.class]) ||
                    (favorites && ![favorites isKindOfClass:NSArray.class]);
    }
    if (parseError || badSchema) {
        if (needsWrite) *needsWrite = YES;
        if (corrupt) *corrupt = YES;
        return [self defaultDocument];
    }

    NSMutableDictionary *document = [parsed mutableCopy];
    BOOL repaired = NO;
    for (NSString *key in @[KayokoHistoryKey, KayokoFavoritesKey]) {
        id source = document[key] ?: @[];
        NSMutableArray *clean = [NSMutableArray array];
        for (id item in source) {
            if (![item isKindOfClass:NSDictionary.class]) { repaired = YES; continue; }
            NSDictionary *record = [self normalizedRecord:item];
            if (![record isEqualToDictionary:item]) repaired = YES;
            [clean addObject:record];
        }
        if (!document[key] || ![clean isEqualToArray:source]) repaired = YES;
        document[key] = [clean copy];
    }
    if (needsWrite) *needsWrite = repaired;
    return document;
}

- (NSDictionary *)defaultDocument {
    return @{ KayokoHistoryKey: @[], KayokoFavoritesKey: @[] };
}

- (NSDictionary *)normalizedRecord:(NSDictionary *)source {
    id rawBundle = source[KayokoBundleKey];
    id rawContent = source[KayokoContentKey];
    id rawImage = source[KayokoImageKey];
    id rawLink = source[KayokoHasLinkKey];
    NSString *bundle = [rawBundle isKindOfClass:NSString.class] ? [rawBundle copy] : @"";
    NSString *content = [rawContent isKindOfClass:NSString.class] ? [rawContent copy] : @"";
    NSString *image = [rawImage isKindOfClass:NSString.class] ? [rawImage copy] : @"";
    BOOL hasLink = [rawLink isKindOfClass:NSNumber.class] ? [rawLink boolValue] :
                   ([content hasPrefix:@"http://"] || [content hasPrefix:@"https://"]);
    return @{ KayokoBundleKey: bundle, KayokoContentKey: content,
              KayokoImageKey: image, KayokoHasLinkKey: @(hasLink) };
}

- (BOOL)writeDocumentLocked:(NSDictionary *)document preservingCorrupt:(BOOL)corrupt error:(NSError **)error {
    NSError *localError = nil;
    if (![NSJSONSerialization isValidJSONObject:document]) {
        if (error) *error = [NSError errorWithDomain:KayokoHistoryStoreErrorDomain code:1 userInfo:nil];
        return NO;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:document options:0 error:&localError];
    if (!data) { if (error) *error = localError; return NO; }
    NSString *directory = [_path stringByDeletingLastPathComponent];
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES attributes:nil error:&localError]) {
        if (error) *error = localError;
        return NO;
    }
    if (corrupt) {
        NSString *backup = nil;
        do {
            backup = [_path stringByAppendingFormat:@".corrupt-%@", NSUUID.UUID.UUIDString];
        } while ([NSFileManager.defaultManager fileExistsAtPath:backup]);
        if (![NSFileManager.defaultManager moveItemAtPath:_path toPath:backup error:&localError]) {
            if (error) *error = localError;
            return NO;
        }
    }
    if (![data writeToFile:_path options:NSDataWritingAtomic error:&localError]) {
        if (error) *error = localError;
        return NO;
    }
    return YES;
}

- (void)publishDocument:(NSDictionary *)document {
    NSArray *history = [document[KayokoHistoryKey] copy] ?: @[];
    NSArray *favorites = [document[KayokoFavoritesKey] copy] ?: @[];
    [_cacheLock lock];
    _historyCache = history;
    _favoritesCache = favorites;
    [_cacheLock unlock];
}

- (void)notifyChange {
    dispatch_block_t callback = self.didChange;
    if (callback) callback();
}

- (void)notifyCommit {
    dispatch_block_t callback = self.didCommit;
    if (callback) callback();
}

- (void)deleteImageNamedLocked:(NSString *)name {
    if (![name isKindOfClass:NSString.class] || name.length == 0 ||
        ![name.lastPathComponent isEqualToString:name] ||
        [name isEqualToString:@"."] || [name isEqualToString:@".."] ||
        [name containsString:@"/"]) return;
    NSString *path = [_imagesPath stringByAppendingPathComponent:name];
    struct stat info;
    if (lstat(path.fileSystemRepresentation, &info) != 0) return;
    if (!S_ISREG(info.st_mode) && !S_ISLNK(info.st_mode)) return;
    unlink(path.fileSystemRepresentation); // unlink a symlink itself; never follows it.
}

@end
