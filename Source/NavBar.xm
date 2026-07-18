#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

@interface YTMNavigationBarView : UIView
@end

@interface QTMButton : UIButton
@property (nonatomic, copy, readwrite) NSString *accessibilityIdentifier;
@end

@interface YTMSortFilterButton : UIButton
@end

@interface UIView (YTMUNavPrivate)
- (UIViewController *)_viewControllerForAncestor;
@end

static BOOL YTMUInNavigationBar(UIView *view) {
    UIView *v = view;
    while (v) {
        if ([v isKindOfClass:NSClassFromString(@"YTMNavigationBarView")] ||
            [v isKindOfClass:[UINavigationBar class]]) {
            return YES;
        }
        v = v.superview;
    }
    return NO;
}

%hook QTMButton
- (void)layoutSubviews {
    %orig;
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideHistoryButton")) {
        if ([self.accessibilityIdentifier isEqualToString:@"id.navigation.history.button"]) {
            self.hidden = YES;
        }
    }
    // 导航栏投屏：仅在导航栏上下文隐藏，与播放页/迷你条的 hidePlayerCastButton 分离
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideCastButton") && YTMUInNavigationBar(self)) {
        if ([self.accessibilityIdentifier isEqualToString:@"id.mdx.playbackroute.button"] ||
            [self.accessibilityIdentifier containsString:@"mdx"] ||
            [self.accessibilityIdentifier containsString:@"playbackroute"]) {
            self.hidden = YES;
            self.alpha = 0;
            self.userInteractionEnabled = NO;
        }
    }
}
%end

%hook YTMNavigationBarView
- (void)layoutSubviews {
    %orig;

    NSArray *subviews = [self subviews];

    UIView *sortFilterButton = nil;
    for (UIView *subview in subviews) {
        if ([subview isKindOfClass:NSClassFromString(@"YTMSortFilterButton")]) {
            sortFilterButton = subview;
            break;
        }
    }

    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideFilterButton")) {
        if (sortFilterButton != nil) {
            [sortFilterButton removeFromSuperview];
        }
    }
}
%end
