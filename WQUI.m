//
//  WQUI.m
//  WQ Files shared UI helpers
//  GPL-3.0-or-later.
//

#import "WQUI.h"
#import "WQAccess.h"
#import "WQLaunchServices.h"
#import "IPTheme.h"
#import <sys/sysctl.h>
#import <sys/utsname.h>

// "iPhone 17 Pro Max (iPhone18,2)\niOS 27.0.1 (24A446)"
NSString *wq_device_line(void)
{
    struct utsname u;
    NSString *machine = (uname(&u) == 0) ? @(u.machine) : @"unknown";
    char build[64] = {0};
    size_t len = sizeof(build);
    NSString *buildStr = (sysctlbyname("kern.osversion", build, &len, NULL, 0) == 0) ? @(build) : nil;
    NSDictionary *names = @{
        @"iPhone17,1": @"iPhone 16 Pro", @"iPhone17,2": @"iPhone 16 Pro Max",
        @"iPhone17,3": @"iPhone 16", @"iPhone17,4": @"iPhone 16 Plus", @"iPhone17,5": @"iPhone 16e",
        @"iPhone18,1": @"iPhone 17 Pro", @"iPhone18,2": @"iPhone 17 Pro Max",
        @"iPhone18,3": @"iPhone 17", @"iPhone18,4": @"iPhone Air",
    };
    NSString *marketing = names[machine];
    NSString *model = marketing ? [NSString stringWithFormat:@"%@ (%@)", marketing, machine] : machine;
    NSString *ver = UIDevice.currentDevice.systemVersion;
    return buildStr ? [NSString stringWithFormat:@"%@ · iOS %@ (%@)", model, ver, buildStr]
                    : [NSString stringWithFormat:@"%@ · iOS %@", model, ver];
}

float wq_progress_from_text(NSString *text)
{
    if (!text.length) return -1;
    NSRegularExpression *percent = [NSRegularExpression regularExpressionWithPattern:@"([0-9]{1,3})%"
        options:0 error:nil];
    NSTextCheckingResult *match = [percent firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (match.numberOfRanges > 1) {
        NSInteger value = [[text substringWithRange:[match rangeAtIndex:1]] integerValue];
        return (float)MAX(0, MIN(100, value)) / 100.0f;
    }
    NSRegularExpression *fraction = [NSRegularExpression regularExpressionWithPattern:@"([0-9]+)\\s*/\\s*([0-9]+)"
        options:0 error:nil];
    match = [fraction firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (match.numberOfRanges > 2) {
        float done = [[text substringWithRange:[match rangeAtIndex:1]] floatValue];
        float total = [[text substringWithRange:[match rangeAtIndex:2]] floatValue];
        return total > 0 ? MAX(0, MIN(1, done / total)) : -1;
    }
    return -1;
}

@interface WQFolderLayerView : UIView
@property (nonatomic, strong) UIColor *fillColor;
@end

@implementation WQFolderLayerView
- (void)drawRect:(CGRect)rect
{
    CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
    CGFloat tabHeight = h * 0.22, radius = MIN(16, h * 0.16);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(radius, tabHeight)];
    [path addLineToPoint:CGPointMake(w * 0.38, tabHeight)];
    [path addCurveToPoint:CGPointMake(w * 0.5, h * 0.35)
            controlPoint1:CGPointMake(w * 0.43, tabHeight)
            controlPoint2:CGPointMake(w * 0.43, h * 0.35)];
    [path addLineToPoint:CGPointMake(w - radius, h * 0.35)];
    [path addQuadCurveToPoint:CGPointMake(w, h * 0.35 + radius) controlPoint:CGPointMake(w, h * 0.35)];
    [path addLineToPoint:CGPointMake(w, h - radius)];
    [path addQuadCurveToPoint:CGPointMake(w - radius, h) controlPoint:CGPointMake(w, h)];
    [path addLineToPoint:CGPointMake(radius, h)];
    [path addQuadCurveToPoint:CGPointMake(0, h - radius) controlPoint:CGPointMake(0, h)];
    [path addLineToPoint:CGPointMake(0, tabHeight + radius)];
    [path addQuadCurveToPoint:CGPointMake(radius, tabHeight) controlPoint:CGPointMake(0, tabHeight)];
    [path closePath];
    [self.fillColor setFill];
    [path fill];
}
@end

UIView *wq_folder_stack_view(CGSize size, BOOL animated)
{
    UIView *container = [[UIView alloc] initWithFrame:(CGRect){CGPointZero, size}];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [container.widthAnchor constraintEqualToConstant:size.width],
        [container.heightAnchor constraintEqualToConstant:size.height],
    ]];
    NSArray<UIColor *> *colors;
    if (IPSelectedTheme() == IPThemeStyleLime) {
        colors = @[
            IPDynamicColor(0xFFF8A8, 0xFFF59D), IPDynamicColor(0xE8FF55, 0xD8F238),
            IPDynamicColor(0xA8D900, 0xB8E61B), IPDynamicColor(0x526900, 0x718D00),
        ];
    } else if (IPPixelUIEnabled()) {
        colors = @[
            IPDynamicColor(0xDDE2FF, 0x90F0FF), IPDynamicColor(0x8D80FF, 0x35D6FF),
            IPDynamicColor(0x5B4BFF, 0x7667FF), IPDynamicColor(0x211B65, 0x25306E),
        ];
    } else {
        colors = @[
            IPDynamicColor(0xB9DBFF, 0x8CC5FF), IPDynamicColor(0x1685F8, 0x2A91FF),
            IPDynamicColor(0x0A55AF, 0x176AC5), IPDynamicColor(0x041D3D, 0x082C55),
        ];
    }
    CGFloat layerHeight = size.height * 0.46;
    for (NSUInteger i = 0; i < colors.count; i++) {
        WQFolderLayerView *folder = [[WQFolderLayerView alloc] initWithFrame:
            CGRectMake(size.width * 0.06, size.height * (0.04 + i * 0.16), size.width * 0.88, layerHeight)];
        folder.backgroundColor = UIColor.clearColor;
        folder.fillColor = colors[i];
        folder.layer.shadowColor = (IPSelectedTheme() == IPThemeStyleLime ? IPColor(0x3B4700) : IPColor(0x00152E)).CGColor;
        folder.layer.shadowOpacity = i == colors.count - 1 ? 0.22 : 0.10;
        folder.layer.shadowRadius = 8;
        folder.layer.shadowOffset = CGSizeMake(0, 5);
        [container addSubview:folder];
        if (animated) {
            CAKeyframeAnimation *floatAnimation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
            floatAnimation.values = @[@0, @(-5 - (NSInteger)i), @0];
            floatAnimation.keyTimes = @[@0, @0.5, @1];
            floatAnimation.duration = 1.35;
            floatAnimation.beginTime = CACurrentMediaTime() + i * 0.10;
            floatAnimation.repeatCount = HUGE_VALF;
            floatAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [folder.layer addAnimation:floatAnimation forKey:@"folderFloat"];
        }
    }
    return container;
}

// Compact device card shared by the Apps and Cache screens.
UIView *wq_device_header(CGFloat width)
{
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 92)];
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 8, MAX(1, width - 32), 68)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = IPElevatedSurface();
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.cornerRadius = IPCornerRadius(20);
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"iphone.gen3"]];
    icon.frame = CGRectMake(16, 17, 34, 34);
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = IPAccent();
    UILabel *eyebrow = [[UILabel alloc] initWithFrame:CGRectMake(64, 12, MAX(1, width - 128), 18)];
    eyebrow.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    eyebrow.text = @"THIS DEVICE";
    eyebrow.font = IPFont(11, UIFontWeightBold);
    eyebrow.textColor = IPAccent();
    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(64, 29, MAX(1, width - 128), 27)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.font = IPFont(13, UIFontWeightMedium);
    header.adjustsFontSizeToFitWidth = YES;
    header.minimumScaleFactor = 0.75;
    header.textColor = IPPrimaryText();
    header.text = wq_device_line();
    [card addSubview:icon];
    [card addSubview:eyebrow];
    [card addSubview:header];
    [box addSubview:card];
    return box;
}

@implementation WQLoadingCardCell {
    UILabel *_loadingTitle;
    UILabel *_loadingStatus;
    UIProgressView *_loadingProgress;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        UIView *folders = wq_folder_stack_view(CGSizeMake(68, 68), YES);
        _loadingTitle = [UILabel new];
        _loadingTitle.font = IPFont(20, UIFontWeightBold);
        _loadingTitle.textColor = IPPrimaryText();
        _loadingStatus = [UILabel new];
        _loadingStatus.font = IPTextFont(UIFontTextStyleFootnote);
        _loadingStatus.textColor = IPSecondaryText();
        _loadingStatus.numberOfLines = 2;
        _loadingProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _loadingProgress.progressTintColor = IPAccent();
        _loadingProgress.trackTintColor = IPTrack();
        _loadingProgress.layer.cornerRadius = 3;
        _loadingProgress.clipsToBounds = YES;
        _loadingProgress.transform = CGAffineTransformMakeScale(1, 2.2);
        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[_loadingTitle, _loadingStatus, _loadingProgress]];
        text.axis = UILayoutConstraintAxisVertical;
        text.spacing = 8;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[folders, text]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentCenter;
        row.spacing = 16;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:24],
            [row.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-24],
            [row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:18],
            [row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-18],
        ]];
        IPStyleCell(self);
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title status:(NSString *)status progress:(float)progress
{
    _loadingTitle.text = title;
    _loadingStatus.text = status.length ? status : @"Preparing…";
    if (progress >= 0) {
        [_loadingProgress.layer removeAnimationForKey:@"loadingPulse"];
        [_loadingProgress setProgress:progress animated:YES];
    } else {
        _loadingProgress.progress = 0.32;
        if (![_loadingProgress.layer animationForKey:@"loadingPulse"]) {
            CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
            pulse.fromValue = @0.35;
            pulse.toValue = @1;
            pulse.duration = 0.75;
            pulse.autoreverses = YES;
            pulse.repeatCount = HUGE_VALF;
            [_loadingProgress.layer addAnimation:pulse forKey:@"loadingPulse"];
        }
    }
}

@end

// Private: app icon by bundle id (in UIKit; guarded with respondsToSelector).
@interface UIImage (WQPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)fmt scale:(CGFloat)scale;
@end

// Small grey fingerprint of an icon, to recognise iOS's blank placeholder.
static NSData *wq_icon_fingerprint(UIImage *img)
{
    const size_t s = 12;
    uint8_t px[12 * 12 * 4] = {0};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, s, s, 8, s * 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!ctx) return nil;
    if (img.CGImage) CGContextDrawImage(ctx, CGRectMake(0, 0, s, s), img.CGImage);
    CGContextRelease(ctx);
    return [NSData dataWithBytes:px length:sizeof(px)];
}

static UIImage *wq_raw_icon(NSString *bundleID)
{
    if (![UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) return nil;
    CGFloat scale = 2.0; // Safe fallback for background preparation without UI context.
    if (NSThread.isMainThread) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) {
                scale = ((UIWindowScene *)scene).screen.scale;
                break;
            }
        }
    }
    return [UIImage _applicationIconImageForBundleIdentifier:bundleID format:2 scale:scale];
}

// The real icon for bundleID, or nil when iOS only has its placeholder.
static UIImage *wq_real_icon(NSString *bundleID)
{
    static NSData *placeholder;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ placeholder = wq_icon_fingerprint(wq_raw_icon(@"cz.kolbi.wqfiles.no-such-app")); });
    UIImage *raw = wq_raw_icon(bundleID);
    if (!raw || !raw.CGImage) return nil;
    NSData *fp = wq_icon_fingerprint(raw);
    if (!placeholder || fp.length != placeholder.length) return raw;
    // Near-identical to the placeholder (allow small rendering differences).
    const uint8_t *a = fp.bytes, *b = placeholder.bytes;
    unsigned long diff = 0;
    for (NSUInteger i = 0; i < fp.length; i++) diff += (unsigned long)abs((int)a[i] - (int)b[i]);
    return diff / fp.length < 8 ? nil : raw;
}

// The icon from the app's own bundle, for when iOS only hands out its
// placeholder (iOS 26 refuses this app's icon requests). Reads the primary
// icon names from Info.plist and loads the matching PNG files.
static UIImage *wq_bundle_icon(NSString *bundleID)
{
    NSString *path = wq_bundle_path_for_id(bundleID);
    if (!path.length) return nil;
    NSString *plistPath = [path stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (!info && wq_grant(path)) info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (![info isKindOfClass:NSDictionary.class]) return nil;
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    for (NSString *key in @[@"CFBundleIcons", @"CFBundleIcons~ipad"]) {
        NSDictionary *primary = [info[key] isKindOfClass:NSDictionary.class] ? info[key][@"CFBundlePrimaryIcon"] : nil;
        if (![primary isKindOfClass:NSDictionary.class]) continue;
        if ([primary[@"CFBundleIconName"] isKindOfClass:NSString.class]) [names addObject:primary[@"CFBundleIconName"]];
        NSArray *files = [primary[@"CFBundleIconFiles"] isKindOfClass:NSArray.class] ? primary[@"CFBundleIconFiles"] : @[];
        for (id file in files.reverseObjectEnumerator) if ([file isKindOfClass:NSString.class]) [names addObject:file];
    }
    if ([info[@"CFBundleIconFile"] isKindOfClass:NSString.class]) [names addObject:info[@"CFBundleIconFile"]];
    [names addObjectsFromArray:@[@"AppIcon60x60", @"AppIcon"]];
    // Only the PNG files apps ship next to their asset catalog. Loading from
    // the catalog (UIImage imageNamed:inBundle:) aborts inside UIKit when an
    // entry exists but can't be rendered (crash on 27.0.1, build 21).
    for (NSString *name in names) {
        NSString *base = name.stringByDeletingPathExtension;
        for (NSString *suffix in @[@"@3x.png", @"@2x.png", @"@2x~ipad.png", @"~ipad.png", @".png"]) {
            UIImage *image = [UIImage imageWithContentsOfFile:[path stringByAppendingPathComponent:[base stringByAppendingString:suffix]]];
            if (image.CGImage) return image;
        }
    }
    return nil;
}

static UIImage *wq_round_icon(UIImage *raw)
{
    CGFloat s = 40;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(s, s)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *__unused ctx) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, s, s) cornerRadius:s * 0.225] addClip];
        [raw drawInRect:CGRectMake(0, 0, s, s)];
    }];
}

// Symbol tile for system services and extensions that have no icon at all,
// picked from keywords in the bundle id.
static UIImage *wq_service_tile(NSString *bundleID)
{
    static NSArray<NSArray *> *rules;
    static NSCache *tiles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tiles = [NSCache new];
        UIColor *blue = UIColor.systemBlueColor, *green = UIColor.systemGreenColor, *red = UIColor.systemRedColor,
                *orange = UIColor.systemOrangeColor, *purple = UIColor.systemPurpleColor, *indigo = UIColor.systemIndigoColor,
                *teal = UIColor.systemTealColor, *pink = UIColor.systemPinkColor, *gray = UIColor.systemGrayColor;
        // keywords (lower case, any match), symbol, colour
        rules = @[
            @[@[@"emoji"], @"face.smiling.inverse", orange],
            @[@[@"keyboard", @"inputui", @"textinput", @"dictation"], @"keyboard.fill", gray],
            @[@[@"airdrop", @"sharing", @"sharesheet"], @"antenna.radiowaves.left.and.right", blue],
            @[@[@"widget", @"chrono"], @"square.grid.2x2.fill", blue],
            @[@[@"screenshot", @"screencapture", @"screenrecord"], @"camera.viewfinder", indigo],
            @[@[@"poster", @"wallpaper"], @"photo.on.rectangle.angled", purple],
            @[@[@"siri", @"assistant"], @"waveform", indigo],
            @[@[@"camera"], @"camera.fill", gray],
            @[@[@"photo"], @"photo.fill", orange],
            @[@[@"music", @"audio", @"shazam", @"musicrecognition"], @"music.note", pink],
            @[@[@"headphone", @"airpods", @"bluetooth"], @"headphones", gray],
            @[@[@"hearing"], @"ear.fill", blue],
            @[@[@"weather"], @"cloud.sun.fill", teal],
            @[@[@"location", @"maps", @"navigation"], @"location.fill", blue],
            @[@[@"health", @"fitness", @"workout"], @"heart.fill", red],
            @[@[@"pay", @"wallet", @"passbook", @"cash", @"finance"], @"creditcard.fill", green],
            @[@[@"mail"], @"envelope.fill", blue],
            @[@[@"message", @"sms", @"imessage"], @"message.fill", green],
            @[@[@"facetime", @"video"], @"video.fill", green],
            @[@[@"phone", @"call", @"telephony"], @"phone.fill", green],
            @[@[@"notification", @"usernotification", @"bulletin"], @"bell.fill", red],
            @[@[@"shortcut", @"workflow", @"intent"], @"square.on.square", indigo],
            @[@[@"safari", @"web"], @"safari.fill", blue],
            @[@[@"news", @"stocks"], @"newspaper.fill", red],
            @[@[@"calendar", @"event"], @"calendar", red],
            @[@[@"note", @"paper"], @"note.text", orange],
            @[@[@"reminder"], @"checklist", blue],
            @[@[@"game"], @"gamecontroller.fill", purple],
            @[@[@"auth", @"account", @"appsso", @"password", @"keychain", @"tcc", @"privacy"], @"lock.fill", gray],
            @[@[@"print"], @"printer.fill", gray],
            @[@[@"clarity", @"accessib"], @"accessibility", blue],
            @[@[@"home"], @"house.fill", orange],
            @[@[@"findmy", @"fmd", @"fmip"], @"location.circle.fill", green],
            @[@[@"carplay", @"carradio", @"cartrip", @"car."], @"car.fill", gray],
            @[@[@"tvremote", @"tvsetup", @"com.apple.tv"], @"tv.fill", gray],
            @[@[@"book"], @"book.fill", orange],
            @[@[@"podcast"], @"mic.fill", purple],
            @[@[@"spotlight", @"search"], @"magnifyingglass", gray],
            @[@[@"diagnostic", @"logging", @"crash", @"analytics"], @"stethoscope", gray],
            @[@[@"font"], @"textformat", gray],
            @[@[@"translate"], @"character.bubble.fill", blue],
            @[@[@"file", @"document", @"cloud"], @"folder.fill", blue],
            @[@[@"setup", @"buddy", @"onboarding"], @"gearshape.2.fill", gray],
        ];
    });
    NSString *key = bundleID.lowercaseString;
    NSString *symbol = @"gearshape.fill";
    UIColor *color = UIColor.systemGrayColor;
    for (NSArray *rule in rules) {
        BOOL hit = NO;
        for (NSString *word in rule[0]) if ([key containsString:word]) { hit = YES; break; }
        if (hit) { symbol = rule[1]; color = rule[2]; break; }
    }
    NSString *cacheKey = [symbol stringByAppendingString:color.description];
    UIImage *tile = [tiles objectForKey:cacheKey];
    if (tile) return tile;
    CGFloat s = 40;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(s, s)];
    UIColor *fill = [color resolvedColorWithTraitCollection:[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight]];
    tile = [r imageWithActions:^(UIGraphicsImageRendererContext *__unused ctx) {
        [fill setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, s, s) cornerRadius:s * 0.225] fill];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold];
        UIImage *g = [[UIImage systemImageNamed:symbol withConfiguration:cfg] ?: [UIImage systemImageNamed:@"gearshape.fill" withConfiguration:cfg]
                      imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        [g drawInRect:CGRectMake((s - g.size.width) / 2, (s - g.size.height) / 2, g.size.width, g.size.height)];
    }];
    [tiles setObject:tile forKey:cacheKey];
    return tile;
}

// Rounded app icon for a bundle id, cached. Falls back to the closest parent
// app's icon (extensions: com.foo.app.widget -> com.foo.app), then to a
// neutral service tile. Nil only without a bundle id.
UIImage *wq_app_icon(NSString *bundleID)
{
    if (!bundleID.length) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    UIImage *cached = [cache objectForKey:bundleID];
    if (cached) return cached;
    // The bundle fallback reads files and may ask for access: never on the
    // main thread. Lists warm the cache from their background passes; a
    // main-thread miss gets the tile without caching it.
    BOOL background = !NSThread.isMainThread;
    UIImage *raw = wq_real_icon(bundleID) ?: (background ? wq_bundle_icon(bundleID) : nil);
    NSArray *parts = [bundleID componentsSeparatedByString:@"."];
    for (NSInteger n = (NSInteger)parts.count - 1; !raw && n >= 3; n--)
    {
        NSString *parent = [[parts subarrayWithRange:NSMakeRange(0, (NSUInteger)n)] componentsJoinedByString:@"."];
        raw = wq_real_icon(parent) ?: (background ? wq_bundle_icon(parent) : nil);
    }
    UIImage *icon = raw ? wq_round_icon(raw) : wq_service_tile(bundleID);
    if (raw || background) [cache setObject:icon forKey:bundleID];
    return icon;
}

dispatch_queue_t wq_io(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("wqfiles.io", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

void wq_alert(UIViewController *host, NSString *title, NSString *message)
{
    if (!host || !host.isViewLoaded || !host.view.window) return;
    UIWindowScene *scene = host.view.window.windowScene;
    if (scene && scene.activationState != UISceneActivationStateForegroundActive) return;
    UINavigationController *nav = host.navigationController;
    if (nav && nav.topViewController != host) return;
    if (host.presentedViewController && !host.presentedViewController.isBeingDismissed) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [host presentViewController:alert animated:YES completion:nil];
}

NSString *wq_size_text(unsigned long long size)
{
    if (size == 0) return @"0 KB";
    return [NSByteCountFormatter stringFromByteCount:(long long)size countStyle:NSByteCountFormatterCountStyleFile];
}
