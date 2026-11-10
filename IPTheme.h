#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, IPThemeStyle) {
    IPThemeStyleLime = 0,
    IPThemeStyleBlue = 1,
    IPThemeStylePixel = 2,
};

typedef NS_ENUM(NSInteger, IPAppearanceMode) {
    IPAppearanceModeSystem = 0,
    IPAppearanceModeLight = 1,
    IPAppearanceModeDark = 2,
};

static NSString *const IPThemeStyleDefaultsKey = @"IPThemeStyle";
static NSString *const IPAppearanceModeDefaultsKey = @"IPAppearanceMode";
static NSString *const IPThemeDidChangeNotification = @"IPThemeDidChangeNotification";

static inline UIColor *IPColor(unsigned int rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
                          green:((rgb >> 8) & 255) / 255.0
                           blue:(rgb & 255) / 255.0 alpha:1];
}

static inline IPThemeStyle IPSelectedTheme(void) {
    if (![NSUserDefaults.standardUserDefaults objectForKey:IPThemeStyleDefaultsKey]) return IPThemeStyleBlue;
    NSInteger value = [NSUserDefaults.standardUserDefaults integerForKey:IPThemeStyleDefaultsKey];
    return value >= IPThemeStyleLime && value <= IPThemeStylePixel
        ? (IPThemeStyle)value : IPThemeStyleBlue;
}

static inline BOOL IPPixelUIEnabled(void) { return IPSelectedTheme() == IPThemeStylePixel; }
static inline CGFloat IPCornerRadius(CGFloat regular) { return IPPixelUIEnabled() ? 3.0 : regular; }

static inline IPAppearanceMode IPSelectedAppearance(void) {
    NSInteger value = [NSUserDefaults.standardUserDefaults integerForKey:IPAppearanceModeDefaultsKey];
    return value >= IPAppearanceModeSystem && value <= IPAppearanceModeDark
        ? (IPAppearanceMode)value : IPAppearanceModeSystem;
}

static inline UIUserInterfaceStyle IPPreferredInterfaceStyle(void) {
    switch (IPSelectedAppearance()) {
        case IPAppearanceModeLight: return UIUserInterfaceStyleLight;
        case IPAppearanceModeDark: return UIUserInterfaceStyleDark;
        default: return UIUserInterfaceStyleUnspecified;
    }
}

static inline UIColor *IPDynamicColor(unsigned int light, unsigned int dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return IPColor(traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light);
    }];
}

// Every screen consumes this semantic palette. The lime style keeps the
// original iPixel identity; Blue Files follows the supplied clean file-manager
// references. Both palettes provide independent light and dark values.
static inline UIColor *IPAccent(void) {
    if (IPPixelUIEnabled()) return IPDynamicColor(0x5B4BFF, 0x24E0FF);
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0x087CF0, 0x55A8FF)
        : IPDynamicColor(0x526900, 0xE8FF91);
}

static inline UIColor *IPBackground(void) {
    if (IPPixelUIEnabled()) return IPDynamicColor(0xEEF1FF, 0x080B1E);
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0xF3F6FA, 0x071321)
        : IPDynamicColor(0xF3F5EF, 0x171817);
}

static inline UIColor *IPSurface(void) {
    if (IPPixelUIEnabled()) return IPDynamicColor(0xFFFFFF, 0x11162D);
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0xFFFFFF, 0x0D2138)
        : IPDynamicColor(0xFFFFFF, 0x272927);
}

static inline UIColor *IPElevatedSurface(void) {
    if (IPPixelUIEnabled()) return IPDynamicColor(0xDFE4FF, 0x1C2445);
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0xE8F2FF, 0x132D4A)
        : IPDynamicColor(0xE9EDDF, 0x30332D);
}

static inline UIColor *IPPrimaryText(void) {
    if (IPPixelUIEnabled()) return IPDynamicColor(0x11142B, 0xF5F7FF);
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0x091426, 0xF4F8FF)
        : IPDynamicColor(0x1B1E17, 0xF7F8F4);
}

static inline UIColor *IPSecondaryText(void) {
    if (IPPixelUIEnabled()) return IPDynamicColor(0x5F6789, 0xAAB4DC);
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0x68768A, 0xA9B9CA)
        : IPDynamicColor(0x66705F, 0xB7BDB1);
}

static inline UIColor *IPSeparator(void) {
    if (IPPixelUIEnabled()) return IPDynamicColor(0xC9D0F2, 0x303A67);
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0xDCE5EF, 0x25415E)
        : IPDynamicColor(0xDCE1D6, 0x3A3E37);
}

static inline UIColor *IPTrack(void) {
    if (IPPixelUIEnabled()) return IPDynamicColor(0xCDD4F5, 0x313B69);
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0xD8E2ED, 0x294765)
        : IPDynamicColor(0xDDE4D2, 0x454940);
}

static inline UIColor *IPSelection(void) {
    if (IPPixelUIEnabled()) return IPDynamicColor(0xDADFFF, 0x28325D);
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0xD9EAFF, 0x183C61)
        : IPDynamicColor(0xE7F1C2, 0x3C442D);
}

static inline UIColor *IPCardColor(NSUInteger index) {
    static const unsigned int pixelLight[] = { 0xBFC7FF, 0x8FEAFF, 0xE1B8FF, 0xFFD09E, 0xAFCBFF, 0xA5F0D5 };
    static const unsigned int pixelDark[]  = { 0x2A3471, 0x134E67, 0x4B286B, 0x633E25, 0x203E75, 0x164F43 };
    static const unsigned int limeLight[] = { 0xE8FF91, 0xFFF3A0, 0xD9BEF2, 0xFFD2AE, 0xC5CEFF, 0xBFE9DC };
    static const unsigned int limeDark[]  = { 0x3D4B1F, 0x4D4520, 0x423153, 0x503724, 0x303958, 0x27483E };
    static const unsigned int blueLight[] = { 0xCFE7FF, 0xA9D2FF, 0xDDEEFF, 0xB6DBFF, 0xD7E3FF, 0xC5EAF5 };
    static const unsigned int blueDark[]  = { 0x123B65, 0x164B7F, 0x1A3857, 0x17558B, 0x263F70, 0x164A5B };
    index %= 6;
    if (IPPixelUIEnabled()) return IPDynamicColor(pixelLight[index], pixelDark[index]);
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(blueLight[index], blueDark[index])
        : IPDynamicColor(limeLight[index], limeDark[index]);
}

static inline UIColor *IPCardForeground(void) {
    return IPDynamicColor(0x07182D, 0xFFFFFF);
}

static inline UIFont *IPFont(CGFloat size, UIFontWeight weight) {
    if (IPPixelUIEnabled()) {
        NSString *name = weight >= UIFontWeightSemibold ? @"Menlo-Bold" : @"Menlo-Regular";
        UIFont *pixel = [UIFont fontWithName:name size:size];
        if (pixel) return pixel;
        return [UIFont monospacedSystemFontOfSize:size weight:weight];
    }
    UIFont *font = [UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *rounded = [font.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    return rounded ? [UIFont fontWithDescriptor:rounded size:size] : font;
}

static inline UIFont *IPTextFont(UIFontTextStyle style) {
    if (!IPPixelUIEnabled()) return [UIFont preferredFontForTextStyle:style];
    CGFloat size = 17;
    UIFontWeight weight = UIFontWeightRegular;
    if ([style isEqualToString:UIFontTextStyleLargeTitle]) { size = 32; weight = UIFontWeightBold; }
    else if ([style isEqualToString:UIFontTextStyleTitle1]) { size = 27; weight = UIFontWeightBold; }
    else if ([style isEqualToString:UIFontTextStyleTitle2]) { size = 21; weight = UIFontWeightBold; }
    else if ([style isEqualToString:UIFontTextStyleTitle3]) { size = 19; weight = UIFontWeightSemibold; }
    else if ([style isEqualToString:UIFontTextStyleHeadline]) { size = 16; weight = UIFontWeightBold; }
    else if ([style isEqualToString:UIFontTextStyleCallout]) size = 15;
    else if ([style isEqualToString:UIFontTextStyleSubheadline]) size = 14;
    else if ([style isEqualToString:UIFontTextStyleFootnote]) size = 12;
    else if ([style isEqualToString:UIFontTextStyleCaption1]) size = 11;
    else if ([style isEqualToString:UIFontTextStyleCaption2]) size = 10;
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:IPFont(size, weight)];
}

static inline void IPStyleCell(UITableViewCell *cell) {
    if (IPPixelUIEnabled() && [cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]) {
        UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
        content.textProperties.font = IPFont(16, UIFontWeightSemibold);
        content.secondaryTextProperties.font = IPFont(11, UIFontWeightRegular);
        cell.contentConfiguration = content;
    }
    UIBackgroundConfiguration *background = [UIBackgroundConfiguration clearConfiguration];
    background.backgroundColor = IPSurface();
    background.cornerRadius = IPPixelUIEnabled() ? 3 : 18;
    background.backgroundInsets = NSDirectionalEdgeInsetsMake(5, 12, 5, 12);
    cell.backgroundConfiguration = background;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.contentView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(15, 26, 15, 26);
    UIView *selected = [UIView new];
    selected.backgroundColor = IPSelection();
    cell.selectedBackgroundView = selected;
    cell.contentView.layer.magnificationFilter = IPPixelUIEnabled() ? kCAFilterNearest : kCAFilterLinear;
}

static inline void IPStyleSearchBar(UISearchBar *searchBar) {
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    searchBar.backgroundImage = [UIImage new];
    searchBar.tintColor = IPAccent();
    // iOS 26 supplies the outer glass capsule. A second opaque text-field
    // background creates the rectangular overlay seen in the old build.
    searchBar.searchTextField.backgroundColor = UIColor.clearColor;
    searchBar.searchTextField.textColor = IPPrimaryText();
    searchBar.searchTextField.leftView.tintColor = IPAccent();
    searchBar.searchTextField.font = IPFont(16, UIFontWeightRegular);
}

static inline void IPInstallAppearance(void) {
    UINavigationBarAppearance *bar = [UINavigationBarAppearance new];
    [bar configureWithOpaqueBackground];
    bar.backgroundColor = IPBackground();
    bar.shadowColor = UIColor.clearColor;
    bar.titleTextAttributes = @{ NSForegroundColorAttributeName: IPPrimaryText(),
                                 NSFontAttributeName: IPFont(18, UIFontWeightSemibold) };
    bar.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: IPPrimaryText(),
                                      NSFontAttributeName: IPFont(34, UIFontWeightBold) };
    UINavigationBar.appearance.standardAppearance = bar;
    UINavigationBar.appearance.scrollEdgeAppearance = bar;
    UINavigationBar.appearance.compactAppearance = bar;
    UINavigationBar.appearance.tintColor = IPAccent();

    UIToolbarAppearance *toolbar = [UIToolbarAppearance new];
    [toolbar configureWithOpaqueBackground];
    toolbar.backgroundColor = IPBackground();
    toolbar.shadowColor = UIColor.clearColor;
    UIToolbar.appearance.standardAppearance = toolbar;
    UIToolbar.appearance.scrollEdgeAppearance = toolbar;
    UIToolbar.appearance.tintColor = IPAccent();

    UITableView.appearance.backgroundColor = IPBackground();
    UITableView.appearance.separatorColor = IPSeparator();
    UITableViewCell.appearance.backgroundColor = IPSurface();
    UICollectionView.appearance.backgroundColor = IPBackground();
    UITextView.appearance.backgroundColor = IPBackground();
    UITextView.appearance.textColor = IPPrimaryText();
    UISearchBar.appearance.tintColor = IPAccent();
    UISearchTextField.appearance.backgroundColor = UIColor.clearColor;
    UISearchTextField.appearance.textColor = IPPrimaryText();
    UIRefreshControl.appearance.tintColor = IPAccent();
    UIActivityIndicatorView.appearance.color = IPAccent();
    UIProgressView.appearance.progressTintColor = IPAccent();
    UIProgressView.appearance.trackTintColor = IPTrack();
    UISwitch.appearance.onTintColor = IPAccent();
}
