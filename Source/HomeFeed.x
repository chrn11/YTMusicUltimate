#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
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

    NSArray *headerKeys = @[@"header", @"headerRenderer", @"musicResponsiveHeaderRenderer", @"musicShelfHeaderRenderer", @"musicCarouselShelfBasicHeaderRenderer"];
    for (NSString *key in headerKeys) {
        @try {
            id header = [section valueForKey:key];
            if (!header) continue;

            for (NSString *tKey in @[@"title", @"strapline"]) {
                @try {
                    NSString *title = YTMUExtractTitle([header valueForKey:tKey]);
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
                for (NSString *k in @[@"itemSectionRenderer", @"musicShelfRenderer", @"musicCarouselShelfRenderer", @"musicPlaylistShelfRenderer", @"gridRenderer"]) {
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

%hook YTISectionListRenderer
- (id)contentsArray {
    id orig = %orig;
    if (!(YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideHomeMusicVideos"))) return orig;
    if (![orig isKindOfClass:[NSArray class]]) return orig;
    return YTMUFilterSections(orig);
}
- (void)setContentsArray:(id)contents {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideHomeMusicVideos") && [contents isKindOfClass:[NSArray class]]) {
        %orig(YTMUFilterSections(contents));
        return;
    }
    %orig;
}
%end

%hook YTISectionListSupportedRenderers
- (id)itemSectionRenderer {
    id orig = %orig;
    if (!(YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideHomeMusicVideos"))) return orig;
    if (YTMUSectionLooksLikeMusicVideoShelf(orig)) return nil;
    return orig;
}
%end

// UI 层兜底：若 feed 已渲染，按货架标题隐藏 section header 及其后续行（弱兜底，主要依赖上面 protobuf 过滤）
%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    if (!(YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideHomeMusicVideos"))) return;
    if (!YTMUIsMusicVideoShelfTitle(text)) return;

    UIView *v = self;
    while (v.superview) {
        v = v.superview;
        NSString *cls = NSStringFromClass([v class]);
        if ([cls containsString:@"Shelf"] || [cls containsString:@"Section"] || [cls containsString:@"Carousel"] || [cls containsString:@"ItemSection"]) {
            v.hidden = YES;
            v.alpha = 0;
            break;
        }
    }
}
%end
