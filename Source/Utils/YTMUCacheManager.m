#import "YTMUCacheManager.h"

@implementation YTMUCacheManager

+ (instancetype)shared {
    static YTMUCacheManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[YTMUCacheManager alloc] init];
    });
    return manager;
}

+ (NSString *)cachesPath {
    return NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
}

- (NSDictionary *)prefs {
    return [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"] ?: @{};
}

- (unsigned long long)cacheLimitBytes {
    NSInteger mb = [[self prefs][@"cacheLimitMB"] integerValue];
    if (mb <= 0) mb = 2048;
    return (unsigned long long)mb * 1024ULL * 1024ULL;
}

- (BOOL)autoCleanEnabled {
    return [[self prefs][@"autoCleanCache"] boolValue];
}

- (unsigned long long)cacheSizeBytes {
    NSString *cachePath = [YTMUCacheManager cachesPath];
    if (!cachePath.length) return 0;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:cachePath];
    unsigned long long folderSize = 0;
    NSString *fileName;
    while ((fileName = [enumerator nextObject])) {
        NSString *filePath = [cachePath stringByAppendingPathComponent:fileName];
        NSDictionary *attrs = [fm attributesOfItemAtPath:filePath error:nil];
        if ([attrs.fileType isEqualToString:NSFileTypeRegular]) {
            folderSize += attrs.fileSize;
        }
    }
    return folderSize;
}

- (NSString *)formattedCacheSize {
    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    return [formatter stringFromByteCount:(long long)[self cacheSizeBytes]];
}

- (void)calculateCacheSizeAsync:(void (^)(unsigned long long, NSString *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        unsigned long long bytes = [self cacheSizeBytes];
        NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
        formatter.countStyle = NSByteCountFormatterCountStyleFile;
        NSString *formatted = [formatter stringFromByteCount:(long long)bytes];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(bytes, formatted);
        });
    });
}

- (void)clearAllCacheWithCompletion:(void (^)(void))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *cachePath = [YTMUCacheManager cachesPath];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *contents = [fm contentsOfDirectoryAtPath:cachePath error:nil];
        for (NSString *item in contents) {
            [fm removeItemAtPath:[cachePath stringByAppendingPathComponent:item] error:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion();
        });
    });
}

- (NSDate *)accessDateForURL:(NSURL *)url {
    NSDate *date = nil;
    [url getResourceValue:&date forKey:NSURLContentAccessDateKey error:nil];
    if (!date) {
        [url getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
    }
    return date ?: [NSDate distantPast];
}

- (void)autoTrimIfNeededWithCompletion:(void (^)(BOOL, unsigned long long))completion {
    if (![self autoCleanEnabled]) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, [self cacheSizeBytes]);
            });
        }
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        unsigned long long limit = [self cacheLimitBytes];
        unsigned long long size = [self cacheSizeBytes];
        if (size < limit) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, size);
            });
            return;
        }

        unsigned long long target = (unsigned long long)(limit * 0.8);
        NSString *cachePath = [YTMUCacheManager cachesPath];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *cacheURL = [NSURL fileURLWithPath:cachePath isDirectory:YES];

        NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:cacheURL
                                     includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey, NSURLContentAccessDateKey, NSURLContentModificationDateKey]
                                                        options:NSDirectoryEnumerationSkipsHiddenFiles
                                                   errorHandler:nil];

        NSMutableArray<NSDictionary *> *files = [NSMutableArray array];
        for (NSURL *fileURL in enumerator) {
            NSNumber *isFile = nil;
            [fileURL getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil];
            if (![isFile boolValue]) continue;

            NSNumber *fileSize = nil;
            [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
            [files addObject:@{
                @"url": fileURL,
                @"size": fileSize ?: @0,
                @"date": [self accessDateForURL:fileURL]
            }];
        }

        [files sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"date"] compare:b[@"date"]];
        }];

        for (NSDictionary *entry in files) {
            if (size <= target) break;
            NSURL *url = entry[@"url"];
            unsigned long long fileSize = [entry[@"size"] unsignedLongLongValue];
            if ([fm removeItemAtURL:url error:nil]) {
                if (size >= fileSize) size -= fileSize;
                else size = 0;
            }
        }

        unsigned long long finalSize = [self cacheSizeBytes];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(YES, finalSize);
        });
    });
}

@end
