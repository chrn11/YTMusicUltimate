#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Utils/YTMUCacheManager.h"

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[YTMUCacheManager shared] autoTrimIfNeededWithCompletion:nil];
    });
}
