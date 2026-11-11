#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const IPLanguageDefaultsKey = @"IPLanguage";
static NSString *const IPLanguageDidChangeNotification = @"IPLanguageDidChangeNotification";

NSString *IPSelectedLanguageCode(void);
BOOL IPArabicEnabled(void);
NSString *IPLocalizedString(NSString *source);
NSString *IPLanguageDisplayName(NSString *code);
void IPInstallLocalization(void);
void IPApplyLanguageDirection(UIWindow *_Nullable window);

NS_ASSUME_NONNULL_END
