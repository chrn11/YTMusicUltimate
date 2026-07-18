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
static BOOL YTMUIsCastLabel(NSString *label) {
    if (!label.length) return NO;
    NSString *l = label;
    if ([l isEqualToString:@"投放"] || [l isEqualToString:@"Cast"] || [l isEqualToString:@"投屏"]) return YES;
    NSString *lower = l.lowercaseString;
    if ([lower containsString:@"cast"] || [lower containsString:@"投放"] || [lower containsString:@"投屏"]) return YES;
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
        BOOL nameHit = [cls containsString:@"AudioVideo"] ||
                       [cls containsString:@"AVSwitch"] ||
                       [cls containsString:@"ModeSwitch"] ||
                       [cls containsString:@"PlayerHeader"];
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
    if (!YTMEnabled()) return;

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
