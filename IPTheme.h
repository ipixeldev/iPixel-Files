#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, IPThemeStyle) {
    IPThemeStyleLime = 0,
    IPThemeStyleBlue = 1,
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
    return value == IPThemeStyleBlue ? IPThemeStyleBlue : IPThemeStyleLime;
}

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
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0x087CF0, 0x55A8FF)
        : IPDynamicColor(0x526900, 0xE8FF91);
}

static inline UIColor *IPBackground(void) {
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0xF3F6FA, 0x071321)
        : IPDynamicColor(0xF3F5EF, 0x171817);
}

static inline UIColor *IPSurface(void) {
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0xFFFFFF, 0x0D2138)
        : IPDynamicColor(0xFFFFFF, 0x272927);
}

static inline UIColor *IPElevatedSurface(void) {
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0xE8F2FF, 0x132D4A)
        : IPDynamicColor(0xE9EDDF, 0x30332D);
}

static inline UIColor *IPPrimaryText(void) {
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0x091426, 0xF4F8FF)
        : IPDynamicColor(0x1B1E17, 0xF7F8F4);
}

static inline UIColor *IPSecondaryText(void) {
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0x68768A, 0xA9B9CA)
        : IPDynamicColor(0x66705F, 0xB7BDB1);
}

static inline UIColor *IPSeparator(void) {
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0xDCE5EF, 0x25415E)
        : IPDynamicColor(0xDCE1D6, 0x3A3E37);
}

static inline UIColor *IPTrack(void) {
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0xD8E2ED, 0x294765)
        : IPDynamicColor(0xDDE4D2, 0x454940);
}

static inline UIColor *IPSelection(void) {
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(0xD9EAFF, 0x183C61)
        : IPDynamicColor(0xE7F1C2, 0x3C442D);
}

static inline UIColor *IPCardColor(NSUInteger index) {
    static const unsigned int limeLight[] = { 0xE8FF91, 0xFFF3A0, 0xD9BEF2, 0xFFD2AE, 0xC5CEFF, 0xBFE9DC };
    static const unsigned int limeDark[]  = { 0x3D4B1F, 0x4D4520, 0x423153, 0x503724, 0x303958, 0x27483E };
    static const unsigned int blueLight[] = { 0xCFE7FF, 0xA9D2FF, 0xDDEEFF, 0xB6DBFF, 0xD7E3FF, 0xC5EAF5 };
    static const unsigned int blueDark[]  = { 0x123B65, 0x164B7F, 0x1A3857, 0x17558B, 0x263F70, 0x164A5B };
    index %= 6;
    return IPSelectedTheme() == IPThemeStyleBlue
        ? IPDynamicColor(blueLight[index], blueDark[index])
        : IPDynamicColor(limeLight[index], limeDark[index]);
}

static inline UIColor *IPCardForeground(void) {
    return IPDynamicColor(0x07182D, 0xFFFFFF);
}

static inline UIFont *IPFont(CGFloat size, UIFontWeight weight) {
    UIFont *font = [UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *rounded = [font.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    return rounded ? [UIFont fontWithDescriptor:rounded size:size] : font;
}

static inline void IPStyleCell(UITableViewCell *cell) {
    UIBackgroundConfiguration *background = [UIBackgroundConfiguration clearConfiguration];
    background.backgroundColor = IPSurface();
    background.cornerRadius = 18;
    background.backgroundInsets = NSDirectionalEdgeInsetsMake(5, 12, 5, 12);
    cell.backgroundConfiguration = background;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.contentView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(15, 26, 15, 26);
    UIView *selected = [UIView new];
    selected.backgroundColor = IPSelection();
    cell.selectedBackgroundView = selected;
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
