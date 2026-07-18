#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

static BOOL YTMUHomeMVEnabled(void) {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideHomeMusicVideos");
}

static NSString *YTMUExtractTitle(id object) {
    if (!object) return nil;

    if ([object isKindOfClass:[NSString class]]) {
        return (NSString *)object;
    }

    if ([object respondsToSelector:@selector(string)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id str = [object performSelector:@selector(string)];
#pragma clang diagnostic pop
        if ([str isKindOfClass:[NSString class]]) return str;
    }

    if ([object respondsToSelector:@selector(runsArray)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *runs = [object performSelector:@selector(runsArray)];
#pragma clang diagnostic pop
        NSMutableString *joined = [NSMutableString string];
        for (id run in runs) {
            if ([run respondsToSelector:@selector(text)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id text = [run performSelector:@selector(text)];
#pragma clang diagnostic pop
                if ([text isKindOfClass:[NSString class]]) [joined appendString:text];
            }
        }
        if (joined.length) return joined;
    }

    return nil;
}

static NSString *YTMUSectionTitle(id section) {
    if (!section) return nil;

    NSArray *headerKeys = @[
        @"header",
        @"headerRenderer",
        @"musicResponsiveHeaderRenderer",
        @"musicShelfHeaderRenderer",
        @"musicCarouselShelfBasicHeaderRenderer",
        @"musicImmersiveCarouselShelfBasicHeaderRenderer"
    ];
    for (NSString *key in headerKeys) {
        @try {
            id header = [section valueForKey:key];
            if (!header) continue;

            for (NSString *tKey in @[@"title", @"strapline", @"accessibilityText"]) {
                @try {
                    NSString *title = YTMUExtractTitle([header valueForKey:tKey]);
                    if (title.length) return title;
                } @catch (__unused NSException *e) {}
            }

            // header 再包一层 basicHeader
            for (NSString *nested in @[@"musicCarouselShelfBasicHeaderRenderer", @"musicResponsiveHeaderRenderer"]) {
                @try {
                    id inner = [header valueForKey:nested];
                    NSString *title = YTMUExtractTitle([inner valueForKey:@"title"]);
                    if (title.length) return title;
                } @catch (__unused NSException *e) {}
            }
        } @catch (__unused NSException *e) {}
    }

    @try {
        NSString *t = YTMUExtractTitle([section valueForKey:@"title"]);
        if (t.length) return t;
    } @catch (__unused NSException *e) {}

    return nil;
}

// 真机实测首页货架标题：为你推荐的音乐视频
static BOOL YTMUIsMusicVideoShelfTitle(NSString *title) {
    if (!title.length) return NO;

    if ([title containsString:@"为你推荐的音乐视频"] ||
        [title containsString:@"為你推薦的音樂影片"] ||
        [title isEqualToString:@"音乐视频"] ||
        [title isEqualToString:@"音樂影片"]) {
        return YES;
    }

    NSString *t = title.lowercaseString;
    if ([t containsString:@"music videos for you"] ||
        [t isEqualToString:@"music videos"] ||
        [t containsString:@"recommended music videos"]) {
        return YES;
    }
    return NO;
}

static BOOL YTMUSectionLooksLikeMusicVideoShelf(id section) {
    return YTMUIsMusicVideoShelfTitle(YTMUSectionTitle(section));
}

static NSArray *YTMUFilterSections(NSArray *sections) {
    if (![sections isKindOfClass:[NSArray class]] || sections.count == 0) return sections;

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:sections.count];
    for (id section in sections) {
        id actual = section;
        @try {
            if ([section respondsToSelector:@selector(valueForKey:)]) {
                for (NSString *k in @[
                    @"itemSectionRenderer",
                    @"musicShelfRenderer",
                    @"musicCarouselShelfRenderer",
                    @"musicImmersiveCarouselShelfRenderer",
                    @"musicPlaylistShelfRenderer",
                    @"gridRenderer"
                ]) {
                    id nested = nil;
                    @try { nested = [section valueForKey:k]; } @catch (__unused NSException *e) {}
                    if (nested) { actual = nested; break; }
                }
            }
        } @catch (__unused NSException *e) {}

        if (YTMUSectionLooksLikeMusicVideoShelf(actual) || YTMUSectionLooksLikeMusicVideoShelf(section)) {
            continue;
        }
        [filtered addObject:section];
    }
    return filtered;
}

static void YTMUHideView(UIView *view) {
    if (!view) return;
    view.hidden = YES;
    view.alpha = 0;
    view.userInteractionEnabled = NO;
}

// 真机：标题行 + 横向视频卡整体约 height≈317
static void YTMUHideMusicVideoShelfFromTitleView(UIView *titleView) {
    if (!titleView) return;

    UIView *best = nil;
    UIView *v = titleView;
    while (v.superview) {
        v = v.superview;
        CGSize sz = v.bounds.size;
        NSString *cls = NSStringFromClass([v class]);
        if ([cls containsString:@"Shelf"] ||
            [cls containsString:@"Carousel"] ||
            [cls containsString:@"ItemSection"] ||
            [cls containsString:@"Section"]) {
            best = v;
            break;
        }
        // 全宽、高度覆盖标题+卡片的容器
        if (sz.width >= UIScreen.mainScreen.bounds.size.width - 24 && sz.height >= 180 && sz.height <= 520) {
            best = v;
        }
    }

    if (best) {
        YTMUHideView(best);
        return;
    }

    // 弱兜底：藏标题所在行及其父级
    YTMUHideView(titleView);
    if (titleView.superview) YTMUHideView(titleView.superview);
}

%hook YTISectionListRenderer
- (id)contentsArray {
    id orig = %orig;
    if (!YTMUHomeMVEnabled()) return orig;
    if (![orig isKindOfClass:[NSArray class]]) return orig;
    return YTMUFilterSections(orig);
}
- (void)setContentsArray:(id)contents {
    if (YTMUHomeMVEnabled() && [contents isKindOfClass:[NSArray class]]) {
        %orig(YTMUFilterSections(contents));
        return;
    }
    %orig;
}
%end

%hook YTISectionListSupportedRenderers
- (id)itemSectionRenderer {
    id orig = %orig;
    if (!YTMUHomeMVEnabled()) return orig;
    if (YTMUSectionLooksLikeMusicVideoShelf(orig)) return nil;
    return orig;
}
%end

%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    if (!YTMUHomeMVEnabled()) return;
    if (!YTMUIsMusicVideoShelfTitle(text)) return;
    YTMUHideMusicVideoShelfFromTitleView(self);
}
- (void)setAttributedText:(NSAttributedString *)attr {
    %orig;
    if (!YTMUHomeMVEnabled()) return;
    if (!YTMUIsMusicVideoShelfTitle(attr.string)) return;
    YTMUHideMusicVideoShelfFromTitleView(self);
}
%end

%hook UIView
- (void)setAccessibilityLabel:(NSString *)label {
    %orig;
    if (!YTMUHomeMVEnabled()) return;
    if (!YTMUIsMusicVideoShelfTitle(label)) return;
    YTMUHideMusicVideoShelfFromTitleView(self);
}

- (void)didMoveToWindow {
    %orig;
    if (!YTMUHomeMVEnabled() || !self.window) return;
    if (YTMUIsMusicVideoShelfTitle(self.accessibilityLabel)) {
        YTMUHideMusicVideoShelfFromTitleView(self);
    }
}
%end
