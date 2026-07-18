#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

static BOOL YTMEnabled(void) {
    return YTMU(@"YTMUltimateIsEnabled");
}

static BOOL YTMUViewIsInClassNamed(UIView *view, NSString *className) {
    Class cls = NSClassFromString(className);
    if (!cls) return NO;
    UIView *v = view;
    while (v) {
        if ([v isKindOfClass:cls]) return YES;
        v = v.superview;
    }
    return NO;
}

static BOOL YTMUIsNavBarContext(UIView *view) {
    return YTMUViewIsInClassNamed(view, @"YTMNavigationBarView") ||
           YTMUViewIsInClassNamed(view, @"YTNavigationBar") ||
           YTMUViewIsInClassNamed(view, @"UINavigationBar");
}

// 真机实测（zh-Hans）：投屏按钮 accessibilityLabel = 「投放」
// 注意：不能用 contains「投屏」——设置项标题「隐藏播放页投屏按钮」会被误藏
static BOOL YTMUIsCastLabel(NSString *label) {
    if (!label.length) return NO;
    NSString *l = [label stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([l isEqualToString:@"投放"] || [l isEqualToString:@"投屏"] || [l isEqualToString:@"Cast"]) return YES;
    // 英文系统常见完整文案；避免匹配设置页长句
    NSString *lower = l.lowercaseString;
    if (l.length <= 24 && ([lower isEqualToString:@"cast"] || [lower hasPrefix:@"cast "] || [lower hasSuffix:@" cast"])) return YES;
    return NO;
}

static BOOL YTMUIsInSettingsUI(UIView *view) {
    UIView *v = view;
    while (v) {
        if ([v isKindOfClass:[UITableViewCell class]] || [v isKindOfClass:[UITableView class]]) return YES;
        NSString *cls = NSStringFromClass([v class]);
        if ([cls containsString:@"SettingsController"] || [cls containsString:@"YTMUltimate"]) return YES;
        v = v.superview;
    }
    UIViewController *vc = nil;
    if ([view respondsToSelector:@selector(_viewControllerForAncestor)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        vc = [view performSelector:@selector(_viewControllerForAncestor)];
#pragma clang diagnostic pop
    }
    if (vc) {
        NSString *cls = NSStringFromClass([vc class]);
        if ([cls containsString:@"Settings"] || [cls containsString:@"YTMUltimate"]) return YES;
    }
    return NO;
}

// 真机实测：音视频切换 = 「正在播放歌曲」/「正在播放视频」
static BOOL YTMUIsAVSwitchLabel(NSString *label) {
    if (!label.length) return NO;
    if ([label containsString:@"正在播放歌曲"] || [label containsString:@"正在播放视频"]) return YES;
    NSString *lower = label.lowercaseString;
    if ([lower containsString:@"playing song"] || [lower containsString:@"playing video"]) return YES;
    if ([lower containsString:@"audio"] && [lower containsString:@"video"]) return YES;
    return NO;
}

static BOOL YTMUIsCastButton(UIView *view) {
    if (YTMUIsCastLabel(view.accessibilityLabel)) return YES;
    NSString *aid = view.accessibilityIdentifier ?: @"";
    if ([aid isEqualToString:@"id.mdx.playbackroute.button"] ||
        [aid containsString:@"mdx"] ||
        [aid containsString:@"playbackroute"]) {
        return YES;
    }
    return NO;
}

static BOOL YTMUIsAVSwitchControl(UIView *view) {
    if (YTMUIsAVSwitchLabel(view.accessibilityLabel)) return YES;
    NSString *aid = view.accessibilityIdentifier ?: @"";
    if ([aid containsString:@"audio"] && [aid containsString:@"video"]) return YES;
    if ([aid containsString:@"av_switch"] || [aid containsString:@"audio_video"]) return YES;
    NSString *cls = NSStringFromClass([view class]);
    if ([cls containsString:@"AudioVideo"] || [cls containsString:@"AVSwitch"] || [cls containsString:@"ModeSwitch"]) return YES;
    return NO;
}

static void YTMUHideView(UIView *view) {
    if (!view) return;
    view.hidden = YES;
    view.alpha = 0;
    view.userInteractionEnabled = NO;
}

// 自定义 UIView 常重写 layoutSubviews 且不调 super，故除按钮 hook 外再按 accessibility 隐藏
static void YTMUHideAVSwitchTree(UIView *view) {
    YTMUHideView(view);
    UIView *p = view.superview;
    for (int i = 0; i < 5 && p; i++) {
        CGSize sz = p.bounds.size;
        NSString *cls = NSStringFromClass([p class]);
        // 勿匹配 PlayerHeader：会把收起/更多整栏藏掉
        BOOL nameHit = [cls containsString:@"AudioVideo"] ||
                       [cls containsString:@"AVSwitch"] ||
                       [cls containsString:@"ModeSwitch"];
        // 顶部紧凑分段控件容器（真机约 96x36）
        BOOL sizeHit = sz.height > 0 && sz.height <= 56 && sz.width > 40 && sz.width <= 220;
        if (nameHit || sizeHit) {
            YTMUHideView(p);
            if (nameHit) break;
        }
        p = p.superview;
    }
}

static void YTMUApplyPlayerUIHides(UIView *view) {
    if (!view || !YTMEnabled()) return;
    if (YTMUIsInSettingsUI(view)) return;

    if (YTMU(@"hideCastButton") && YTMUIsCastButton(view) && YTMUIsNavBarContext(view)) {
        YTMUHideView(view);
        return;
    }

    if (YTMU(@"hidePlayerCastButton") && YTMUIsCastButton(view) && !YTMUIsNavBarContext(view)) {
        YTMUHideView(view);
        return;
    }

    if (YTMU(@"hideAVSwitchButton") && YTMUIsAVSwitchControl(view)) {
        YTMUHideAVSwitchTree(view);
    }
}

@interface QTMButton : UIButton
@end

%hook QTMButton
- (void)layoutSubviews {
    %orig;
    YTMUApplyPlayerUIHides((UIView *)self);
}
%end

%hook UIButton
- (void)layoutSubviews {
    %orig;
    YTMUApplyPlayerUIHides(self);
}
%end

%hook UIControl
- (void)layoutSubviews {
    %orig;
    YTMUApplyPlayerUIHides(self);
}
%end

%hook UIView
- (void)setAccessibilityLabel:(NSString *)label {
    %orig;
    if (!YTMEnabled() || YTMUIsInSettingsUI(self)) return;

    if (YTMU(@"hideAVSwitchButton") && YTMUIsAVSwitchLabel(label)) {
        YTMUHideAVSwitchTree(self);
        return;
    }

    if (YTMUIsCastLabel(label)) {
        if (YTMU(@"hideCastButton") && YTMUIsNavBarContext(self)) {
            YTMUHideView(self);
            return;
        }
        if (YTMU(@"hidePlayerCastButton") && !YTMUIsNavBarContext(self)) {
            YTMUHideView(self);
        }
    }
}

- (void)didMoveToWindow {
    %orig;
    // 部分控件先入窗再设 label；入窗后再扫一次
    YTMUApplyPlayerUIHides(self);
}
%end

%hook YTMMusicAppMetadata
- (BOOL)isAudioOnlyButtonVisible {
    if (YTMEnabled() && YTMU(@"hideAVSwitchButton")) return NO;
    return %orig;
}
%end

%hook YTMMusicAppMetadataImpl
- (BOOL)isAudioOnlyButtonVisible {
    if (YTMEnabled() && YTMU(@"hideAVSwitchButton")) return NO;
    return %orig;
}
%end
