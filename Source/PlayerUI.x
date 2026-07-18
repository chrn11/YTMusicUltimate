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

@interface UIView (YTMUPrivate)
- (UIViewController *)_viewControllerForAncestor;
@end

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

static BOOL YTMUIsPlayerOrMiniContext(UIView *view) {
    if (YTMUIsNavBarContext(view)) return NO;

    UIViewController *vc = nil;
    if ([view respondsToSelector:@selector(_viewControllerForAncestor)]) {
        vc = [view _viewControllerForAncestor];
    }
    NSString *vcName = NSStringFromClass([vc class]) ?: @"";
    if ([vcName containsString:@"NowPlaying"] ||
        [vcName containsString:@"Watch"] ||
        [vcName containsString:@"Miniplayer"] ||
        [vcName containsString:@"PlayerBar"] ||
        [vcName containsString:@"Playback"] ||
        [vcName containsString:@"Tab"] ||
        [vcName containsString:@"Browse"] ||
        [vcName containsString:@"Pivot"]) {
        // Tab/Browse 也要允许迷你条
    }

    if (YTMUViewIsInClassNamed(view, @"YTMNowPlayingView") ||
        YTMUViewIsInClassNamed(view, @"YTMPlayerControlsView") ||
        YTMUViewIsInClassNamed(view, @"YTMMiniplayerView") ||
        YTMUViewIsInClassNamed(view, @"YTMPlayerBarView") ||
        YTMUViewIsInClassNamed(view, @"YTMWatchView") ||
        YTMUViewIsInClassNamed(view, @"YTMContentView") ||
        YTMUViewIsInClassNamed(view, @"YTMAppView")) {
        return YES;
    }

    // 迷你条「投放」常在底部；用无障碍文案匹配时不再强依赖父类
    return YES;
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
    if ([cls containsString:@"AudioVideo"] || [cls containsString:@"AVSwitch"]) return YES;
    return NO;
}

static void YTMUHideView(UIView *view) {
    view.hidden = YES;
    view.alpha = 0;
    view.userInteractionEnabled = NO;
}

@interface QTMButton : UIButton
@end

%hook QTMButton
- (void)layoutSubviews {
    %orig;
    if (!YTMEnabled()) return;

    UIView *view = (UIView *)self;

    if (YTMU(@"hideCastButton") && YTMUIsCastButton(view) && YTMUIsNavBarContext(view)) {
        YTMUHideView(view);
        return;
    }

    if (YTMU(@"hidePlayerCastButton") && YTMUIsCastButton(view) && !YTMUIsNavBarContext(view)) {
        YTMUHideView(view);
        return;
    }

    if (YTMU(@"hideAVSwitchButton") && YTMUIsAVSwitchControl(view)) {
        YTMUHideView(view);
    }
}
%end

%hook UIButton
- (void)layoutSubviews {
    %orig;
    if (!YTMEnabled()) return;

    if (YTMU(@"hidePlayerCastButton") && YTMUIsCastButton(self) && !YTMUIsNavBarContext(self)) {
        YTMUHideView(self);
    }

    if (YTMU(@"hideAVSwitchButton") && YTMUIsAVSwitchControl(self)) {
        YTMUHideView(self);
    }
}
%end

%hook UIControl
- (void)layoutSubviews {
    %orig;
    if (!YTMEnabled()) return;

    // 分段控件形态的「正在播放歌曲」
    if (YTMU(@"hideAVSwitchButton") && YTMUIsAVSwitchControl(self)) {
        YTMUHideView(self);
    }
    if (YTMU(@"hidePlayerCastButton") && YTMUIsCastButton(self) && !YTMUIsNavBarContext(self)) {
        YTMUHideView(self);
    }
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
