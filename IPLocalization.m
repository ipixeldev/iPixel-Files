#import "IPLocalization.h"
#import <objc/runtime.h>

NSString *IPSelectedLanguageCode(void)
{
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:IPLanguageDefaultsKey];
    if ([saved isEqualToString:@"ar"] || [saved isEqualToString:@"en"]) return saved;
    NSString *preferred = NSLocale.preferredLanguages.firstObject.lowercaseString;
    return [preferred hasPrefix:@"ar"] ? @"ar" : @"en";
}

BOOL IPArabicEnabled(void) { return [IPSelectedLanguageCode() isEqualToString:@"ar"]; }

NSString *IPLanguageDisplayName(NSString *code)
{
    if ([code isEqualToString:@"ar"]) return @"العربية";
    if ([code isEqualToString:@"en"]) return @"English";
    return IPArabicEnabled() ? @"لغة الجهاز" : @"System Language";
}

static NSBundle *IPArabicBundle(void)
{
    static NSBundle *bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [NSBundle.mainBundle pathForResource:@"ar" ofType:@"lproj"];
        bundle = path.length ? [NSBundle bundleWithPath:path] : nil;
    });
    return bundle;
}

static NSString *IPLocalizedDynamicString(NSString *source)
{
    NSRegularExpression *apps = [NSRegularExpression regularExpressionWithPattern:@"^([0-9٠-٩]+) apps and extensions$" options:0 error:nil];
    NSTextCheckingResult *match = [apps firstMatchInString:source options:0 range:NSMakeRange(0, source.length)];
    if (match.numberOfRanges == 2)
        return [NSString stringWithFormat:@"%@ من التطبيقات والملحقات", [source substringWithRange:[match rangeAtIndex:1]]];
    if ([source hasPrefix:@"Measuring extensions "]) return [source stringByReplacingOccurrencesOfString:@"Measuring extensions " withString:@"جارٍ قياس الملحقات "];
    if ([source hasPrefix:@"Measuring "]) return [source stringByReplacingOccurrencesOfString:@"Measuring " withString:@"جارٍ القياس: "];
    if ([source hasPrefix:@"Scanning "]) return [source stringByReplacingOccurrencesOfString:@"Scanning " withString:@"جارٍ الفحص: "];
    if ([source hasPrefix:@"Item "]) return [source stringByReplacingOccurrencesOfString:@"Item " withString:@"العنصر "];
    if ([source hasSuffix:@" of app data"]) return [source stringByReplacingOccurrencesOfString:@" of app data" withString:@" من بيانات التطبيقات"];
    return source;
}

NSString *IPLocalizedString(NSString *source)
{
    if (!source.length || !IPArabicEnabled()) return source;
    NSString *localized = [IPArabicBundle() localizedStringForKey:source value:source table:nil];
    return [localized isEqualToString:source] ? IPLocalizedDynamicString(source) : localized;
}

static void IPSwizzle(Class cls, SEL original, SEL replacement)
{
    Method a = class_getInstanceMethod(cls, original), b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

@interface UILabel (IPLocalization)
@end
@implementation UILabel (IPLocalization)
- (void)ip_setText:(NSString *)text
{
    NSString *localized = IPLocalizedString(text);
    BOOL technical = [localized hasPrefix:@"/"] || [localized containsString:@"://"] ||
        [localized containsString:@"com."] || [localized containsString:@"group."];
    self.semanticContentAttribute = technical ? UISemanticContentAttributeForceLeftToRight
                                              : UISemanticContentAttributeUnspecified;
    if (technical) self.textAlignment = NSTextAlignmentLeft;
    [self ip_setText:localized];
}
@end

@interface UITextField (IPLocalization)
@end
@implementation UITextField (IPLocalization)
- (void)ip_setPlaceholder:(NSString *)text { [self ip_setPlaceholder:IPLocalizedString(text)]; }
@end

@interface UISearchBar (IPLocalization)
@end
@implementation UISearchBar (IPLocalization)
- (void)ip_setPlaceholder:(NSString *)text { [self ip_setPlaceholder:IPLocalizedString(text)]; }
@end

@interface UIViewController (IPLocalization)
@end
@implementation UIViewController (IPLocalization)
- (void)ip_setTitle:(NSString *)title { [self ip_setTitle:IPLocalizedString(title)]; }
@end

@interface UINavigationItem (IPLocalization)
@end
@implementation UINavigationItem (IPLocalization)
- (void)ip_setTitle:(NSString *)title { [self ip_setTitle:IPLocalizedString(title)]; }
@end

@interface UIBarButtonItem (IPLocalization)
@end
@implementation UIBarButtonItem (IPLocalization)
- (void)ip_setTitle:(NSString *)title { [self ip_setTitle:IPLocalizedString(title)]; }
@end

@interface UIButton (IPLocalization)
@end
@implementation UIButton (IPLocalization)
- (void)ip_setTitle:(NSString *)title forState:(UIControlState)state
{
    [self ip_setTitle:IPLocalizedString(title) forState:state];
}
@end

void IPInstallLocalization(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        IPSwizzle(UILabel.class, @selector(setText:), @selector(ip_setText:));
        IPSwizzle(UITextField.class, @selector(setPlaceholder:), @selector(ip_setPlaceholder:));
        IPSwizzle(UISearchBar.class, @selector(setPlaceholder:), @selector(ip_setPlaceholder:));
        IPSwizzle(UIViewController.class, @selector(setTitle:), @selector(ip_setTitle:));
        IPSwizzle(UINavigationItem.class, @selector(setTitle:), @selector(ip_setTitle:));
        IPSwizzle(UIBarButtonItem.class, @selector(setTitle:), @selector(ip_setTitle:));
        IPSwizzle(UIButton.class, @selector(setTitle:forState:), @selector(ip_setTitle:forState:));
    });
}

void IPApplyLanguageDirection(UIWindow *window)
{
    UISemanticContentAttribute direction = IPArabicEnabled()
        ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
    // UIAppearance retains values for controls that UIKit owns in separate
    // windows (notably UIMenu). Changing it at runtime can therefore mirror a
    // menu twice or leave the old direction active until relaunch. Direction
    // belongs to the app window; every newly rebuilt screen inherits it.
    window.semanticContentAttribute = direction;
    window.rootViewController.view.semanticContentAttribute = direction;
}
