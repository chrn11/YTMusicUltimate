#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YTMUCacheManager : NSObject

+ (instancetype)shared;
+ (NSString *)cachesPath;

/// 同步计算 Caches 总字节数
- (unsigned long long)cacheSizeBytes;

/// 格式化后的大小字符串
- (NSString *)formattedCacheSize;

/// 后台计算大小，主线程回调
- (void)calculateCacheSizeAsync:(void (^)(unsigned long long bytes, NSString *formatted))completion;

/// 清空整个 Caches 目录
- (void)clearAllCacheWithCompletion:(void (^ _Nullable)(void))completion;

/// 若开启自动清理且超限，则按访问时间渐进删到上限的 80%
- (void)autoTrimIfNeededWithCompletion:(void (^ _Nullable)(BOOL didTrim, unsigned long long newSize))completion;

@end

NS_ASSUME_NONNULL_END
