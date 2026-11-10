//
//  main.m
//  WQ Files
//
//  Proof-of-concept file browser for iOS 27 that reaches other containers
//  through the worse_query sandbox escape by Taj C (forcequit),
//  https://github.com/forcequitOS/worse_query, GPL-3.0-or-later.
//  This app is GPL-3.0-or-later as well (see LICENSE).
//

#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import "WQAccess.h"
#import "WQLaunchServices.h"
#import "WQUI.h"
#import "IPTheme.h"
#import "WQSharing.h"
#import "WQDir.h"
#import "WQApps.h"
#import "WQCache.h"
#import "WQCore.h"
#import "WQPlistEditor.h"
#import "WQPlistEditorSupport.h"
#import "WQHexViewer.h"
#import "WQArchive.h"
#import "WQDatabase.h"

static BOOL wq_looks_like_uuid(NSString *name)
{
    return name.length == 36 && [[NSUUID alloc] initWithUUIDString:name] != nil;
}

static BOOL wq_regular_file_for_ui(NSString *path)
{
    struct stat st;
    if (!wq_stat(path, &st)) return NO;
    // Symbolic links are deliberately not followed: the file APIs use
    // O_NOFOLLOW and the UI must offer the same contract.
    return S_ISREG(st.st_mode);
}

static NSString *const WQStarredLocationsKey = @"WQStarredLocationsV1";
static NSString *const WQRecentFoldersKey = @"WQRecentFoldersV1";
static NSString *const WQRecentFilesKey = @"WQRecentFilesV1";
static NSString *const WQRecentsDidChangeNotification = @"WQRecentsDidChangeNotification";

static NSArray<NSDictionary<NSString *, NSString *> *> *wq_starred_locations(void)
{
    NSArray *saved = [NSUserDefaults.standardUserDefaults arrayForKey:WQStarredLocationsKey];
    NSMutableArray *valid = [NSMutableArray new];
    for (id value in saved) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSString *path = value[@"path"], *name = value[@"name"];
        if (![path isKindOfClass:NSString.class] || ![path hasPrefix:@"/"]) continue;
        [valid addObject:@{@"path": path.stringByStandardizingPath,
                           @"name": [name isKindOfClass:NSString.class] && name.length ? name : path.lastPathComponent}];
    }
    return valid;
}

static BOOL wq_location_is_starred(NSString *path)
{
    NSString *key = path.stringByStandardizingPath;
    for (NSDictionary *item in wq_starred_locations())
        if ([item[@"path"] isEqualToString:key]) return YES;
    return NO;
}

static void wq_set_location_starred(NSString *path, NSString *name, BOOL starred)
{
    NSString *key = path.stringByStandardizingPath;
    NSMutableArray *items = wq_starred_locations().mutableCopy;
    NSIndexSet *matching = [items indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger __unused idx, BOOL *__unused stop) {
        return [item[@"path"] isEqualToString:key];
    }];
    [items removeObjectsAtIndexes:matching];
    if (starred) [items insertObject:@{@"path": key, @"name": name.length ? name : (key.lastPathComponent ?: key)} atIndex:0];
    [NSUserDefaults.standardUserDefaults setObject:items forKey:WQStarredLocationsKey];
}

static NSArray<NSDictionary<NSString *, NSString *> *> *wq_recent_items(BOOL folders)
{
    NSArray *saved = [NSUserDefaults.standardUserDefaults arrayForKey:folders ? WQRecentFoldersKey : WQRecentFilesKey];
    NSMutableArray *valid = [NSMutableArray new];
    for (id value in saved) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSString *path = value[@"path"], *name = value[@"name"];
        if (![path isKindOfClass:NSString.class] || ![path hasPrefix:@"/"]) continue;
        [valid addObject:@{@"path": path.stringByStandardizingPath,
                           @"name": [name isKindOfClass:NSString.class] && name.length ? name : path.lastPathComponent}];
    }
    return valid;
}

static void wq_record_recent(NSString *path, NSString *name, BOOL folder)
{
    if (!path.length || ![path hasPrefix:@"/"]) return;
    NSString *key = path.stringByStandardizingPath;
    NSMutableArray *items = wq_recent_items(folder).mutableCopy;
    NSIndexSet *old = [items indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger __unused idx, BOOL *__unused stop) {
        return [item[@"path"] isEqualToString:key];
    }];
    [items removeObjectsAtIndexes:old];
    [items insertObject:@{@"path": key, @"name": name.length ? name : (key.lastPathComponent ?: key)} atIndex:0];
    if (items.count > 24) [items removeObjectsInRange:NSMakeRange(24, items.count - 24)];
    [NSUserDefaults.standardUserDefaults setObject:items forKey:folder ? WQRecentFoldersKey : WQRecentFilesKey];
    [NSNotificationCenter.defaultCenter postNotificationName:WQRecentsDidChangeNotification object:nil];
}

static void wq_remove_recent(NSString *path, BOOL folder)
{
    NSMutableArray *items = wq_recent_items(folder).mutableCopy;
    NSIndexSet *matches = [items indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger __unused idx, BOOL *__unused stop) {
        return [item[@"path"] isEqualToString:path];
    }];
    [items removeObjectsAtIndexes:matches];
    [NSUserDefaults.standardUserDefaults setObject:items forKey:folder ? WQRecentFoldersKey : WQRecentFilesKey];
    [NSNotificationCenter.defaultCenter postNotificationName:WQRecentsDidChangeNotification object:nil];
}

static void wq_clear_recents(void)
{
    [NSUserDefaults.standardUserDefaults removeObjectForKey:WQRecentFoldersKey];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:WQRecentFilesKey];
    [NSNotificationCenter.defaultCenter postNotificationName:WQRecentsDidChangeNotification object:nil];
}

#pragma mark - Item

@interface WQItem : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *bundleID;  // for the app icon
@property (nonatomic) BOOL isDir;
@property (nonatomic) BOOL isLink;
@property (nonatomic) BOOL isRegular;
@property (nonatomic) unsigned long long size;
@property (nonatomic) mode_t mode;
@property (nonatomic) uid_t uid;
@property (nonatomic, strong) NSDate *modified;
@property (nonatomic, strong) UIImage *thumbnail;
@property (nonatomic) BOOL thumbnailRequested;
@end

@implementation WQItem
@end

#pragma mark - File viewer

typedef NS_ENUM(NSInteger, WQOpenMode) {
    WQOpenAuto, WQOpenPlist, WQOpenText, WQOpenImage, WQOpenHex, WQOpenMedia, WQOpenArchive, WQOpenDatabase
};
// Opens a file in the fitting viewer (Auto: chosen from its first bytes).
static void wq_open_file(UINavigationController *nav, NSString *path, BOOL readOnly, WQOpenMode mode);

typedef NS_ENUM(NSInteger, WQViewKind) { WQViewText, WQViewPlist, WQViewImage, WQViewHex };

static const NSUInteger kViewLimit = 4 * 1024 * 1024;
static const NSUInteger kHexLimit = 64 * 1024;

// Parsing and image creation happen on the I/O queue; the main thread only
// installs the prepared display.
@interface WQFileDisplay : NSObject
@property (nonatomic) BOOL truncated;
@property (nonatomic, strong) NSString *plistText;
@property (nonatomic) NSPropertyListFormat plistFormat;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) NSString *text;
@property (nonatomic, strong) NSString *hexText;
@end
@implementation WQFileDisplay
@end

static NSString *wq_file_hex_dump(NSData *data, BOOL truncated)
{
    NSUInteger len = MIN(data.length, kHexLimit);
    const uint8_t *b = data.bytes;
    NSMutableString *out = [NSMutableString stringWithCapacity:len * 4];
    for (NSUInteger off = 0; off < len; off += 16) {
        [out appendFormat:@"%08lx  ", (unsigned long)off];
        NSMutableString *ascii = [NSMutableString new];
        for (NSUInteger i = 0; i < 16; i++) {
            if (off + i < len) {
                uint8_t c = b[off + i];
                [out appendFormat:@"%02x ", c];
                [ascii appendFormat:@"%c", (c >= 0x20 && c < 0x7f) ? c : '.'];
            } else {
                [out appendString:@"   "];
            }
        }
        [out appendFormat:@" %@\n", ascii];
    }
    if (data.length > len || truncated) [out appendString:@"\n… (only the beginning is shown)\n"];
    return out;
}

@interface WQFileViewController : UIViewController <UITextViewDelegate, WQUnsavedEditing>
@property (nonatomic) BOOL readOnly;
- (instancetype)initWithPath:(NSString *)path;
@end

@implementation WQFileViewController {
    NSString *_path;
    UITextView *_textView;
    UIImageView *_imageView;
    UIBarButtonItem *_editButton;
    WQViewKind _kind;
    NSPropertyListFormat _plistFormat;
    BOOL _truncated;
    WQEditState *_editState;
    NSDictionary<NSString *, NSNumber *> *_version;
}


- (instancetype)initWithPath:(NSString *)path
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _path = [path copy];
        _editState = [WQEditState new];
        self.title = path.lastPathComponent;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = IPBackground();
    _textView = [UITextView new];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    _textView.editable = NO;
    _textView.autocorrectionType = UITextAutocorrectionTypeNo;
    _textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _textView.smartQuotesType = UITextSmartQuotesTypeNo;
    _textView.smartDashesType = UITextSmartDashesTypeNo;
    _textView.alwaysBounceVertical = YES;
    _textView.delegate = self;
    _textView.backgroundColor = IPBackground();
    _textView.textColor = IPPrimaryText();
    [self.view addSubview:_textView];
    __weak typeof(self) weakSelf = self;
    self.navigationItem.backAction = [UIAction actionWithHandler:^(UIAction *__unused a) { [weakSelf leave]; }];
    _imageView = [UIImageView new];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.hidden = YES;
    [self.view addSubview:_imageView];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    for (UIView *v in @[_textView, _imageView]) {
        [NSLayoutConstraint activateConstraints:@[
            [v.topAnchor constraintEqualToAnchor:g.topAnchor],
            [v.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
            [v.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [v.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        ]];
    }
    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                           target:self action:@selector(share:)];
    UIMenu *openAs = [UIMenu menuWithTitle:@"Open As" children:@[
        [UIAction actionWithTitle:@"Plist Editor" image:[UIImage systemImageNamed:@"list.bullet.indent"] identifier:nil
                          handler:^(UIAction *__unused a) { [weakSelf reopenAs:WQOpenPlist]; }],
        [UIAction actionWithTitle:@"Text / Image" image:[UIImage systemImageNamed:@"doc.plaintext"] identifier:nil
                          handler:^(UIAction *__unused a) { [weakSelf reopenAs:WQOpenText]; }],
        [UIAction actionWithTitle:@"Image Viewer" image:[UIImage systemImageNamed:@"photo"] identifier:nil
                          handler:^(UIAction *__unused a) { [weakSelf reopenAs:WQOpenImage]; }],
        [UIAction actionWithTitle:@"Hex Viewer" image:[UIImage systemImageNamed:@"number"] identifier:nil
                          handler:^(UIAction *__unused a) { [weakSelf reopenAs:WQOpenHex]; }],
        [UIAction actionWithTitle:@"Media Player" image:[UIImage systemImageNamed:@"play.rectangle"] identifier:nil
                          handler:^(UIAction *__unused a) { [weakSelf reopenAs:WQOpenMedia]; }],
        [UIAction actionWithTitle:@"Archive" image:[UIImage systemImageNamed:@"archivebox"] identifier:nil
                          handler:^(UIAction *__unused a) { [weakSelf reopenAs:WQOpenArchive]; }],
        [UIAction actionWithTitle:@"SQLite Database" image:[UIImage systemImageNamed:@"cylinder"] identifier:nil
                          handler:^(UIAction *__unused a) { [weakSelf reopenAs:WQOpenDatabase]; }],
    ]];
    UIBarButtonItem *more = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:openAs];
    self.navigationItem.rightBarButtonItems = @[share, more];
    _textView.text = @"Loading…";
    [self load];
}

- (void)load
{
    NSString *path = _path;
    dispatch_async(wq_io(), ^{
        NSString *error = nil;
        struct stat st;
        BOOL exists = wq_stat(path, &st);
        NSDictionary *__unused before = wq_file_version(path);
        NSData *data = wq_read(path, kViewLimit + 1, &error);
        NSDictionary *version = wq_file_version(path);
        if (data && (!before || !version || ![before isEqualToDictionary:version])) {
            data = nil;
            error = version ? @"The file changed while it was being read. Open it again."
                            : @"Could not establish a stable file version. Open it again.";
        }
        WQFileDisplay *display = nil;
        if (data) {
            display = [WQFileDisplay new];
            display.truncated = data.length > kViewLimit;
            NSData *view = display.truncated ? [data subdataWithRange:NSMakeRange(0, kViewLimit)] : data;
            if (!display.truncated) {
                NSPropertyListFormat format = 0;
                id plist = [NSPropertyListSerialization propertyListWithData:view options:0 format:&format error:nil];
                if (plist) {
                    NSData *xml = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                            format:NSPropertyListXMLFormat_v1_0
                                                                           options:0 error:nil];
                    NSString *text = xml ? [[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding] : nil;
                    if (text) {
                        display.plistFormat = format;
                        display.plistText = text;
                    }
                }
            }
            if (!display.plistText) {
                display.image = [UIImage imageWithData:view];
                if (!display.image) {
                    NSString *text = [[NSString alloc] initWithData:view encoding:NSUTF8StringEncoding];
                    if (text && ![text containsString:@"\0"]) display.text = text;
                    else display.hexText = wq_file_hex_dump(view, display.truncated);
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_version = version;
            if (!display) {
                NSString *hint = wq_permission_hint(path, NO);
                self->_textView.text = [NSString stringWithFormat:@"Cannot read this file.\n\n%@", hint ?: error];
                return;
            }
            NSString *info = exists
                ? [NSString stringWithFormat:@"%@ · mode %o · uid %u", wq_size_text((unsigned long long)st.st_size),
                   st.st_mode & 07777, st.st_uid]
                : @"";
            self.navigationItem.prompt = info.length ? info : nil;
            if (wq_permission_hint(path, YES)) self->_readOnly = YES;   // only the owner may write it
            [self showDisplay:display];
        });
    });
}

- (void)showDisplay:(WQFileDisplay *)display
{
    _truncated = display.truncated;
    if (display.plistText) {
        _kind = WQViewPlist;
        _plistFormat = display.plistFormat;
        _textView.text = display.plistText;
        if (!WQPlistFormatIsWritable(display.plistFormat)) {
            _readOnly = YES;
            NSString *prompt = self.navigationItem.prompt;
            NSString *reason = [NSString stringWithFormat:@"%@ · read only", WQPlistFormatName(display.plistFormat)];
            self.navigationItem.prompt = prompt.length ? [prompt stringByAppendingFormat:@" · %@", reason] : reason;
        }
        if (!_readOnly) [self enableEditing];
        return;
    }
    if (display.image) {
        _kind = WQViewImage;
        _imageView.image = display.image;
        _imageView.hidden = NO;
        _textView.hidden = YES;
        return;
    }
    if (display.text) {
        _kind = WQViewText;
        _textView.text = display.text;
        if (!_truncated && !_readOnly) [self enableEditing];
        return;
    }
    _kind = WQViewHex;
    _textView.text = display.hexText ?: @"";
}

- (void)updateEditButton
{
    _editButton.title = _textView.editable ? @"Save" : @"Edit";
    _editButton.style = _textView.editable ? wq_primary_button_style() : UIBarButtonItemStylePlain;
    _editButton.enabled = !_editState.saving;
}

- (void)enableEditing
{
    if (_editButton) return;
    _editButton = [[UIBarButtonItem alloc] initWithTitle:@"Edit" style:UIBarButtonItemStylePlain
                                                  target:self action:@selector(toggleEdit:)];
    NSArray *items = self.navigationItem.rightBarButtonItems;
    self.navigationItem.rightBarButtonItems = [items arrayByAddingObject:_editButton];
}

- (void)textViewDidChange:(UITextView *)textView
{
    if (_editState.saving) return;
    [_editState noteChange];
}

- (BOOL)blockWhileSaving
{
    if (!_editState.saving) return NO;
    wq_alert(self, @"Save in progress", @"Wait for the current save to finish before leaving or making more changes.");
    return YES;
}

- (BOOL)wq_needsLeaveConfirmation
{
    return _editState.dirty || _editState.saving;
}

- (void)confirmLeaveThen:(void (^)(void))proceed
{
    if ([self blockWhileSaving]) return;
    if (!_editState.dirty) { proceed(); return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Discard changes?"
        message:@"Your text changes have not been saved." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Keep Editing" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Discard" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *__unused a) {
        [self->_editState discard];
        self->_textView.editable = NO;
        [self->_textView resignFirstResponder];
        [self updateEditButton];
        proceed();
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)leave
{
    [self confirmLeaveThen:^{ [self.navigationController popViewControllerAnimated:YES]; }];
}

- (void)toggleEdit:(UIBarButtonItem *)sender
{
    if ([self blockWhileSaving]) return;
    if (!_textView.editable) {
        _textView.editable = YES;
        [self updateEditButton];
        [_textView becomeFirstResponder];
        return;
    }
    if (!_editState.dirty) {
        _textView.editable = NO;
        [_textView resignFirstResponder];
        [self updateEditButton];
        return;
    }
    if (!_version) {
        wq_alert(self, @"Cannot save", @"The file has no verified version snapshot. Reopen it before saving.");
        return;
    }
    NSData *newData = nil;
    if (_kind == WQViewPlist) {
        NSData *xml = [_textView.text dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        id plist = xml ? [NSPropertyListSerialization propertyListWithData:xml options:0 format:NULL error:&error] : nil;
        if (!plist) {
            wq_alert(self, @"Not a valid property list", error.localizedDescription ?: @"Check the XML.");
            return;
        }
        newData = [NSPropertyListSerialization dataWithPropertyList:plist format:_plistFormat options:0 error:&error];
        if (!newData) {
            wq_alert(self, @"Cannot encode", error.localizedDescription ?: @"");
            return;
        }
    } else {
        newData = [_textView.text dataUsingEncoding:NSUTF8StringEncoding];
    }
    if (!newData) {
        wq_alert(self, @"Cannot encode", @"The text could not be encoded as UTF-8.");
        return;
    }
    NSString *message = [NSString stringWithFormat:@"%@ will be overwritten in place. The current version is backed up to Backups first.", _path];
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Save changes?" message:message
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *__unused a) {
        NSUInteger savedRevision = [self->_editState beginSave];
        self->_textView.editable = NO;
        [self->_textView resignFirstResponder];
        [self updateEditButton];
        NSString *path = self->_path;
        NSDictionary *expectedVersion = [self->_version copy];
        dispatch_async(wq_io(), ^{
            NSString *error = nil;
            NSDictionary *newVersion = nil;
            BOOL ok = wq_write_if_unchanged_get_version(path, newData, expectedVersion, &newVersion, &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_editState finishSave:ok revision:savedRevision];
                if (ok) self->_version = newVersion;
                self->_textView.editable = self->_editState.dirty;
                [self updateEditButton];
                if (!ok) wq_alert(self, @"Save failed", error ?: wq_permission_hint(path, YES) ?: @"Unknown error");
            });
        });
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)share:(UIBarButtonItem *)sender
{
    wq_share(self, _path, nil);
}

- (void)reopenAs:(WQOpenMode)mode
{
    [self confirmLeaveThen:^{
        UINavigationController *nav = self.navigationController;
        NSString *path = self->_path;
        BOOL readOnly = self->_readOnly;
        [nav popViewControllerAnimated:NO];
        wq_open_file(nav, path, readOnly, mode);
    }];
}

@end

#pragma mark - Media and archives

@interface WQImageViewController : UIViewController <UIScrollViewDelegate, UIGestureRecognizerDelegate>
- (instancetype)initWithPath:(NSString *)path;
@end

@implementation WQImageViewController {
    NSString *_path;
    UIScrollView *_scrollView;
    UIImageView *_imageView;
    UIButton *_shareButton;
    BOOL _controlsHidden;
}

- (instancetype)initWithPath:(NSString *)path
{
    if ((self = [super init])) { _path = path.copy; self.modalPresentationStyle = UIModalPresentationFullScreen; }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    _scrollView = [UIScrollView new];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.delegate = self;
    _scrollView.minimumZoomScale = 1;
    _scrollView.maximumZoomScale = 6;
    _scrollView.backgroundColor = UIColor.blackColor;
    [self.view addSubview:_scrollView];
    _imageView = [UIImageView new];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    [_scrollView addSubview:_imageView];
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_imageView.leadingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.leadingAnchor],
        [_imageView.trailingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.trailingAnchor],
        [_imageView.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor],
        [_imageView.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor],
        [_imageView.widthAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.widthAnchor],
        [_imageView.heightAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.heightAnchor]
    ]];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleControls)];
    [_scrollView addGestureRecognizer:tap];
    UIPanGestureRecognizer *dismiss = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleImageDismiss:)];
    dismiss.delegate = self;
    dismiss.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:dismiss];
    UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
    configuration.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
    configuration.baseForegroundColor = UIColor.whiteColor;
    configuration.baseBackgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.55];
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    __weak typeof(self) weakSelf = self;
    _shareButton = [UIButton buttonWithConfiguration:configuration primaryAction:
        [UIAction actionWithHandler:^(UIAction *__unused action) {
            WQImageViewController *strongSelf = weakSelf;
            if (strongSelf) wq_share(strongSelf, strongSelf->_path, nil);
        }]];
    _shareButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_shareButton];
    [NSLayoutConstraint activateConstraints:@[
        [_shareButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [_shareButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [_shareButton.widthAnchor constraintEqualToConstant:44], [_shareButton.heightAnchor constraintEqualToConstant:44]
    ]];
    NSString *path = _path;
    dispatch_async(wq_io(), ^{
        NSString *error = nil;
        NSData *data = wq_read(path, 64 * 1024 * 1024, &error);
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_imageView.image = image;
            if (!image) wq_alert(self, @"Cannot open image", error ?: @"The image could not be decoded.");
        });
    });
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return _imageView; }
- (BOOL)prefersStatusBarHidden { return _controlsHidden; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)toggleControls
{
    _controlsHidden = !_controlsHidden;
    [self setNeedsStatusBarAppearanceUpdate];
    [UIView animateWithDuration:0.2 animations:^{ self->_shareButton.alpha = self->_controlsHidden ? 0 : 1; }];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if (![gestureRecognizer isKindOfClass:UIPanGestureRecognizer.class] || _scrollView.zoomScale > 1.01) return NO;
    CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.view];
    return velocity.y > 0 && velocity.y > fabs(velocity.x) * 1.2;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *__unused)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *__unused)other { return YES; }

- (void)handleImageDismiss:(UIPanGestureRecognizer *)pan
{
    CGFloat y = MAX(0, [pan translationInView:self.view].y);
    if (pan.state == UIGestureRecognizerStateChanged) {
        self.view.transform = CGAffineTransformMakeTranslation(0, y);
        self.view.alpha = 1 - MIN(0.4, y / MAX(1, self.view.bounds.size.height) * 0.4);
        return;
    }
    if (pan.state != UIGestureRecognizerStateEnded && pan.state != UIGestureRecognizerStateCancelled) return;
    CGFloat velocity = [pan velocityInView:self.view].y;
    if (pan.state == UIGestureRecognizerStateEnded && (y > 120 || velocity > 900)) {
        [UIView animateWithDuration:0.2 animations:^{
            self.view.transform = CGAffineTransformMakeTranslation(0, self.view.bounds.size.height);
            self.view.alpha = 0;
        } completion:^(__unused BOOL finished) { [self dismissViewControllerAnimated:NO completion:nil]; }];
    } else {
        [UIView animateWithDuration:0.24 animations:^{ self.view.transform = CGAffineTransformIdentity; self.view.alpha = 1; }];
    }
}
@end

@interface WQMediaViewController : UIViewController <UIGestureRecognizerDelegate>
- (instancetype)initWithPath:(NSString *)path;
@end

@implementation WQMediaViewController {
    NSString *_path;
    AVPlayerViewController *_playerController;
}

- (instancetype)initWithPath:(NSString *)path
{
    if ((self = [super init])) { _path = path.copy; self.title = path.lastPathComponent; }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    (void)wq_grant(_path.stringByDeletingLastPathComponent);
    (void)wq_grant(_path);
    self.modalPresentationStyle = UIModalPresentationFullScreen;

    _playerController = [AVPlayerViewController new];
    _playerController.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:_path]];
    _playerController.showsPlaybackControls = YES;
    [self addChildViewController:_playerController];
    _playerController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_playerController.view];
    [NSLayoutConstraint activateConstraints:@[
        [_playerController.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_playerController.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_playerController.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_playerController.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [_playerController didMoveToParentViewController:self];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(handleDismissPan:)];
    pan.delegate = self;
    pan.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:pan];
    UIButton *share = [self overlayButtonWithSymbol:@"square.and.arrow.up" action:@selector(shareMedia)];
    [self.view addSubview:share];
    [NSLayoutConstraint activateConstraints:@[
        [share.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [share.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12]
    ]];
    NSSet *audio = [NSSet setWithArray:@[@"mp3", @"m4a", @"aac", @"wav", @"caf", @"aiff"]];
    if ([audio containsObject:_path.pathExtension.lowercaseString]) {
        (void)[AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:nil];
        UIImageView *art = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"waveform.circle.fill"]];
        art.tintColor = UIColor.systemCyanColor;
        art.contentMode = UIViewContentModeScaleAspectFit;
        art.translatesAutoresizingMaskIntoConstraints = NO;
        [_playerController.contentOverlayView addSubview:art];
        UILabel *name = [UILabel new];
        name.text = _path.lastPathComponent;
        name.textColor = UIColor.whiteColor;
        name.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        name.textAlignment = NSTextAlignmentCenter;
        name.lineBreakMode = NSLineBreakByTruncatingMiddle;
        name.translatesAutoresizingMaskIntoConstraints = NO;
        [_playerController.contentOverlayView addSubview:name];
        [NSLayoutConstraint activateConstraints:@[
            [art.centerXAnchor constraintEqualToAnchor:_playerController.contentOverlayView.centerXAnchor],
            [art.centerYAnchor constraintEqualToAnchor:_playerController.contentOverlayView.centerYAnchor constant:-44],
            [art.widthAnchor constraintEqualToConstant:112], [art.heightAnchor constraintEqualToConstant:112],
            [name.topAnchor constraintEqualToAnchor:art.bottomAnchor constant:18],
            [name.leadingAnchor constraintEqualToAnchor:_playerController.contentOverlayView.leadingAnchor constant:28],
            [name.trailingAnchor constraintEqualToAnchor:_playerController.contentOverlayView.trailingAnchor constant:-28]
        ]];
    }
}

- (UIButton *)overlayButtonWithSymbol:(NSString *)symbol action:(SEL)action
{
    UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
    configuration.image = [UIImage systemImageNamed:symbol];
    configuration.baseForegroundColor = UIColor.whiteColor;
    configuration.baseBackgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.55];
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:44], [button.heightAnchor constraintEqualToConstant:44]
    ]];
    return button;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
    CGPoint velocity = [pan velocityInView:self.view];
    return velocity.y > 0 && velocity.y > fabs(velocity.x) * 1.2;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *__unused)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *__unused)other
{
    return YES;
}

- (void)handleDismissPan:(UIPanGestureRecognizer *)pan
{
    CGFloat y = MAX(0, [pan translationInView:self.view].y);
    CGFloat progress = MIN(1, y / MAX(1, self.view.bounds.size.height));
    if (pan.state == UIGestureRecognizerStateChanged) {
        self.view.transform = CGAffineTransformMakeTranslation(0, y);
        self.view.alpha = 1 - progress * 0.35;
        return;
    }
    if (pan.state != UIGestureRecognizerStateEnded && pan.state != UIGestureRecognizerStateCancelled) return;
    CGFloat velocity = [pan velocityInView:self.view].y;
    if (pan.state == UIGestureRecognizerStateEnded && (y > 120 || velocity > 900)) {
        [_playerController.player pause];
        [UIView animateWithDuration:0.22 animations:^{
            self.view.transform = CGAffineTransformMakeTranslation(0, self.view.bounds.size.height);
            self.view.alpha = 0;
        } completion:^(__unused BOOL finished) {
            [self dismissViewControllerAnimated:NO completion:nil];
        }];
    } else {
        [UIView animateWithDuration:0.25 delay:0
             usingSpringWithDamping:0.82 initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut
                         animations:^{ self.view.transform = CGAffineTransformIdentity; self.view.alpha = 1; }
                         completion:nil];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [_playerController.player play];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [_playerController.player pause];
}

- (void)shareMedia { wq_share(self, _path, nil); }

@end

@interface WQArchiveViewController : UITableViewController
- (instancetype)initWithPath:(NSString *)path;
@end

@implementation WQArchiveViewController {
    NSString *_path;
    NSArray<NSDictionary<NSString *, id> *> *_entries;
    NSString *_error;
    BOOL _loading;
}

- (instancetype)initWithPath:(NSString *)path
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { _path = path.copy; self.title = path.lastPathComponent; }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.backgroundColor = IPBackground();
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Extract"
        style:UIBarButtonItemStyleProminent target:self action:@selector(extractArchive)];
    _loading = YES;
    NSString *path = _path;
    dispatch_async(wq_io(), ^{
        NSString *error = nil;
        NSArray *entries = WQArchiveList(path, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_loading = NO; self->_entries = entries; self->_error = error;
            self.navigationItem.rightBarButtonItem.enabled = entries != nil;
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return MAX((NSInteger)1, (NSInteger)_entries.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"archive"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"archive"];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    if (_loading || !_entries.count) {
        content.text = _loading ? @"Reading archive…" : (_error ? @"Cannot open archive" : @"Archive is empty");
        content.secondaryText = _error;
        content.image = [UIImage systemImageNamed:_error ? @"exclamationmark.triangle" : @"archivebox"];
    } else {
        NSDictionary *entry = _entries[(NSUInteger)indexPath.row];
        BOOL directory = [entry[@"directory"] boolValue];
        content.text = entry[@"name"];
        content.secondaryText = directory ? @"Folder" : wq_size_text([entry[@"size"] unsignedLongLongValue]);
        content.image = [UIImage systemImageNamed:directory ? @"folder.fill" : @"doc"];
    }
    content.textProperties.color = IPPrimaryText();
    content.secondaryTextProperties.color = IPSecondaryText();
    content.imageProperties.tintColor = IPAccent();
    content.secondaryTextProperties.numberOfLines = 0;
    cell.contentConfiguration = content;
    IPStyleCell(cell);
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)extractArchive
{
    NSString *base = _path.lastPathComponent.stringByDeletingPathExtension;
    NSString *destination = [_path.stringByDeletingLastPathComponent stringByAppendingPathComponent:
        [base stringByAppendingString:@" Extracted"]];
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Extract archive?"
        message:[NSString stringWithFormat:@"Files will be extracted safely into %@. Links, traversal paths and oversized entries are refused.", destination.lastPathComponent]
        preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Extract" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused action) {
        self.navigationItem.rightBarButtonItem.enabled = NO;
        dispatch_async(wq_io(), ^{
            NSString *error = nil;
            BOOL ok = WQArchiveExtract(self->_path, destination, &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.navigationItem.rightBarButtonItem.enabled = YES;
                if (!ok) { wq_alert(self, @"Extraction failed", error ?: @"Unknown archive error"); return; }
                [self.navigationController pushViewController:[[WQDirViewController alloc] initWithPath:destination title:destination.lastPathComponent] animated:YES];
            });
        });
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}
@end

#pragma mark - Choosing a viewer

static WQOpenMode wq_sniff(NSData *head, NSString *path)
{
    const uint8_t *b = head.bytes;
    NSUInteger n = head.length;
    NSString *extension = path.pathExtension.lowercaseString;
    NSSet *media = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v", @"mp3", @"m4a", @"aac", @"wav", @"caf", @"aiff"]];
    NSSet *images = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"gif", @"heic", @"heif", @"tif", @"tiff", @"bmp", @"webp"]];
    NSSet *archives = [NSSet setWithArray:@[@"zip", @"tar", @"gz", @"tgz", @"bz2", @"xz", @"7z"]];
    NSSet *databases = [NSSet setWithArray:@[@"sqlite", @"sqlite3", @"db", @"db3"]];
    NSSet *databaseSidecars = [NSSet setWithArray:@[@"sqlite-wal", @"sqlite-shm", @"db-wal", @"db-shm"]];
    if ([media containsObject:extension]) return WQOpenMedia;
    if ([images containsObject:extension]) return WQOpenImage;
    if ([archives containsObject:extension]) return WQOpenArchive;
    if ([databases containsObject:extension]) return WQOpenDatabase;
    if ([databaseSidecars containsObject:extension] || [path.lowercaseString hasSuffix:@"-wal"] || [path.lowercaseString hasSuffix:@"-shm"])
        return WQOpenDatabase;
    if (n >= 16 && memcmp(b, "SQLite format 3\0", 16) == 0) return WQOpenDatabase;
    if (n >= 4 && b[0] == 'P' && b[1] == 'K' && (b[2] == 3 || b[2] == 5 || b[2] == 7)) return WQOpenArchive;
    if (n >= 7 && memcmp(b, "bplist0", 7) == 0) return WQOpenPlist;
    if (n >= 12 && memcmp(b + 4, "ftyp", 4) == 0) return WQOpenMedia;
    if ((n >= 8 && memcmp(b, "\x89PNG", 4) == 0) || (n >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) ||
        (n >= 4 && memcmp(b, "GIF8", 4) == 0))
        return WQOpenImage;
    if (n == 0) return WQOpenText;
    if (memchr(b, 0, n)) return WQOpenHex;
    NSString *text = nil;
    for (NSUInteger cut = 0; cut < 4 && !text && cut < n; cut++)   // the sample may end mid-character
        text = [[NSString alloc] initWithBytes:b length:n - cut encoding:NSUTF8StringEncoding];
    if (!text) return WQOpenHex;
    if ([text containsString:@"<plist"] || [text containsString:@"<!DOCTYPE plist"]) return WQOpenPlist;
    return WQOpenText;
}

static NSUInteger wq_open_generation;

static void wq_open_file(UINavigationController *nav, NSString *path, BOOL readOnly, WQOpenMode mode)
{
    if (!nav || !path.length) return;
    // All calls originate on the main thread. A newer explicit or automatic
    // open invalidates older sniff requests, and leaving the originating screen
    // also prevents a late push.
    NSUInteger request = ++wq_open_generation;
    UIViewController *origin = nav.topViewController;
    void (^push)(WQOpenMode) = ^(WQOpenMode m) {
        if (request != wq_open_generation || nav.topViewController != origin) return;
        UIViewController *vc;
        if (m == WQOpenPlist) {
            WQPlistEditorViewController *editor = [[WQPlistEditorViewController alloc] initWithPath:path readOnly:readOnly];
            __weak UINavigationController *weakNav = nav;
            editor.openAsText = ^{ wq_open_file(weakNav, path, readOnly, WQOpenText); };
            editor.openAsHex = ^{ wq_open_file(weakNav, path, readOnly, WQOpenHex); };
            vc = editor;
        } else if (m == WQOpenHex) {
            vc = [[WQHexViewController alloc] initWithPath:path readOnly:readOnly];
        } else if (m == WQOpenImage) {
            vc = [[WQImageViewController alloc] initWithPath:path];
            vc.modalPresentationStyle = UIModalPresentationFullScreen;
            [origin presentViewController:vc animated:YES completion:nil];
            return;
        } else if (m == WQOpenMedia) {
            vc = [[WQMediaViewController alloc] initWithPath:path];
            vc.modalPresentationStyle = UIModalPresentationFullScreen;
            [origin presentViewController:vc animated:YES completion:nil];
            return;
        } else if (m == WQOpenArchive) {
            vc = [[WQArchiveViewController alloc] initWithPath:path];
        } else if (m == WQOpenDatabase) {
            vc = [[WQDatabaseViewController alloc] initWithPath:path];
        } else {
            WQFileViewController *file = [[WQFileViewController alloc] initWithPath:path];
            file.readOnly = readOnly;
            vc = file;
        }
        [nav pushViewController:vc animated:YES];
    };
    if (!wq_regular_file_for_ui(path)) {
        UIViewController *host = nav.topViewController;
        struct stat st;
        BOOL link = wq_stat(path, &st) && S_ISLNK(st.st_mode);
        if (host) wq_alert(host, link ? @"Symbolic link" : @"Cannot open this item",
                           link ? @"WQ Files does not follow symbolic links for viewing, sharing or editing."
                                : @"Only regular files can be viewed.");
        return;
    }
    wq_record_recent(path, path.lastPathComponent, NO);
    if (mode != WQOpenAuto) { push(mode); return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *head = wq_permission_hint(path, NO) ? nil : wq_read_range(path, 0, 4096, NULL);
        WQOpenMode m = head ? wq_sniff(head, path) : WQOpenText;   // unreadable: the file viewer shows why
        dispatch_async(dispatch_get_main_queue(), ^{ push(m); });
    });
}

#pragma mark - Folder

static NSString *wq_folder_date_text(NSDate *date)
{
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.dateStyle = NSDateFormatterShortStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        formatter.locale = NSLocale.autoupdatingCurrentLocale;
    });
    return date ? [formatter stringFromDate:date] : @"";
}

static NSSet<NSString *> *wq_video_extensions(void)
{
    static NSSet *extensions; static dispatch_once_t once;
    dispatch_once(&once, ^{ extensions = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v", @"avi", @"mpeg", @"mpg"]]; });
    return extensions;
}

static NSSet<NSString *> *wq_image_extensions(void)
{
    static NSSet *extensions; static dispatch_once_t once;
    dispatch_once(&once, ^{ extensions = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"gif", @"heic", @"heif", @"tif", @"tiff", @"bmp", @"webp"]]; });
    return extensions;
}

static NSSet<NSString *> *wq_audio_extensions(void)
{
    static NSSet *extensions; static dispatch_once_t once;
    dispatch_once(&once, ^{ extensions = [NSSet setWithArray:@[@"mp3", @"m4a", @"aac", @"wav", @"caf", @"aiff"]]; });
    return extensions;
}

static NSString *wq_media_kind(NSString *path)
{
    NSString *extension = path.pathExtension.lowercaseString;
    if ([wq_video_extensions() containsObject:extension]) return @"Video";
    if ([wq_image_extensions() containsObject:extension]) return @"Photo";
    if ([wq_audio_extensions() containsObject:extension]) return @"Audio";
    return nil;
}

static NSString *wq_compact_file_name(WQItem *item, NSUInteger limit)
{
    NSString *name = item.label ?: item.name;
    if (item.isDir || item.label || name.length <= limit) return name;
    NSString *kind = wq_media_kind(item.path);
    if (kind) {
        NSString *stem = item.name.stringByDeletingPathExtension;
        NSArray *parts = [stem componentsSeparatedByCharactersInSet:
            [NSCharacterSet characterSetWithCharactersInString:@":_-"]];
        NSString *identifier = nil;
        NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
        for (NSString *part in parts.reverseObjectEnumerator) {
            if (part.length > 0 && part.length <= 7 && [part rangeOfCharacterFromSet:nonDigits].location == NSNotFound && part.integerValue > 0) {
                identifier = part; break;
            }
        }
        return identifier ? [NSString stringWithFormat:@"%@ %@", kind, identifier] : kind;
    }
    NSString *extension = item.name.pathExtension;
    NSString *stem = item.name.stringByDeletingPathExtension;
    NSUInteger room = limit - MIN(limit / 3, extension.length + 2);
    if (stem.length > room && room > 8)
        stem = [NSString stringWithFormat:@"%@…%@", [stem substringToIndex:room - 6], [stem substringFromIndex:stem.length - 5]];
    return extension.length ? [NSString stringWithFormat:@"%@.%@", stem, extension] : stem;
}

static NSString *wq_file_type_detail(WQItem *item)
{
    NSString *kind = wq_media_kind(item.path);
    NSString *extension = item.path.pathExtension.uppercaseString;
    if (kind) return extension.length ? [NSString stringWithFormat:@"%@ · %@", kind, extension] : kind;
    return extension.length ? extension : @"File";
}

static UIImage *wq_file_symbol(WQItem *item, CGFloat size)
{
    NSString *kind = wq_media_kind(item.path);
    NSString *symbol = item.isDir ? @"folder.fill" : (item.isLink ? @"link" : @"doc");
    if ([kind isEqualToString:@"Video"]) symbol = @"video.fill";
    else if ([kind isEqualToString:@"Photo"]) symbol = @"photo.fill";
    else if ([kind isEqualToString:@"Audio"]) symbol = @"waveform";
    return [UIImage systemImageNamed:symbol withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightRegular]];
}

static UIImage *wq_grid_tile_image(UIImage *source)
{
    if (!source) return nil;
    CGSize canvas = CGSizeMake(78, 78);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 2;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:canvas format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *__unused context) {
        [source drawInRect:(CGRect){CGPointZero, canvas}];
    }];
}

typedef NS_ENUM(NSInteger, WQFolderSortKey) {
    WQFolderSortDefault = 0,
    WQFolderSortName,
    WQFolderSortDate,
    WQFolderSortType,
    WQFolderSortSize,
};

static NSString *gTransferShelfPath;
static NSString *const WQTransferShelfDidChangeNotification = @"WQTransferShelfDidChangeNotification";
static NSString *const WQFolderGridViewKey = @"WQFolderGridViewV1";

@interface WQGridCell : UITableViewCell
- (void)configureSlot:(NSUInteger)slot item:(WQItem *_Nullable)item menu:(UIMenu *_Nullable)menu;
@property (nonatomic, copy) void (^openSlot)(NSUInteger slot);
@end

@implementation WQGridCell {
    NSArray<UIButton *> *_buttons;
}

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        NSMutableArray *buttons = [NSMutableArray new];
        for (NSUInteger slot = 0; slot < 2; slot++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tag = (NSInteger)slot;
            button.showsMenuAsPrimaryAction = NO;
            button.imageView.contentMode = UIViewContentModeScaleAspectFit;
            button.titleLabel.numberOfLines = 2;
            button.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
            button.titleLabel.textAlignment = NSTextAlignmentCenter;
            [button addTarget:self action:@selector(openButton:) forControlEvents:UIControlEventTouchUpInside];
            [buttons addObject:button];
        }
        _buttons = buttons;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:_buttons];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.spacing = 10;
        stack.distribution = UIStackViewDistributionFillEqually;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:5],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-5],
            [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5]
        ]];
    }
    return self;
}

- (void)configureSlot:(NSUInteger)slot item:(WQItem *)item menu:(UIMenu *)menu
{
    UIButton *button = _buttons[slot];
    button.hidden = item == nil;
    button.menu = menu;
    if (!item) return;
    UIImage *image = item.bundleID ? wq_app_icon(item.bundleID) : item.thumbnail;
    if (image) image = wq_grid_tile_image(image);
    else image = wq_file_symbol(item, 52);
    NSString *title = wq_compact_file_name(item, 25);
    NSString *subtitle = item.isDir ? @"Folder" : [NSString stringWithFormat:@"%@ · %@", wq_file_type_detail(item), wq_size_text(item.size)];
    NSDictionary *titleAttributes = @{NSFontAttributeName: IPFont(14, UIFontWeightSemibold),
                                       NSForegroundColorAttributeName: IPPrimaryText()};
    NSDictionary *subtitleAttributes = @{NSFontAttributeName: IPFont(11, UIFontWeightRegular),
                                          NSForegroundColorAttributeName: IPSecondaryText()};
    UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
    configuration.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:titleAttributes];
    configuration.attributedSubtitle = [[NSAttributedString alloc] initWithString:subtitle attributes:subtitleAttributes];
    configuration.image = image;
    configuration.imagePlacement = NSDirectionalRectEdgeTop;
    configuration.imagePadding = 9;
    configuration.titlePadding = 3;
    configuration.titleAlignment = UIButtonConfigurationTitleAlignmentCenter;
    configuration.baseForegroundColor = IPAccent();
    configuration.baseBackgroundColor = IPSurface();
    configuration.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(12, 8, 10, 8);
    button.configuration = configuration;
    button.accessibilityLabel = title;
    button.accessibilityHint = item.isDir ? @"Opens folder. Long press for more actions." : @"Opens file. Long press for more actions.";
}

- (void)openButton:(UIButton *)button { if (self.openSlot) self.openSlot((NSUInteger)button.tag); }
@end

@implementation WQDirViewController {
    NSString *_path;
    NSArray<WQItem *> *_all;     // everything in the folder
    NSArray<WQItem *> *_items;   // what the search lets through (shown)
    NSString *_query;
    UILabel *_pathLabel;
    UILabel *_deviceLabel;
    UILabel *_locationTitleLabel;
    UILabel *_scanLabel;
    UIProgressView *_scanProgress;
    UIView *_scanFolders;
    UIView *_locationCard;
    UIView *_headerBox;
    NSString *_scanStatus;
    CGFloat _headerWidth;
    NSString *_error;
    BOOL _labels;
    BOOL _backupManager;
    BOOL _backupStorage;
    BOOL _selectingBackups;
    BOOL _selectingFiles;
    NSMutableSet<NSString *> *_selectedBackups;
    NSMutableSet<NSString *> *_selectedFiles;
    UIBarButtonItem *_selectItem;
    UIBarButtonItem *_sortItem;
    UIBarButtonItem *_menuItem;
    UIBarButtonItem *_starItem;
    UIBarButtonItem *_doneItem;
    UIBarButtonItem *_deleteItem;
    UIBarButtonItem *_shareItem;
    UIBarButtonItem *_fileDoneItem;
    UIBarButtonItem *_fileAllItem;
    UIBarButtonItem *_allItem;
    NSString *_baseTitle;
    WQScanCancellation *_scanCancellation;
    NSUInteger _scanGeneration;
    BOOL _scanInFlight;
    BOOL _scanNeedsRefresh;
    NSTimeInterval _lastReloadFinished;
    WQFolderSortKey _sortKey;
    BOOL _sortAscending;
    BOOL _gridView;
    BOOL _folderViewAppeared;
    BOOL _tableRefreshPending;
    BOOL _tableRefreshScheduled;
}

- (instancetype)initWithPath:(NSString *)path title:(NSString *)title
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _path = [path copy];
        self.title = title ?: (path.lastPathComponent.length ? path.lastPathComponent : @"/");
        _baseTitle = self.title;
        _sortKey = WQFolderSortDefault;
        _sortAscending = YES;
        _gridView = [NSUserDefaults.standardUserDefaults boolForKey:WQFolderGridViewKey];
        _selectedBackups = [NSMutableSet new];
        _selectedFiles = [NSMutableSet new];
        // Container parents: show bundle/group identifiers instead of UUIDs.
        NSString *parent = path.lastPathComponent;
        _labels = [@[@"Application", @"AppGroup", @"PluginKitPlugin", @"InternalDaemon", @"System"] containsObject:parent];
        NSString *appBackups = wq_app_backup_root();
        NSString *fileBackups = wq_backup_root();
        _backupManager = appBackups.length &&
            ([_path isEqualToString:appBackups] || [_path hasPrefix:[appBackups stringByAppendingString:@"/"]]);
        _backupStorage = _backupManager ||
            (fileBackups.length && ([_path isEqualToString:fileBackups] || [_path hasPrefix:[fileBackups stringByAppendingString:@"/"]]));
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.refreshControl = [UIRefreshControl new];
    self.tableView.separatorStyle = _gridView ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine;
    self.tableView.prefetchDataSource = (id<UITableViewDataSourcePrefetching>)self;
    [self.refreshControl addTarget:self action:@selector(userRefresh) forControlEvents:UIControlEventValueChanged];
    _sortItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down.circle"]
                                                 menu:[self sortMenu]];
    _sortItem.accessibilityLabel = @"Sort files";
    _menuItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                 menu:[self browserMenu]];
    _starItem = [[UIBarButtonItem alloc] initWithImage:nil style:UIBarButtonItemStylePlain
                                                target:self action:@selector(toggleStar)];
    _starItem.accessibilityLabel = @"Star this folder";
    [self updateStarButton];
    if (_backupStorage) {
        _selectItem = [[UIBarButtonItem alloc] initWithTitle:@"Select" style:UIBarButtonItemStylePlain
                                                       target:self action:@selector(enterBackupSelection)];
        _selectItem.enabled = NO;
        self.navigationItem.rightBarButtonItems = @[_selectItem, _starItem, _sortItem, _menuItem];
    } else {
        self.navigationItem.rightBarButtonItems = @[_starItem, _sortItem, _menuItem];
    }
    [self updateHeader];
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = _labels ? @"Search names and bundle IDs" : @"Search this folder";
    search.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    search.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    IPStyleSearchBar(search.searchBar);
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(transferShelfDidChange:)
        name:WQTransferShelfDidChangeNotification object:nil];
    [self reload];
}

- (void)updateStarButton
{
    BOOL starred = wq_location_is_starred(_path);
    _starItem.image = [UIImage systemImageNamed:starred ? @"star.fill" : @"star"];
    _starItem.tintColor = starred ? UIColor.systemYellowColor : IPAccent();
    _starItem.accessibilityLabel = starred ? @"Remove this folder from Starred" : @"Add this folder to Starred";
}

- (void)toggleStar
{
    BOOL next = !wq_location_is_starred(_path);
    wq_set_location_starred(_path, _baseTitle, next);
    [self updateStarButton];
    _scanStatus = next ? @"Added to Starred" : @"Removed from Starred";
    [self updateHeader];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self->_scanStatus hasSuffix:@"Starred"]) { self->_scanStatus = nil; [self updateHeader]; }
    });
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (UIMenu *)sortMenu
{
    __weak typeof(self) weakSelf = self;
    NSArray *titles = @[@"Default", @"Name", @"Date", @"Type", @"Size"];
    NSArray *symbols = @[@"line.3.horizontal.decrease", @"textformat", @"calendar", @"doc.on.doc", @"internaldrive"];
    NSMutableArray<UIAction *> *sortActions = [NSMutableArray new];
    for (NSInteger value = WQFolderSortDefault; value <= WQFolderSortSize; value++) {
        UIAction *action = [UIAction actionWithTitle:titles[(NSUInteger)value]
                                               image:[UIImage systemImageNamed:symbols[(NSUInteger)value]]
                                          identifier:nil
                                             handler:^(__kindof UIAction *__unused sender) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_sortKey = (WQFolderSortKey)value;
            [self applySortAndFilter];
            self->_sortItem.menu = [self sortMenu];
        }];
        action.state = _sortKey == value ? UIMenuElementStateOn : UIMenuElementStateOff;
        [sortActions addObject:action];
    }
    UIAction *direction = [UIAction actionWithTitle:_sortAscending ? @"Ascending" : @"Descending"
                                               image:[UIImage systemImageNamed:_sortAscending ? @"chevron.up" : @"chevron.down"]
                                          identifier:nil handler:^(__kindof UIAction *__unused sender) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self->_sortAscending = !self->_sortAscending;
        [self applySortAndFilter];
        self->_sortItem.menu = [self sortMenu];
    }];
    UIMenu *choices = [UIMenu menuWithTitle:@""
                                      image:nil
                                 identifier:nil
                                    options:UIMenuOptionsDisplayInline | UIMenuOptionsSingleSelection
                                   children:sortActions];
    UIMenu *directionGroup = [UIMenu menuWithTitle:@"" image:nil identifier:nil
                                            options:UIMenuOptionsDisplayInline children:@[direction]];
    UIAction *list = [UIAction actionWithTitle:@"List" image:[UIImage systemImageNamed:@"list.bullet"]
                                     identifier:nil handler:^(__kindof UIAction *__unused sender) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self) [self setGridView:NO];
    }];
    list.state = !_gridView ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIAction *grid = [UIAction actionWithTitle:@"Grid" image:[UIImage systemImageNamed:@"square.grid.2x2"]
                                     identifier:nil handler:^(__kindof UIAction *__unused sender) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self) [self setGridView:YES];
    }];
    grid.state = _gridView ? UIMenuElementStateOn : UIMenuElementStateOff;
    if (_selectingFiles || _selectingBackups) grid.attributes = UIMenuElementAttributesDisabled;
    UIMenu *viewGroup = [UIMenu menuWithTitle:@"View" image:nil identifier:nil
                                      options:UIMenuOptionsDisplayInline | UIMenuOptionsSingleSelection
                                     children:@[list, grid]];
    return [UIMenu menuWithTitle:@"Sort and View" children:@[viewGroup, choices, directionGroup]];
}

- (void)setGridView:(BOOL)grid
{
    if (_gridView == grid) return;
    _gridView = grid;
    [NSUserDefaults.standardUserDefaults setBool:grid forKey:WQFolderGridViewKey];
    self.tableView.separatorStyle = grid ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine;
    _sortItem.menu = [self sortMenu];
    [self.tableView reloadData];
}

- (UIMenu *)browserMenu
{
    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray new];
    UIAction *selectFiles = [UIAction actionWithTitle:@"Select Files" image:[UIImage systemImageNamed:@"checkmark.circle"]
                                            identifier:nil handler:^(UIAction *__unused action) { [weakSelf enterFileSelection]; }];
    if (_selectingFiles || _selectingBackups) selectFiles.attributes = UIMenuElementAttributesDisabled;
    [items addObject:selectFiles];
    NSString *pasteTitle = gTransferShelfPath.length
        ? [NSString stringWithFormat:@"Paste %@ Here", gTransferShelfPath.lastPathComponent]
        : @"Paste from Transfer Shelf";
    UIAction *paste = [UIAction actionWithTitle:pasteTitle image:[UIImage systemImageNamed:@"doc.on.clipboard"]
                                      identifier:nil handler:^(UIAction *__unused a) { [weakSelf pasteTransferShelf]; }];
    if (!gTransferShelfPath.length || self.readOnly || _backupStorage)
        paste.attributes = UIMenuElementAttributesDisabled;
    [items addObject:paste];
    if (gTransferShelfPath.length) {
        [items addObject:[UIAction actionWithTitle:@"Clear Transfer Shelf" image:[UIImage systemImageNamed:@"xmark.bin"]
                                       identifier:nil handler:^(UIAction *__unused a) {
            gTransferShelfPath = nil;
            [NSNotificationCenter.defaultCenter postNotificationName:WQTransferShelfDidChangeNotification object:nil];
        }]];
    }
    if (!self.readOnly && !_backupStorage) {
        [items addObject:[UIAction actionWithTitle:@"New Folder" image:[UIImage systemImageNamed:@"folder.badge.plus"] identifier:nil
                          handler:^(UIAction *__unused a) { [weakSelf promptNewFolder]; }]];
        [items addObject:[UIAction actionWithTitle:@"Import File" image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil
                          handler:^(UIAction *__unused a) { [weakSelf importFile]; }]];
    }
    NSString *path = _path;
    [items addObject:[UIAction actionWithTitle:@"Copy Path" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil
                      handler:^(UIAction *__unused a) { UIPasteboard.generalPasteboard.string = path; }]];
    return [UIMenu menuWithChildren:items];
}

- (void)transferShelfDidChange:(NSNotification *)notification
{
    _menuItem.menu = [self browserMenu];
}

- (void)copyItemToTransferShelf:(WQItem *)item
{
    if (!item.path.length || item.isLink || (!item.isDir && !item.isRegular)) return;
    gTransferShelfPath = [item.path copy];
    [NSNotificationCenter.defaultCenter postNotificationName:WQTransferShelfDidChangeNotification object:nil];
    _scanStatus = [NSString stringWithFormat:@"%@ ready to paste", item.label ?: item.name];
    [self updateHeader];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self->_scanStatus hasSuffix:@"ready to paste"]) { self->_scanStatus = nil; [self updateHeader]; }
    });
}

- (void)pasteTransferShelf
{
    NSString *source = [gTransferShelfPath copy];
    if (!source.length || self.readOnly || _backupStorage) return;
    NSString *destination = [_path stringByAppendingPathComponent:source.lastPathComponent];
    void (^performCopy)(void) = ^{
        [self runIO:^BOOL(NSString **error) { return wq_copy_item(source, destination, error); }
              failure:@"Cannot copy item"];
    };
    struct stat existing = {0};
    if (!wq_stat(destination, &existing)) { performCopy(); return; }
    NSString *message = S_ISDIR(existing.st_mode)
        ? @"A folder with this name already exists. Its contents will be merged and same-named items replaced safely."
        : @"A file with this name already exists. Its previous contents will be saved in Backups before replacement.";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Replace existing item?"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *__unused action) { performCopy(); }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)applySortAndFilter
{
    NSArray<WQItem *> *source = [_all sortedArrayUsingComparator:^NSComparisonResult(WQItem *a, WQItem *b) {
        if (a.isDir != b.isDir) return a.isDir ? NSOrderedAscending : NSOrderedDescending;
        NSComparisonResult result = NSOrderedSame;
        switch (self->_sortKey) {
            case WQFolderSortDate:
                result = [(a.modified ?: NSDate.distantPast) compare:(b.modified ?: NSDate.distantPast)];
                break;
            case WQFolderSortType: {
                NSString *left = a.isDir ? @"" : a.name.pathExtension.lowercaseString;
                NSString *right = b.isDir ? @"" : b.name.pathExtension.lowercaseString;
                result = [left localizedCaseInsensitiveCompare:right];
                break;
            }
            case WQFolderSortSize:
                result = a.size < b.size ? NSOrderedAscending : (a.size > b.size ? NSOrderedDescending : NSOrderedSame);
                break;
            case WQFolderSortDefault:
            case WQFolderSortName:
                break;
        }
        if (result == NSOrderedSame)
            result = [(a.label ?: a.name) localizedCaseInsensitiveCompare:(b.label ?: b.name)];
        return self->_sortAscending ? result : (NSComparisonResult)-result;
    }];
    _all = source;
    [self applyFilter];
    [self scheduleTableRefresh];
}

- (void)scheduleTableRefresh
{
    _tableRefreshPending = YES;
    if (!_folderViewAppeared || _tableRefreshScheduled) return;
    _tableRefreshScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_tableRefreshScheduled = NO;
        if (!self->_folderViewAppeared || !self->_tableRefreshPending) return;
        self->_tableRefreshPending = NO;
        [UIView performWithoutAnimation:^{ [self.tableView reloadData]; }];
    });
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (_scanInFlight) return;
    NSTimeInterval age = NSDate.date.timeIntervalSinceReferenceDate - _lastReloadFinished;
    if (_scanNeedsRefresh || _lastReloadFinished <= 0 || age > 2.0) [self reload];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    _folderViewAppeared = YES;
    wq_record_recent(_path, _baseTitle, YES);
    if (_tableRefreshPending) [self scheduleTableRefresh];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    _folderViewAppeared = NO;
    if (_selectingFiles) [self exitFileSelection];
    if (_selectingBackups) [self exitBackupSelection];
    if (_scanInFlight) {
        _scanNeedsRefresh = YES;
        [_scanCancellation cancel];
    }
    _scanStatus = nil;
    [self.refreshControl endRefreshing];
    [self updateHeader];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    if (!self.presentedViewController && self.navigationController.topViewController != self) {
        wq_share_cancel(self);
    }
}

// A themed location card replaces the old diagnostic strip. It keeps the path
// readable and turns inode/container discovery into a visible progress state.
- (void)updateHeader
{
    CGFloat width = self.tableView.bounds.size.width ?: self.view.bounds.size.width;
    if (!_headerBox) {
        _headerBox = [UIView new];
        _locationCard = [UIView new];
        _locationCard.backgroundColor = IPSurface();
        _locationCard.layer.cornerCurve = kCACornerCurveContinuous;
        _locationCard.layer.cornerRadius = IPCornerRadius(24);
        [_headerBox addSubview:_locationCard];

        UIImageView *deviceIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"iphone.gen3"]];
        deviceIcon.frame = CGRectMake(20, 17, 20, 20);
        deviceIcon.tintColor = IPAccent();
        [_locationCard addSubview:deviceIcon];
        _deviceLabel = [UILabel new];
        _deviceLabel.font = IPFont(11, UIFontWeightSemibold);
        _deviceLabel.textColor = IPSecondaryText();
        _deviceLabel.adjustsFontSizeToFitWidth = YES;
        _deviceLabel.minimumScaleFactor = 0.72;
        _deviceLabel.text = wq_device_line();
        [_locationCard addSubview:_deviceLabel];

        _locationTitleLabel = [UILabel new];
        _locationTitleLabel.text = @"CURRENT LOCATION";
        _locationTitleLabel.font = IPFont(11, UIFontWeightBold);
        _locationTitleLabel.textColor = IPAccent();
        [_locationCard addSubview:_locationTitleLabel];

        _pathLabel = [UILabel new];
        _pathLabel.numberOfLines = 0;
        _pathLabel.font = IPFont(15, UIFontWeightSemibold);
        _pathLabel.textColor = IPPrimaryText();
        _pathLabel.userInteractionEnabled = YES;
        [_pathLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(copyPath)]];
        [_locationCard addSubview:_pathLabel];

        _scanFolders = wq_folder_stack_view(CGSizeMake(54, 54), YES);
        _scanFolders.translatesAutoresizingMaskIntoConstraints = YES;
        [_locationCard addSubview:_scanFolders];
        _scanLabel = [UILabel new];
        _scanLabel.font = IPFont(13, UIFontWeightSemibold);
        _scanLabel.textColor = IPSecondaryText();
        _scanLabel.numberOfLines = 2;
        [_locationCard addSubview:_scanLabel];
        _scanProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _scanProgress.progressTintColor = IPAccent();
        _scanProgress.trackTintColor = IPTrack();
        _scanProgress.layer.cornerRadius = 3;
        _scanProgress.clipsToBounds = YES;
        _scanProgress.transform = CGAffineTransformMakeScale(1, 2.1);
        [_locationCard addSubview:_scanProgress];
        self.tableView.tableHeaderView = _headerBox;
    }

    NSString *breakable = [_path stringByReplacingOccurrencesOfString:@"/" withString:@"/\u200B"];
    _pathLabel.text = breakable;
    CGFloat cardX = 16, cardWidth = MAX(1, width - 32);
    _deviceLabel.frame = CGRectMake(48, 16, MAX(1, cardWidth - 68), 22);
    _locationTitleLabel.frame = CGRectMake(20, 50, MAX(1, cardWidth - 40), 18);
    CGSize fit = [_pathLabel sizeThatFits:CGSizeMake(cardWidth - 40, CGFLOAT_MAX)];
    _pathLabel.frame = CGRectMake(20, 71, cardWidth - 40, ceil(fit.height));
    CGFloat nextY = CGRectGetMaxY(_pathLabel.frame) + 13;
    BOOL scanning = _scanStatus.length > 0;
    _scanFolders.hidden = !scanning;
    _scanLabel.hidden = !scanning;
    _scanProgress.hidden = !scanning || [_scanStatus isEqualToString:@"Path copied"];
    if (scanning) {
        _scanFolders.frame = CGRectMake(17, nextY, 54, 54);
        _scanLabel.frame = CGRectMake(82, nextY + 2, MAX(1, cardWidth - 102), 34);
        _scanLabel.text = _scanStatus;
        _scanProgress.frame = CGRectMake(82, nextY + 43, MAX(1, cardWidth - 104), 4);
        float progress = wq_progress_from_text(_scanStatus);
        _scanProgress.progress = progress >= 0 ? progress : 0.28;
        nextY += 67;
    }
    CGFloat cardHeight = nextY + 14;
    _locationCard.frame = CGRectMake(cardX, 8, cardWidth, cardHeight);
    CGFloat height = cardHeight + 20;
    CGFloat oldHeight = _headerBox.frame.size.height;
    _headerBox.frame = CGRectMake(0, 0, width, height);
    _headerWidth = width;
    if (fabs(height - oldHeight) > 0.5) self.tableView.tableHeaderView = _headerBox;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    if (fabs(self.tableView.bounds.size.width - _headerWidth) > 0.5) [self updateHeader];
}

- (void)copyPath
{
    UIPasteboard.generalPasteboard.string = _path;
    _scanStatus = @"Path copied";
    [self updateHeader];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self->_scanStatus isEqualToString:@"Path copied"]) { self->_scanStatus = nil; [self updateHeader]; }
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    NSString *q = [searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    _query = q.length ? q : nil;
    [self applyFilter];
    [self.tableView reloadData];
}

// App name, bundle or group ID, or file name; case and accents ignored.
- (void)applyFilter
{
    if (!_query) { _items = _all; return; }
    NSStringCompareOptions opts = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    NSString *q = _query;
    _items = [_all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(WQItem *item, NSDictionary *__unused b) {
        for (NSString *field in @[item.label ?: @"", item.name ?: @"", item.bundleID ?: @""])
            if ([field rangeOfString:q options:opts].location != NSNotFound) return YES;
        return NO;
    }]];
}

#pragma mark File multi-selection

- (NSArray<NSString *> *)selectableFilePaths
{
    NSMutableArray<NSString *> *paths = [NSMutableArray new];
    for (WQItem *item in _items)
        if (item.isRegular && !item.isLink) [paths addObject:item.path];
    return paths;
}

- (void)updateFileSelectionBar
{
    _shareItem.enabled = _selectedFiles.count > 0;
    _fileAllItem.enabled = _selectedFiles.count < [self selectableFilePaths].count;
    self.title = _selectedFiles.count
        ? [NSString stringWithFormat:@"%lu Selected", (unsigned long)_selectedFiles.count] : @"Select Files";
}

- (void)enterFileSelection
{
    if ([self selectableFilePaths].count == 0) {
        wq_alert(self, @"No files to select", @"This folder does not contain regular files that can be shared.");
        return;
    }
    if (_gridView) [self setGridView:NO];
    _selectingFiles = YES;
    [_selectedFiles removeAllObjects];
    _fileDoneItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleProminent
                                                target:self action:@selector(exitFileSelection)];
    _shareItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                                 style:UIBarButtonItemStyleProminent target:self action:@selector(shareSelectedFiles)];
    _shareItem.accessibilityLabel = @"Share or Save Selected Files";
    _fileAllItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle"]
                                               style:UIBarButtonItemStylePlain target:self action:@selector(selectAllFiles)];
    _fileAllItem.accessibilityLabel = @"Select All Files";
    self.refreshControl.enabled = NO;
    self.tableView.allowsMultipleSelection = YES;
    self.navigationItem.rightBarButtonItems = @[_shareItem, _fileAllItem, _fileDoneItem];
    [self updateFileSelectionBar];
    [self.tableView reloadData];
}

- (void)exitFileSelection
{
    if (!_selectingFiles) return;
    _selectingFiles = NO;
    [_selectedFiles removeAllObjects];
    self.tableView.allowsMultipleSelection = NO;
    self.refreshControl.enabled = YES;
    self.title = _baseTitle;
    self.navigationItem.rightBarButtonItems = _backupStorage
        ? @[_selectItem, _starItem, _sortItem, _menuItem] : @[_starItem, _sortItem, _menuItem];
    _sortItem.menu = [self sortMenu];
    _menuItem.menu = [self browserMenu];
    [self.tableView reloadData];
}

- (void)selectAllFiles
{
    [_selectedFiles addObjectsFromArray:[self selectableFilePaths]];
    for (NSUInteger row = 0; row < _items.count; row++) {
        WQItem *item = _items[row];
        if (item.isRegular && !item.isLink)
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]
                                        animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
    [self updateFileSelectionBar];
    [self.tableView reloadData];
}

- (void)shareSelectedFiles
{
    NSArray<NSString *> *paths = _selectedFiles.allObjects;
    if (paths.count == 0) return;
    [self exitFileSelection];
    wq_share_files(self, paths, nil);
}

#pragma mark Backup multi-selection

- (NSArray<NSString *> *)backupUnitPathsInItems
{
    NSMutableArray<NSString *> *paths = [NSMutableArray new];
    for (WQItem *item in _items)
        if (wq_backup_unit_deletable(item.path)) [paths addObject:item.path];
    return paths;
}

- (void)updateBackupSelectionAvailability
{
    _selectItem.enabled = !_selectingBackups && [self backupUnitPathsInItems].count > 0;
}

- (void)updateBackupSelectionBar
{
    _deleteItem.enabled = _selectedBackups.count > 0;
    _allItem.enabled = _selectedBackups.count < [self backupUnitPathsInItems].count;
}

- (void)enterBackupSelection
{
    if ([self backupUnitPathsInItems].count == 0) {
        wq_alert(self, @"Nothing to select", @"Only complete backup folders can be selected here.");
        return;
    }
    if (_gridView) [self setGridView:NO];
    _selectingBackups = YES;
    [_selectedBackups removeAllObjects];
    if (!_doneItem) {
        _doneItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleProminent
                                                       target:self action:@selector(exitBackupSelection)];
        _deleteItem = [[UIBarButtonItem alloc] initWithTitle:@"Delete" style:UIBarButtonItemStylePlain
                                                       target:self action:@selector(deleteSelectedBackups)];
        _deleteItem.tintColor = UIColor.systemRedColor;
        _allItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle"]
                                                     style:UIBarButtonItemStylePlain
                                                    target:self action:@selector(selectAllBackups)];
        _allItem.accessibilityLabel = @"Select All";
    }
    self.refreshControl.enabled = NO;
    self.tableView.allowsMultipleSelection = YES;
    self.title = @"Select Backups";
    self.navigationItem.rightBarButtonItems = @[_allItem, _deleteItem, _doneItem];
    [self updateBackupSelectionBar];
    [self.tableView reloadData];
}

- (void)exitBackupSelection
{
    if (!_selectingBackups) return;
    _selectingBackups = NO;
    [_selectedBackups removeAllObjects];
    self.tableView.allowsMultipleSelection = NO;
    self.refreshControl.enabled = YES;
    self.title = _baseTitle;
    self.navigationItem.rightBarButtonItems = _backupStorage
        ? @[_selectItem, _starItem, _sortItem, _menuItem] : @[_starItem, _sortItem, _menuItem];
    [self.tableView reloadData];
    [self updateBackupSelectionAvailability];
}

- (void)selectAllBackups
{
    NSArray<NSString *> *paths = [self backupUnitPathsInItems];
    [_selectedBackups addObjectsFromArray:paths];
    [self updateBackupSelectionBar];
    [self.tableView reloadData];
}

- (void)deleteSelectedBackups
{
    NSArray<NSString *> *paths = [_selectedBackups.allObjects sortedArrayUsingSelector:@selector(compare:)];
    if (paths.count == 0) return;
    NSString *message = [NSString stringWithFormat:
        @"This permanently removes %lu complete backup%@ and everything inside them. It cannot be undone.",
        (unsigned long)paths.count, paths.count == 1 ? @"" : @"s"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete backups?"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive
                                              handler:^(UIAlertAction *__unused a) {
        [self exitBackupSelection];
        [self runIO:^BOOL(NSString **error) {
            NSString *first = nil;
            for (NSString *path in paths) {
                NSString *failure = nil;
                if (!wq_delete_backup(path, &failure) && first == nil)
                    first = failure ?: @"Could not remove a backup.";
            }
            if (first) {
                if (error) *error = [NSString stringWithFormat:@"%@ Some selected backups may still exist.", first];
                return NO;
            }
            return YES;
        } failure:@"Cannot delete backups"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Pull to refresh: container lists are scanned again instead of reused.
- (void)userRefresh
{
    wq_enumerate_invalidate();
    wq_display_names_reset_miss();
    [self reload];
}

- (void)reload
{
    [_scanCancellation cancel];
    WQScanCancellation *cancellation = [WQScanCancellation new];
    _scanCancellation = cancellation;
    NSUInteger generation = ++_scanGeneration;
    _scanInFlight = YES;
    _scanNeedsRefresh = NO;
    _scanStatus = nil;
    [self.refreshControl endRefreshing];
    [self updateHeader];
    NSString *path = _path;
    BOOL labels = _labels;
    BOOL enumerable = [@[@"/private/var/mobile/Containers/Data/Application",
                         @"/var/mobile/Containers/Data/Application",
                         @"/private/var/mobile/Containers/Data/PluginKitPlugin",
                         @"/var/mobile/Containers/Data/PluginKitPlugin",
                         @"/private/var/mobile/Containers/Data/InternalDaemon",
                         @"/var/mobile/Containers/Data/InternalDaemon",
                         // Listable on iOS 27; on iOS 26 only by scanning.
                         @"/private/var/mobile/Containers/Shared/AppGroup",
                         @"/var/mobile/Containers/Shared/AppGroup"] containsObject:path];
    dispatch_async(wq_io(), ^{
        NSString *error = nil;
        NSArray *names = wq_list(path, &error);
        NSArray *childPaths = nil;
        // Parent gives no token on 27.x: discover children with fsgetpath.
        if (!names && enumerable && !cancellation.isCancelled) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self->_scanGeneration || cancellation.isCancelled) return;
                self->_scanStatus = @"Scanning inodes…";
                [self updateHeader];
            });
            CFAbsoluteTime scanStarted = CFAbsoluteTimeGetCurrent();
            childPaths = wq_enumerate(path, 0, cancellation, ^(int64_t done, int64_t total, NSUInteger __unused f) {
                // Time left, once the rate is known: an iOS 26 id scan can take most of an hour.
                double elapsed = CFAbsoluteTimeGetCurrent() - scanStarted;
                NSString *left = @"";
                if (elapsed > 5 && done > 0 && done < total) {
                    double remaining = elapsed * (double)(total - done) / (double)done;
                    left = remaining >= 90 ? [NSString stringWithFormat:@" · about %.0f min left", ceil(remaining / 60)]
                                           : @" · less than 2 min left";
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (generation != self->_scanGeneration || cancellation.isCancelled) return;
                    self->_scanStatus = [NSString stringWithFormat:@"Scanning inodes… %lld%% · %lu found%@",
                                         total ? (long long)(done * 100 / total) : 0, (unsigned long)f, left];
                    [self updateHeader];
                });
            });
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self->_scanGeneration || cancellation.isCancelled) return;
                self->_scanStatus = nil;
                [self updateHeader];
            });
        }
        if (cancellation.isCancelled) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self->_scanGeneration) return;
                self->_scanInFlight = NO;
                self->_scanNeedsRefresh = YES;
                self->_scanStatus = nil;
                [self.refreshControl endRefreshing];
                [self updateHeader];
            });
            return;
        }
        NSMutableArray<WQItem *> *items = [NSMutableArray new];
        NSUInteger labelIssues = 0;
        NSArray *entries = names ?: childPaths;
        BOOL haveFullPaths = names == nil;
        NSUInteger entryIndex = 0, entryCount = entries.count;
        for (NSString *entry in entries) {
            entryIndex++;
            // Each container needs a token and its identifier: hundreds take a
            // few seconds, so show where it is.
            if (haveFullPaths && (entryIndex == 1 || entryIndex % 10 == 0)) {
                NSUInteger shown = entryIndex;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (generation != self->_scanGeneration || cancellation.isCancelled) return;
                    self->_scanStatus = [NSString stringWithFormat:@"Reading containers… %lu of %lu",
                                         (unsigned long)shown, (unsigned long)entryCount];
                    [self updateHeader];
                });
            }
            if (cancellation.isCancelled) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (generation != self->_scanGeneration) return;
                    self->_scanInFlight = NO;
                    self->_scanNeedsRefresh = YES;
                    self->_scanStatus = nil;
                    [self.refreshControl endRefreshing];
                    [self updateHeader];
                });
                return;
            }
            WQItem *item = [WQItem new];
            item.name = haveFullPaths ? entry.lastPathComponent : entry;
            item.path = haveFullPaths ? entry : [path stringByAppendingPathComponent:entry];
            NSString *name = item.name;
            // Enumerated containers need a token before they can be stat'd.
            if (haveFullPaths) {
                item.isDir = YES;
                BOOL token = wq_grant(item.path);
                NSString *bid = token ? wq_container_label(item.path) : nil;
                item.bundleID = bid;
                if (bid) (void)wq_app_icon(bid);   // warm the icon off the main thread
                item.label = token ? (wq_display_name(bid) ?: bid ?: @"(no label)") : @"NO TOKEN";
                if (!token && labelIssues < 3) {
                    wq_log(@"label: no token for %@", item.path);
                    labelIssues++;
                } else if (token && !bid.length && labelIssues < 3) {
                    wq_log(@"label: no container identifier for %@", item.path);
                    labelIssues++;
                }
            }
            struct stat st;
            if (lstat(item.path.fileSystemRepresentation, &st) == 0) {
                item.isLink = S_ISLNK(st.st_mode);
                item.isDir = S_ISDIR(st.st_mode);
                item.isRegular = S_ISREG(st.st_mode);
                item.size = (unsigned long long)st.st_size;
                item.mode = st.st_mode;
                item.uid = st.st_uid;
                item.modified = [NSDate dateWithTimeIntervalSince1970:st.st_mtimespec.tv_sec];
            }
            if (!haveFullPaths && labels && item.isDir && wq_looks_like_uuid(name)) {
                NSString *bid = wq_container_label(item.path);
                item.bundleID = bid;
                if (bid) (void)wq_app_icon(bid);   // warm the icon off the main thread
                item.label = wq_display_name(bid) ?: bid;
            }
            if (!haveFullPaths && item.isDir && !item.bundleID) {
                // App backups: AppBackups/<bundle id>/...
                if ([path.lastPathComponent isEqualToString:@"AppBackups"]) {
                    item.bundleID = name;
                    item.label = wq_display_name(name) ?: name;
                }
                // File backups mirror the original path; label container UUIDs
                // from the live container they came from.
                NSString *live = wq_backup_original_path(item.path);
                if (live && wq_looks_like_uuid(name)) {
                    NSString *bid = wq_container_label(live);
                    if (bid) { item.bundleID = bid; item.label = wq_display_name(bid) ?: bid; (void)wq_app_icon(bid); }
                }
                if ([path isEqualToString:wq_backup_root().stringByDeletingLastPathComponent]) {
                    if ([name isEqualToString:@"Backups"]) item.label = @"File Backups";
                    if ([name isEqualToString:@"AppBackups"]) item.label = @"App Backups";
                }
            }
            [items addObject:item];
        }
        [items sortUsingComparator:^NSComparisonResult(WQItem *a, WQItem *b) {
            if (a.isDir != b.isDir) return a.isDir ? NSOrderedAscending : NSOrderedDescending;
            return [(a.label ?: a.name) localizedCaseInsensitiveCompare:(b.label ?: b.name)];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_scanGeneration) return;
            self->_scanInFlight = NO;
            if (cancellation.isCancelled) {
                self->_scanNeedsRefresh = YES;
                self->_scanStatus = nil;
                [self.refreshControl endRefreshing];
                [self updateHeader];
                return;
            }
            self->_all = items;
            self->_error = (names || childPaths != nil) ? nil
                : (error.length ? error : @"Cannot list this folder. Container enumeration failed; see Log.");
            [self applySortAndFilter];
            self->_scanStatus = nil;
            self->_lastReloadFinished = NSDate.date.timeIntervalSinceReferenceDate;
            [self.refreshControl endRefreshing];
            [self updateHeader];
            [self updateBackupSelectionAvailability];
            if (self->_selectingBackups) [self updateBackupSelectionBar];
        });
    });
}

- (void)requestThumbnailForItem:(WQItem *)item
{
    if (item.isDir || !item.isRegular || item.thumbnail || item.thumbnailRequested) return;
    static NSSet<NSString *> *thumbnailExtensions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        thumbnailExtensions = [wq_image_extensions() setByAddingObjectsFromSet:
            [wq_video_extensions() setByAddingObjectsFromSet:wq_audio_extensions()]];
    });
    if (![thumbnailExtensions containsObject:item.path.pathExtension.lowercaseString]) return;
    item.thumbnailRequested = YES;
    NSString *requestedPath = item.path.copy;
    __weak typeof(self) weakSelf = self;
    wq_file_thumbnail(requestedPath, CGSizeMake(120, 120), ^(UIImage *image) {
        WQDirViewController *strongSelf = weakSelf;
        if (!strongSelf || !image) return;
        NSUInteger itemIndex = [strongSelf->_items indexOfObjectPassingTest:^BOOL(WQItem *candidate, NSUInteger __unused idx, BOOL *__unused stop) {
            return [candidate.path isEqualToString:requestedPath];
        }];
        if (itemIndex == NSNotFound) return;
        strongSelf->_items[itemIndex].thumbnail = image;
        [strongSelf scheduleTableRefresh];
    });
}

- (void)tableView:(UITableView *)tableView prefetchRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    if (_error || _scanInFlight || _items.count == 0) return;
    for (NSIndexPath *indexPath in indexPaths) {
        NSUInteger first = _gridView ? (NSUInteger)indexPath.row * 2 : (NSUInteger)indexPath.row;
        NSUInteger count = _gridView ? 2 : 1;
        for (NSUInteger offset = 0; offset < count && first + offset < _items.count; offset++)
            [self requestThumbnailForItem:_items[first + offset]];
    }
}

- (UIMenu *)gridMenuForItem:(WQItem *)item
{
    NSString *path = item.path.copy;
    NSString *name = (item.label ?: item.name).copy;
    BOOL directory = item.isDir;
    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray new];
    if (directory) {
        BOOL starred = wq_location_is_starred(path);
        [actions addObject:[UIAction actionWithTitle:starred ? @"Remove from Starred" : @"Add to Starred"
                                               image:[UIImage systemImageNamed:starred ? @"star.slash" : @"star"]
                                          identifier:nil handler:^(UIAction *__unused action) {
            wq_set_location_starred(path, name, !starred);
        }]];
    }
    [actions addObject:[UIAction actionWithTitle:@"Share" image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                      identifier:nil handler:^(UIAction *__unused action) {
        WQDirViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (directory) wq_share_folder(strongSelf, path, nil, nil);
        else wq_share(strongSelf, path, nil);
    }]];
    [actions addObject:[UIAction actionWithTitle:@"Copy to Transfer Shelf" image:[UIImage systemImageNamed:@"doc.on.clipboard"]
                                      identifier:nil handler:^(UIAction *__unused action) {
        WQDirViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        WQItem *latest = [strongSelf->_items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(WQItem *candidate, NSDictionary *__unused bindings) {
            return [candidate.path isEqualToString:path];
        }]].firstObject;
        if (latest) [strongSelf copyItemToTransferShelf:latest];
    }]];
    [actions addObject:[UIAction actionWithTitle:@"Info" image:[UIImage systemImageNamed:@"info.circle"]
                                      identifier:nil handler:^(UIAction *__unused action) {
        WQDirViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        WQItem *latest = [strongSelf->_items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(WQItem *candidate, NSDictionary *__unused bindings) {
            return [candidate.path isEqualToString:path];
        }]].firstObject;
        if (latest) [strongSelf showInfoForItem:latest];
    }]];
    return [UIMenu menuWithChildren:actions];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (_error || _scanInFlight || _items.count == 0) return 1;
    return _gridView ? (NSInteger)((_items.count + 1) / 2) : (NSInteger)_items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_gridView && !_error && !_scanInFlight && _items.count > 0) {
        WQGridCell *gridCell = [tableView dequeueReusableCellWithIdentifier:@"grid"]
            ?: [[WQGridCell alloc] initWithReuseIdentifier:@"grid"];
        NSUInteger first = (NSUInteger)indexPath.row * 2;
        for (NSUInteger slot = 0; slot < 2; slot++) {
            NSUInteger itemIndex = first + slot;
            WQItem *item = itemIndex < _items.count ? _items[itemIndex] : nil;
            UIMenu *menu = item ? [self gridMenuForItem:item] : nil;
            if (item) {
                [self requestThumbnailForItem:item];
            }
            [gridCell configureSlot:slot item:item menu:menu];
        }
        __weak typeof(self) weakSelf = self;
        gridCell.openSlot = ^(NSUInteger slot) {
            WQDirViewController *strongSelf = weakSelf;
            NSUInteger itemIndex = first + slot;
            if (strongSelf && itemIndex < strongSelf->_items.count)
                [strongSelf openItem:strongSelf->_items[itemIndex]];
        };
        return gridCell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"item"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"item"];
    UIListContentConfiguration *c = cell.defaultContentConfiguration;
    if (_error) {
        c.text = @"Cannot open this folder";
        BOOL container = [_path containsString:@"/Containers/"] || [_path containsString:@"/SystemGroup/"];
        c.secondaryText = container ? _error
            : [NSString stringWithFormat:@"%@\n\nThis method only opens containers. Use App Data, App Groups, "
               "Extension Data, Internal Daemons or System Groups for the folders inside /private/var.", _error];
        c.secondaryTextProperties.numberOfLines = 0;
        c.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
        c.textProperties.color = IPPrimaryText();
        c.secondaryTextProperties.color = IPSecondaryText();
        cell.contentConfiguration = c;
        IPStyleCell(cell);
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    if (_scanInFlight || _items.count == 0) {
        BOOL searching = _query.length > 0 && _all.count > 0;
        c.text = _scanInFlight ? @"Loading folder…" : (searching ? @"No matching items" : @"This folder is empty");
        c.secondaryText = _scanInFlight
            ? @"Checking access and reading this location."
            : (searching ? @"The folder loaded, but nothing matches your search."
                         : @"Loaded successfully — there are no files or folders here.");
        c.secondaryTextProperties.numberOfLines = 0;
        c.image = [UIImage systemImageNamed:_scanInFlight ? @"arrow.triangle.2.circlepath" :
                   (searching ? @"magnifyingglass" : @"folder")];
        c.imageProperties.tintColor = IPAccent();
        c.textProperties.color = IPPrimaryText();
        c.secondaryTextProperties.color = IPSecondaryText();
        cell.contentConfiguration = c;
        IPStyleCell(cell);
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    WQItem *item = _items[(NSUInteger)indexPath.row];
    c.text = wq_compact_file_name(item, 38);
    NSString *date = wq_folder_date_text(item.modified);
    NSString *detail = item.isDir ? date : [NSString stringWithFormat:@"%@ · %@ · %@",
        wq_file_type_detail(item), wq_size_text(item.size), date];
    if (item.label) detail = [NSString stringWithFormat:@"%@\n%@", item.name, detail];
    if (item.isLink) detail = [@"symlink · " stringByAppendingString:detail];
    c.secondaryText = detail;
    c.textProperties.color = IPPrimaryText();
    c.textProperties.numberOfLines = 1;
    c.textProperties.lineBreakMode = NSLineBreakByTruncatingMiddle;
    c.secondaryTextProperties.color = IPSecondaryText();
    c.secondaryTextProperties.numberOfLines = item.label ? 2 : 1;
    c.secondaryTextProperties.lineBreakMode = NSLineBreakByTruncatingMiddle;
    UIImage *appIcon = item.bundleID ? wq_app_icon(item.bundleID) : nil;
    UIImage *preview = item.thumbnail;
    c.image = appIcon ?: preview ?: wq_file_symbol(item, 28);
    c.imageProperties.maximumSize = (appIcon || preview) ? CGSizeMake(56, 56) : CGSizeMake(30, 30);
    if (preview) c.imageProperties.cornerRadius = 6;
    cell.contentConfiguration = c;
    IPStyleCell(cell);
    if (_selectingFiles) {
        BOOL selectable = item.isRegular && !item.isLink;
        cell.accessoryType = selectable && [_selectedFiles containsObject:item.path]
            ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.selectionStyle = selectable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    } else if (_selectingBackups) {
        BOOL selectable = wq_backup_unit_deletable(item.path);
        cell.accessoryType = selectable && [_selectedBackups containsObject:item.path]
            ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.selectionStyle = selectable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    } else {
        cell.accessoryType = item.isDir ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    [self requestThumbnailForItem:item];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_gridView && !_error && !_scanInFlight && _items.count > 0) return 204;
    return UITableViewAutomaticDimension;
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_gridView) return nil;
    if (_error || indexPath.section != 0 || (NSUInteger)indexPath.row >= _items.count) return nil;
    if (_selectingFiles) {
        WQItem *item = _items[(NSUInteger)indexPath.row];
        return item.isRegular && !item.isLink ? indexPath : nil;
    }
    if (!_selectingBackups) return indexPath;
    WQItem *item = _items[(NSUInteger)indexPath.row];
    return wq_backup_unit_deletable(item.path) ? indexPath : nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_selectingFiles) {
        if (indexPath.section != 0 || (NSUInteger)indexPath.row >= _items.count) return;
        WQItem *selected = _items[(NSUInteger)indexPath.row];
        if (!selected.isRegular || selected.isLink) return;
        [_selectedFiles addObject:selected.path];
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self updateFileSelectionBar];
        return;
    }
    if (_selectingBackups) {
        if (indexPath.section != 0 || (NSUInteger)indexPath.row >= _items.count) return;
        WQItem *selected = _items[(NSUInteger)indexPath.row];
        if (!wq_backup_unit_deletable(selected.path)) return;
        [_selectedBackups addObject:selected.path];
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self updateBackupSelectionBar];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_error) return;
    if (indexPath.section != 0 || (NSUInteger)indexPath.row >= _items.count) return;
    WQItem *item = _items[(NSUInteger)indexPath.row];
    [self openItem:item];
}

- (void)openItem:(WQItem *)item
{
    UIViewController *next;
    if (item.isLink) {
        wq_alert(self, @"Symbolic link",
                 @"WQ Files does not follow symbolic links for viewing, sharing or editing. Use Copy Path to open the target explicitly.");
        return;
    }
    if (item.isDir) {
        WQDirViewController *dir = [[WQDirViewController alloc] initWithPath:item.path title:item.label ?: item.name];
        dir.readOnly = self.readOnly;
        next = dir;
    } else {
        if (!item.isRegular) {
            wq_alert(self, @"Cannot open this item", item.isLink
                     ? @"Symbolic links are not followed for viewing, sharing or editing."
                     : @"Only regular files can be viewed.");
            return;
        }
        _scanNeedsRefresh = YES;
        wq_open_file(self.navigationController, item.path, self.readOnly, WQOpenAuto);
        return;
    }
    [self.navigationController pushViewController:next animated:YES];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_selectingFiles) {
        if (indexPath.section == 0 && (NSUInteger)indexPath.row < _items.count) {
            [_selectedFiles removeObject:_items[(NSUInteger)indexPath.row].path];
            [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            [self updateFileSelectionBar];
        }
        return;
    }
    if (!_selectingBackups) return;
    if (indexPath.section != 0 || (NSUInteger)indexPath.row >= _items.count) return;
    WQItem *item = _items[(NSUInteger)indexPath.row];
    [_selectedBackups removeObject:item.path];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self updateBackupSelectionBar];
}

// Right-to-left reveals Delete. The opposite direction is intentionally
// non-destructive so the interactive navigation-back gesture cannot delete.
- (UISwipeActionsConfiguration *)deleteSwipeForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_gridView || _selectingFiles || _selectingBackups || _error) return nil;
    if (indexPath.section != 0 || (NSUInteger)indexPath.row >= _items.count) return nil;
    WQItem *item = _items[(NSUInteger)indexPath.row];
    BOOL backupUnit = item.isDir && wq_backup_unit_deletable(item.path);
    BOOL regular = !self.readOnly && !_backupStorage;
    if (!backupUnit && !regular) return nil;
    NSString *itemPath = [item.path copy];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"Delete" handler:^(UIContextualAction *__unused a, UIView *__unused view, void (^done)(BOOL)) {
        WQDirViewController *strongSelf = weakSelf;
        WQItem *current = nil;
        if (strongSelf && (NSUInteger)indexPath.row < strongSelf->_items.count &&
            [strongSelf->_items[(NSUInteger)indexPath.row].path isEqualToString:itemPath])
            current = strongSelf->_items[(NSUInteger)indexPath.row];
        // The row stays until the confirmed delete reloads the folder.
        done(NO);
        if (!current) return;
        if (backupUnit) [strongSelf confirmDeleteBackup:current];
        else [strongSelf confirmDelete:current];
    }];
    action.image = [UIImage systemImageNamed:@"trash"];
    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[action]];
    config.performsFirstActionWithFullSwipe = YES;
    return config;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [self deleteSwipeForRowAtIndexPath:indexPath];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_gridView || _selectingFiles || _selectingBackups || _error ||
        indexPath.section != 0 || (NSUInteger)indexPath.row >= _items.count) return nil;
    WQItem *item = _items[(NSUInteger)indexPath.row];
    if (item.isLink || (!item.isDir && !item.isRegular)) return nil;
    NSString *path = item.path.copy;
    BOOL directory = item.isDir;
    __weak typeof(self) weakSelf = self;
    UIContextualAction *share = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:@"Share" handler:^(UIContextualAction *__unused action, UIView *source, void (^done)(BOOL)) {
            WQDirViewController *strongSelf = weakSelf;
            done(strongSelf != nil);
            if (!strongSelf) return;
            if (directory) wq_share_folder(strongSelf, path, nil, source);
            else wq_share(strongSelf, path, source);
        }];
    share.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
    share.backgroundColor = IPAccent();
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[share]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point
{
    if (_selectingFiles || _selectingBackups || _error) return nil;
    if (indexPath.section != 0 || (NSUInteger)indexPath.row >= _items.count) return nil;
    WQItem *item = _items[(NSUInteger)indexPath.row];
    NSString *itemPath = [item.path copy];
    __weak typeof(self) weakSelf = self;
    WQItem *(^currentItem)(void) = ^WQItem *{
        WQDirViewController *strongSelf = weakSelf;
        if (!strongSelf || indexPath.section != 0 || (NSUInteger)indexPath.row >= strongSelf->_items.count) return nil;
        WQItem *current = strongSelf->_items[(NSUInteger)indexPath.row];
        return [current.path isEqualToString:itemPath] ? current : nil;
    };
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *__unused suggested) {
        WQItem *current = currentItem();
        WQDirViewController *strongSelf = weakSelf;
        if (!current || !strongSelf) return nil;
        NSMutableArray *actions = [NSMutableArray new];
        if (current.isDir) {
            BOOL starred = wq_location_is_starred(current.path);
            [actions addObject:[UIAction actionWithTitle:starred ? @"Remove from Starred" : @"Add to Starred"
                                                   image:[UIImage systemImageNamed:starred ? @"star.slash" : @"star"]
                                              identifier:nil handler:^(UIAction *__unused a) {
                WQItem *latest = currentItem();
                if (latest) wq_set_location_starred(latest.path, latest.label ?: latest.name, !starred);
            }]];
            [actions addObject:[UIAction actionWithTitle:@"Share as ZIP (AirDrop…)" image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                              identifier:nil handler:^(UIAction *__unused a) {
                WQItem *latest = currentItem();
                UITableViewCell *cell = [weakSelf.tableView cellForRowAtIndexPath:indexPath];
                if (latest && weakSelf) wq_share_folder(weakSelf, latest.path, nil, cell);
            }]];
        }
        if (!current.isDir && current.isRegular) {
            [actions addObject:[UIAction actionWithTitle:@"Share" image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                              identifier:nil handler:^(UIAction *__unused a) {
                WQItem *latest = currentItem();
                UITableViewCell *cell = [weakSelf.tableView cellForRowAtIndexPath:indexPath];
                if (latest && weakSelf) wq_share(weakSelf, latest.path, cell);
            }]];
            NSString *original = wq_backup_original_path(current.path);
            if (original) {
                [actions addObject:[UIAction actionWithTitle:@"Restore to Original Location"
                                                       image:[UIImage systemImageNamed:@"arrow.uturn.backward"]
                                                  identifier:nil handler:^(UIAction *__unused a) {
                    WQItem *latest = currentItem();
                    if (latest && weakSelf) [weakSelf restoreBackup:latest.path to:original];
                }]];
            }
        }
        if (!current.isDir && current.isRegular) {
            BOOL ro = weakSelf.readOnly;
            [actions addObject:[UIMenu menuWithTitle:@"Open As" image:[UIImage systemImageNamed:@"arrow.up.forward.app"] identifier:nil
                                             options:0 children:@[
                [UIAction actionWithTitle:@"Plist Editor" image:[UIImage systemImageNamed:@"list.bullet.indent"] identifier:nil
                                  handler:^(UIAction *__unused a) { WQDirViewController *strongSelf = weakSelf; WQItem *latest = currentItem(); if (strongSelf && latest) wq_open_file(strongSelf.navigationController, latest.path, ro, WQOpenPlist); }],
                [UIAction actionWithTitle:@"Text / Image" image:[UIImage systemImageNamed:@"doc.plaintext"] identifier:nil
                                  handler:^(UIAction *__unused a) { WQDirViewController *strongSelf = weakSelf; WQItem *latest = currentItem(); if (strongSelf && latest) wq_open_file(strongSelf.navigationController, latest.path, ro, WQOpenText); }],
                    [UIAction actionWithTitle:@"Image Viewer" image:[UIImage systemImageNamed:@"photo"] identifier:nil
                                  handler:^(UIAction *__unused a) { WQDirViewController *strongSelf = weakSelf; WQItem *latest = currentItem(); if (strongSelf && latest) wq_open_file(strongSelf.navigationController, latest.path, ro, WQOpenImage); }],
                [UIAction actionWithTitle:@"Hex Viewer" image:[UIImage systemImageNamed:@"number"] identifier:nil
                                  handler:^(UIAction *__unused a) { WQDirViewController *strongSelf = weakSelf; WQItem *latest = currentItem(); if (strongSelf && latest) wq_open_file(strongSelf.navigationController, latest.path, ro, WQOpenHex); }],
                [UIAction actionWithTitle:@"Media Player" image:[UIImage systemImageNamed:@"play.rectangle"] identifier:nil
                                  handler:^(UIAction *__unused a) { WQDirViewController *strongSelf = weakSelf; WQItem *latest = currentItem(); if (strongSelf && latest) wq_open_file(strongSelf.navigationController, latest.path, ro, WQOpenMedia); }],
                [UIAction actionWithTitle:@"Archive" image:[UIImage systemImageNamed:@"archivebox"] identifier:nil
                                  handler:^(UIAction *__unused a) { WQDirViewController *strongSelf = weakSelf; WQItem *latest = currentItem(); if (strongSelf && latest) wq_open_file(strongSelf.navigationController, latest.path, ro, WQOpenArchive); }],
                [UIAction actionWithTitle:@"SQLite Database" image:[UIImage systemImageNamed:@"cylinder"] identifier:nil
                                  handler:^(UIAction *__unused a) { WQDirViewController *strongSelf = weakSelf; WQItem *latest = currentItem(); if (strongSelf && latest) wq_open_file(strongSelf.navigationController, latest.path, ro, WQOpenDatabase); }],
            ]]];
        }
        if (!current.isLink && (current.isDir || current.isRegular)) {
            [actions addObject:[UIAction actionWithTitle:@"Copy to Transfer Shelf"
                                                   image:[UIImage systemImageNamed:@"doc.on.clipboard"]
                                              identifier:nil handler:^(UIAction *__unused action) {
                WQItem *latest = currentItem();
                if (latest) [weakSelf copyItemToTransferShelf:latest];
            }]];
            [actions addObject:[UIAction actionWithTitle:@"Info"
                                                   image:[UIImage systemImageNamed:@"info.circle"]
                                              identifier:nil handler:^(UIAction *__unused action) {
                WQItem *latest = currentItem();
                if (latest) [weakSelf showInfoForItem:latest];
            }]];
        }
        [actions addObject:[UIAction actionWithTitle:@"Copy Path" image:[UIImage systemImageNamed:@"doc.on.doc"]
                                          identifier:nil handler:^(UIAction *__unused a) {
            WQItem *latest = currentItem();
            if (latest) UIPasteboard.generalPasteboard.string = latest.path;
        }]];
        if (current.label) {
            [actions addObject:[UIAction actionWithTitle:@"Copy Identifier" image:[UIImage systemImageNamed:@"tag"]
                                              identifier:nil handler:^(UIAction *__unused a) {
                WQItem *latest = currentItem();
                if (latest) UIPasteboard.generalPasteboard.string = latest.bundleID ?: latest.label;
            }]];
        }
        if (current.isDir && wq_backup_unit_deletable(current.path)) {
            UIAction *remove = [UIAction actionWithTitle:@"Delete Backup…" image:[UIImage systemImageNamed:@"trash"]
                                              identifier:nil handler:^(UIAction *__unused a) {
                WQItem *latest = currentItem();
                if (latest) [weakSelf confirmDeleteBackup:latest];
            }];
            remove.attributes = UIMenuElementAttributesDestructive;
            [actions addObject:remove];
        }
        if (!strongSelf.readOnly && !strongSelf->_backupStorage) {
            if (!current.isLink && (current.isDir || current.isRegular))
                [actions addObject:[UIAction actionWithTitle:@"Duplicate"
                                                       image:[UIImage systemImageNamed:@"plus.square.on.square"]
                                                  identifier:nil handler:^(UIAction *__unused action) {
                    WQItem *latest = currentItem();
                    if (latest) [weakSelf duplicateItem:latest];
                }]];
            [actions addObject:[UIAction actionWithTitle:@"Rename" image:[UIImage systemImageNamed:@"pencil"]
                                              identifier:nil handler:^(UIAction *__unused a) { WQItem *latest = currentItem(); if (latest) [weakSelf promptRename:latest]; }]];
            UIAction *del = [UIAction actionWithTitle:@"Delete" image:[UIImage systemImageNamed:@"trash"]
                                           identifier:nil handler:^(UIAction *__unused a) { WQItem *latest = currentItem(); if (latest) [weakSelf confirmDelete:latest]; }];
            del.attributes = UIMenuElementAttributesDestructive;
            [actions addObject:del];
        }
        return [UIMenu menuWithChildren:actions];
    }];
}

#pragma mark Actions

- (void)showInfoForItem:(WQItem *)item
{
    NSString *type = item.isDir ? @"Folder" : (item.isRegular ? @"File" : @"Special item");
    NSString *date = wq_folder_date_text(item.modified);
    NSString *(^details)(NSString *) = ^NSString *(NSString *size) {
        return [NSString stringWithFormat:
            @"Type: %@\nSize: %@\nModified: %@\nOwner UID: %u\nMode: %04o%@\n\n%@",
            type, size, date.length ? date : @"Unknown", item.uid, item.mode & 07777,
            item.bundleID.length ? [NSString stringWithFormat:@"\nIdentifier: %@", item.bundleID] : @"", item.path];
    };
    if (!item.isDir) { wq_alert(self, item.label ?: item.name, details(wq_size_text(item.size))); return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.label ?: item.name
        message:details(@"Measuring folder…") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    NSString *path = item.path.copy;
    dispatch_async(wq_io(), ^{
        unsigned long long bytes = 0;
        WQMeasureResult result = wq_measure_tree(path, nil, &bytes);
        NSString *size = result == WQMeasureResultKnown ? wq_size_text(bytes) :
            (result == WQMeasureResultLimited ? [NSString stringWithFormat:@"At least %@ (some contents are inaccessible)", wq_size_text(bytes)] :
             (result == WQMeasureResultMissing ? @"Folder is no longer available" : @"Measurement cancelled"));
        dispatch_async(dispatch_get_main_queue(), ^{
            if (alert.presentingViewController) alert.message = details(size);
        });
    });
}

- (void)duplicateItem:(WQItem *)item
{
    NSString *extension = item.isDir ? @"" : item.name.pathExtension;
    NSString *stem = item.isDir || !extension.length ? item.name : item.name.stringByDeletingPathExtension;
    NSString *destination = nil;
    for (NSUInteger n = 1; n < 1000; n++) {
        NSString *suffix = n == 1 ? @" copy" : [NSString stringWithFormat:@" copy %lu", (unsigned long)n];
        NSString *name = [stem stringByAppendingString:suffix];
        if (extension.length) name = [name stringByAppendingPathExtension:extension];
        NSString *candidate = [_path stringByAppendingPathComponent:name];
        struct stat existing = {0};
        if (!wq_stat(candidate, &existing)) { destination = candidate; break; }
    }
    if (!destination.length) { wq_alert(self, @"Cannot duplicate", @"Could not choose a free destination name."); return; }
    NSString *source = [item.path copy];
    [self runIO:^BOOL(NSString **error) { return wq_copy_item(source, destination, error); }
          failure:@"Cannot duplicate item"];
}

- (void)runIO:(BOOL (^)(NSString **error))work failure:(NSString *)failureTitle
{
    dispatch_async(wq_io(), ^{
        NSString *error = nil;
        BOOL ok = work(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) wq_alert(self, failureTitle, error ?: @"Unknown error");
            [self reload];
        });
    });
}

- (void)promptNewFolder
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Folder" message:_path
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"Name"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused a) {
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0 || [name containsString:@"/"]) return;
        NSString *path = [self->_path stringByAppendingPathComponent:name];
        [self runIO:^BOOL(NSString **error) { return wq_create_dir(path, error); } failure:@"Cannot create folder"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptRename:(WQItem *)item
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename" message:item.path
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = item.name; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused a) {
        NSString *name = alert.textFields.firstObject.text;
        [self runIO:^BOOL(NSString **error) { return wq_rename(item.path, name, error); } failure:@"Cannot rename"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDeleteBackup:(WQItem *)item
{
    BOOL bundle = [item.path.stringByDeletingLastPathComponent isEqualToString:wq_app_backup_root()];
    NSString *message = bundle
        ? [NSString stringWithFormat:@"%@\n\nThis removes every backup for this app. It cannot be undone.", item.path]
        : [NSString stringWithFormat:@"%@\n\nThis removes the selected backup. It cannot be undone.", item.path];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete backup?"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *__unused a) {
        [self runIO:^BOOL(NSString **error) { return wq_delete_backup(item.path, error); } failure:@"Cannot delete backup"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDelete:(WQItem *)item
{
    NSString *message;
    if (item.isLink) {
        message = [NSString stringWithFormat:@"%@\n\nRemoves the symbolic link only; its target is not changed.", item.path];
    } else if (item.isDir) {
        message = [NSString stringWithFormat:@"%@\n\nOnly empty folders can be deleted.", item.path];
    } else if (item.isRegular) {
        message = [NSString stringWithFormat:@"%@\n\nA copy is kept in Backups.", item.path];
    } else {
        message = [NSString stringWithFormat:@"%@\n\nThis special file is removed; no backup is kept.", item.path];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Delete \"%@\"?", item.name]
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *__unused a) {
        [self runIO:^BOOL(NSString **error) { return wq_delete(item.path, error); } failure:@"Cannot delete"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)restoreBackup:(NSString *)backup to:(NSString *)original
{
    NSString *message = [NSString stringWithFormat:@"Write this backup back to\n%@?\n\nIf a file is there now, it is backed up first.", original];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restore" message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *__unused a) {
        [self runIO:^BOOL(NSString **error) {
            struct stat st;
            return wq_stat(original, &st) ? wq_write_from_file(original, backup, error)
                                          : wq_create_file_from(original, backup, error);
        } failure:@"Restore failed"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)importFile
{
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    // The picker hands over a local copy (asCopy). It is streamed into place,
    // never read into memory, and the existence check runs off the main thread.
    NSString *source = urls.firstObject.path;
    if (!source) return;
    NSString *dest = [_path stringByAppendingPathComponent:source.lastPathComponent];
    void (^cleanup)(void) = ^{ [NSFileManager.defaultManager removeItemAtPath:source error:nil]; };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        struct stat st;
        BOOL exists = wq_stat(dest, &st);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!exists) {
                [self runIO:^BOOL(NSString **error) {
                    BOOL ok = wq_create_file_from(dest, source, error);
                    cleanup();
                    return ok;
                } failure:@"Import failed"];
                return;
            }
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Replace existing file?"
                message:[NSString stringWithFormat:@"%@ already exists. It is backed up before being replaced.", dest]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel
                                                    handler:^(UIAlertAction *__unused a) { cleanup(); }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Replace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *__unused a) {
                [self runIO:^BOOL(NSString **error) {
                    BOOL ok = wq_write_from_file(dest, source, error);
                    cleanup();
                    return ok;
                } failure:@"Import failed"];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    });
}

@end

#pragma mark - Starred locations

@interface WQStarredViewController : UITableViewController
@end

@implementation WQStarredViewController {
    NSArray<NSDictionary<NSString *, NSString *> *> *_locations;
}

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Starred";
    self.tableView.backgroundColor = IPBackground();
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    _locations = wq_starred_locations();
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return MAX((NSInteger)1, (NSInteger)_locations.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"starred"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"starred"];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    if (_locations.count == 0) {
        content.text = @"No starred folders yet";
        content.secondaryText = @"Open a folder and tap the star in the navigation bar, or long-press a folder.";
        content.secondaryTextProperties.numberOfLines = 0;
        content.image = [UIImage systemImageNamed:@"star"];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        NSDictionary *item = _locations[(NSUInteger)indexPath.row];
        content.text = item[@"name"];
        content.secondaryText = item[@"path"];
        content.secondaryTextProperties.numberOfLines = 2;
        content.image = [UIImage systemImageNamed:@"folder.fill"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    content.textProperties.color = IPPrimaryText();
    content.secondaryTextProperties.color = IPSecondaryText();
    content.imageProperties.tintColor = IPAccent();
    cell.contentConfiguration = content;
    IPStyleCell(cell);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ((NSUInteger)indexPath.row >= _locations.count) return;
    NSDictionary *item = _locations[(NSUInteger)indexPath.row];
    [self.navigationController pushViewController:[[WQDirViewController alloc] initWithPath:item[@"path"] title:item[@"name"]]
                                         animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ((NSUInteger)indexPath.row >= _locations.count) return nil;
    NSDictionary *item = _locations[(NSUInteger)indexPath.row];
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"Remove" handler:^(UIContextualAction *__unused action, UIView *__unused view, void (^done)(BOOL)) {
        wq_set_location_starred(item[@"path"], item[@"name"], NO);
        self->_locations = wq_starred_locations();
        [self.tableView reloadData];
        done(YES);
    }];
    remove.image = [UIImage systemImageNamed:@"star.slash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}

@end

#pragma mark - System groups

// The SystemGroup parent gets no token on 27.0.1, so it cannot be listed.
// Known container names are checked one by one (lstat works without access).
@interface WQSystemGroupsViewController : UITableViewController
@end

@implementation WQSystemGroupsViewController {
    NSArray<NSString *> *_names;
    BOOL _listed;
}

static NSString *const kSystemGroupRoot = @"/private/var/containers/Shared/SystemGroup";

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"System Groups";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                           target:self action:@selector(tryName)];
    dispatch_async(wq_io(), ^{
        NSArray *listed = wq_list(kSystemGroupRoot, NULL);
        NSArray *names = listed;
        if (!names) {
            NSArray *known = @[
                @"systemgroup.com.apple.configurationprofiles", @"systemgroup.com.apple.mobilegestaltcache",
                @"systemgroup.com.apple.osanalytics", @"systemgroup.com.apple.lsd.iconscache",
                @"systemgroup.com.apple.lsd.identifiers", @"systemgroup.com.apple.ManagedSettings",
                @"systemgroup.com.apple.sharedpclogging", @"systemgroup.com.apple.media.shared.books",
                @"systemgroup.com.apple.nsurlstoragedresources", @"systemgroup.com.apple.pisco.suinfo",
                @"systemgroup.com.apple.icloud.findmydevice.managed", @"systemgroup.com.apple.mobilestoragemounter",
                @"systemgroup.com.apple.mobileactivationd", @"systemgroup.com.apple.sensorkit",
                @"systemgroup.com.apple.powerlog", @"systemgroup.com.apple.diagnosticextensionsd",
                @"systemgroup.com.apple.mediaanalysisd", @"systemgroup.com.apple.translationd",
                @"systemgroup.com.apple.chronod", @"systemgroup.com.apple.coreaudio",
                @"systemgroup.com.apple.ManagedConfiguration.ExternalTrust", @"systemgroup.com.apple.cfprefsd",
            ];
            NSMutableArray *found = [NSMutableArray new];
            for (NSString *name in known) {
                struct stat st;
                NSString *p = [kSystemGroupRoot stringByAppendingPathComponent:name];
                if (lstat(p.fileSystemRepresentation, &st) == 0) [found addObject:name];
            }
            names = found;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_listed = listed != nil;
            self->_names = [names sortedArrayUsingSelector:@selector(compare:)];
            [self.tableView reloadData];
        });
    });
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (!_names) return @"Loading…";
    return _listed ? nil : @"This folder cannot be listed on this iOS version. Known names that exist are shown; tap + to try another name.";
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    if (![view isKindOfClass:UITableViewHeaderFooterView.class]) return;
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    header.textLabel.font = IPPixelUIEnabled() ? IPFont(15, UIFontWeightBold) : IPTextFont(UIFontTextStyleHeadline);
    header.textLabel.textColor = IPSecondaryText();
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section
{
    if (![view isKindOfClass:UITableViewHeaderFooterView.class]) return;
    UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
    footer.textLabel.font = IPPixelUIEnabled() ? IPFont(11, UIFontWeightRegular) : IPTextFont(UIFontTextStyleFootnote);
    footer.textLabel.textColor = IPSecondaryText();
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)_names.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"g"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"g"];
    UIListContentConfiguration *c = cell.defaultContentConfiguration;
    c.text = [_names[(NSUInteger)indexPath.row] stringByReplacingOccurrencesOfString:@"systemgroup." withString:@""];
    c.image = [UIImage systemImageNamed:@"folder.fill"];
    c.textProperties.color = IPPrimaryText();
    c.imageProperties.tintColor = IPAccent();
    cell.contentConfiguration = c;
    IPStyleCell(cell);
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *name = _names[(NSUInteger)indexPath.row];
    [self.navigationController pushViewController:[[WQDirViewController alloc]
        initWithPath:[kSystemGroupRoot stringByAppendingPathComponent:name] title:nil] animated:YES];
}

- (void)tryName
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Open System Group" message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.text = @"systemgroup.com.apple.";
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Open" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused a) {
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0 || [name containsString:@"/"]) return;
        NSString *path = [kSystemGroupRoot stringByAppendingPathComponent:name];
        struct stat st;
        if (lstat(path.fileSystemRepresentation, &st) != 0) {
            wq_alert(self, @"Not found", path);
            return;
        }
        [self.navigationController pushViewController:[[WQDirViewController alloc] initWithPath:path title:nil] animated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - Log

@interface WQLogViewController : UIViewController
@end

@implementation WQLogViewController {
    UITextView *_textView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Log";
    self.view.backgroundColor = IPBackground();
    _textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _textView.editable = NO;
    _textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _textView.backgroundColor = IPBackground();
    _textView.textColor = IPPrimaryText();
    [self.view addSubview:_textView];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                           target:self action:@selector(share:)];
}

// App version, device and iOS first, so a Log someone sends in says where it
// came from.
- (NSString *)fullLog
{
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return [NSString stringWithFormat:@"iPixel-Files %@ (%@)\n%@\n\n%@",
            info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?", wq_device_line(), wq_log_text()];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    _textView.text = [self fullLog];
}

- (void)share:(UIBarButtonItem *)sender
{
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[self fullLog]]
                                                                        applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:share animated:YES completion:nil];
}

@end

#pragma mark - Navigation

// Adds a Home button next to Back on screens two or more levels deep. Editors
// guard Back, Home and the interactive edge swipe through WQUnsavedEditing.
@interface WQNavigationController : UINavigationController <UINavigationControllerDelegate, UIGestureRecognizerDelegate>
@end

@implementation WQNavigationController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.delegate = self;
    self.interactivePopGestureRecognizer.delegate = self;
}

- (void)navigationController:(UINavigationController *)nav willShowViewController:(UIViewController *)vc animated:(BOOL)animated
{
    NSUInteger depth = [nav.viewControllers indexOfObject:vc];
    if (depth == NSNotFound || depth < 2) {
        if (vc.navigationItem.leftBarButtonItem.tag == 0x484f4d45) vc.navigationItem.leftBarButtonItem = nil;
        return;
    }
    if (vc.navigationItem.leftBarButtonItem) return;
    UIBarButtonItem *home = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"house"]
                                                             style:UIBarButtonItemStylePlain target:self action:@selector(goHome)];
    home.tag = 0x484f4d45;   // "HOME"
    home.accessibilityLabel = @"Home";
    vc.navigationItem.leftItemsSupplementBackButton = YES;
    vc.navigationItem.leftBarButtonItem = home;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer != self.interactivePopGestureRecognizer) return YES;
    if (self.viewControllers.count <= 1) return NO;
    UIViewController<WQUnsavedEditing> *editor = (UIViewController<WQUnsavedEditing> *)self.topViewController;
    if (![editor conformsToProtocol:@protocol(WQUnsavedEditing)] || !editor.wq_needsLeaveConfirmation) return YES;
    __weak typeof(self) weakSelf = self;
    [editor confirmLeaveThen:^{ [weakSelf popViewControllerAnimated:YES]; }];
    return NO;
}

- (void)goHome
{
    UIViewController<WQUnsavedEditing> *top = (UIViewController<WQUnsavedEditing> *)self.topViewController;
    __weak typeof(self) weakSelf = self;
    void (^home)(void) = ^{ [weakSelf popToRootViewControllerAnimated:YES]; };
    if ([top conformsToProtocol:@protocol(WQUnsavedEditing)]) [top confirmLeaveThen:home];
    else home();
}

@end

#pragma mark - Root

@interface WQDualBrowserViewController : UIViewController
@end

@implementation WQDualBrowserViewController {
    UINavigationController *_leftPane;
    UINavigationController *_rightPane;
    UISegmentedControl *_panePicker;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Dual Browser";
    self.view.backgroundColor = IPBackground();
    WQDirViewController *left = [[WQDirViewController alloc]
        initWithPath:@"/private/var/mobile/Containers/Data/Application" title:@"Left · App Data"];
    WQDirViewController *right = [[WQDirViewController alloc]
        initWithPath:@"/private/var/mobile/Containers/Shared/AppGroup" title:@"Right · App Groups"];
    _leftPane = [[WQNavigationController alloc] initWithRootViewController:left];
    _rightPane = [[WQNavigationController alloc] initWithRootViewController:right];
    for (UINavigationController *pane in @[_leftPane, _rightPane]) {
        [self addChildViewController:pane];
        [self.view addSubview:pane.view];
        [pane didMoveToParentViewController:self];
        pane.view.layer.borderWidth = 1;
        pane.view.layer.borderColor = IPSeparator().CGColor;
    }
    _panePicker = [[UISegmentedControl alloc] initWithItems:@[@"LEFT", @"RIGHT"]];
    _panePicker.selectedSegmentIndex = 0;
    [_panePicker addTarget:self action:@selector(switchPane) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _panePicker;
}

- (void)switchPane
{
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    BOOL sideBySide = CGRectGetWidth(bounds) >= 700;
    _panePicker.hidden = sideBySide;
    if (sideBySide) {
        CGFloat gap = 8;
        CGFloat width = floor((CGRectGetWidth(bounds) - gap) / 2.0);
        _leftPane.view.hidden = NO;
        _rightPane.view.hidden = NO;
        _leftPane.view.frame = CGRectMake(0, 0, width, CGRectGetHeight(bounds));
        _rightPane.view.frame = CGRectMake(width + gap, 0, CGRectGetWidth(bounds) - width - gap, CGRectGetHeight(bounds));
    } else {
        BOOL showLeft = _panePicker.selectedSegmentIndex == 0;
        _leftPane.view.hidden = !showLeft;
        _rightPane.view.hidden = showLeft;
        _leftPane.view.frame = bounds;
        _rightPane.view.frame = bounds;
    }
}

@end

static void ip_sync_alternate_icon(void)
{
    UIApplication *application = UIApplication.sharedApplication;
    if (!application.supportsAlternateIcons) return;
    NSString *wanted = IPSelectedTheme() == IPThemeStyleLime ? @"LimeIcon" : nil;
    NSString *current = application.alternateIconName;
    if ((wanted == nil && current == nil) || [wanted isEqualToString:current]) return;
    [application setAlternateIconName:wanted completionHandler:^(NSError *error) {
        if (error) NSLog(@"Could not update themed app icon: %@", error.localizedDescription);
    }];
}

// Eight-by-eight glyphs keep dashboard/tool symbols genuinely pixel drawn in
// Pixel mode. Blue and Lime continue to use the familiar SF Symbol set.
static UIImage *ip_pixel_glyph(NSString *symbol)
{
    if (!IPPixelUIEnabled()) return [UIImage systemImageNamed:symbol];
    NSDictionary<NSString *, NSArray<NSString *> *> *glyphs = @{
        @"square.grid.2x2": @[@"00000000",@"01100110",@"01100110",@"00000000",@"01100110",@"01100110",@"00000000",@"00000000"],
        @"square.stack.3d.up": @[@"00011000",@"00111100",@"01100110",@"00111100",@"01100110",@"00111100",@"00011000",@"00000000"],
        @"puzzlepiece.extension": @[@"00011000",@"00111100",@"01111110",@"11111111",@"11100111",@"01111110",@"00111100",@"00011000"],
        @"gearshape.2": @[@"00100100",@"01111110",@"11111111",@"11011011",@"11011011",@"11111111",@"01111110",@"00100100"],
        @"cpu": @[@"01011010",@"00111100",@"01111110",@"11011011",@"11011011",@"01111110",@"00111100",@"01011010"],
        @"lock.square.stack": @[@"00111100",@"01100110",@"01100110",@"11111111",@"11011011",@"11011011",@"11111111",@"00000000"],
        @"trash": @[@"00111100",@"01111110",@"00111100",@"00111100",@"00111100",@"00111100",@"00111100",@"00000000"],
        @"arrow.right.circle": @[@"00011000",@"00001100",@"11111110",@"11111111",@"11111110",@"00001100",@"00011000",@"00000000"],
        @"clock.arrow.circlepath": @[@"00111100",@"01100110",@"11011011",@"11011011",@"11000011",@"01100110",@"00111100",@"00000110"],
        @"doc.plaintext": @[@"01111100",@"01000110",@"01000011",@"01011111",@"01000001",@"01011111",@"01111111",@"00000000"],
        @"rectangle.split.2x1": @[@"11111111",@"10011001",@"10011001",@"10011001",@"10011001",@"10011001",@"11111111",@"00000000"],
        @"star.fill": @[@"00011000",@"01011010",@"00111100",@"11111111",@"01111110",@"00111100",@"01100110",@"01000010"],
        @"magnifyingglass": @[@"00111100",@"01100110",@"11000011",@"11000011",@"01100110",@"00111100",@"00011000",@"00001100"],
        @"folder.fill": @[@"00000000",@"01110000",@"11111110",@"11111111",@"11111111",@"11111111",@"01111110",@"00000000"],
        @"doc": @[@"01111000",@"01001100",@"01000110",@"01000010",@"01000010",@"01000010",@"01111110",@"00000000"],
    };
    NSArray<NSString *> *rows = glyphs[symbol] ?: glyphs[@"doc.plaintext"];
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    format.scale = 1;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32, 32) format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextSetFillColorWithColor(context.CGContext, UIColor.whiteColor.CGColor);
        for (NSUInteger y = 0; y < rows.count; y++) {
            NSString *row = rows[y];
            for (NSUInteger x = 0; x < MIN((NSUInteger)8, row.length); x++)
                if ([row characterAtIndex:x] == '1') CGContextFillRect(context.CGContext, CGRectMake(x * 4, y * 4, 4, 4));
        }
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@interface IPAppearanceSettingsViewController : UITableViewController
@end

@implementation IPAppearanceSettingsViewController

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.title = @"Appearance";
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 3 : 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return section == 0 ? @"Interface style" : @"Color appearance";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return section == 0
        ? @"The selected design is applied to the dashboard, file browser, app manager, cache cleaner, editors, search and nested menus."
        : @"System follows the iPhone setting. Light and Dark keep the selected appearance at all times.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"theme"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"theme"];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    if (indexPath.section == 0) {
        NSArray *names = @[@"iPixel Blue", @"iPixel Lime", @"iPixel Pixel"];
        NSArray *details = @[@"Clean navy, electric blue and ice surfaces",
                             @"Charcoal, lime and soft utility cards",
                             @"Crisp pixel edges, retro color and monospaced type"];
        NSArray<NSNumber *> *values = @[@(IPThemeStyleBlue), @(IPThemeStyleLime), @(IPThemeStylePixel)];
        content.text = names[(NSUInteger)indexPath.row];
        content.secondaryText = details[(NSUInteger)indexPath.row];
        NSArray *symbols = @[@"folder.fill", @"sparkles", @"square.grid.3x3.fill"];
        content.image = [UIImage systemImageNamed:symbols[(NSUInteger)indexPath.row]];
        cell.accessoryType = IPSelectedTheme() == values[(NSUInteger)indexPath.row].integerValue
            ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else {
        NSArray *names = @[@"System", @"Light", @"Dark"];
        NSArray *symbols = @[@"circle.lefthalf.filled", @"sun.max.fill", @"moon.stars.fill"];
        content.text = names[(NSUInteger)indexPath.row];
        content.image = [UIImage systemImageNamed:symbols[(NSUInteger)indexPath.row]];
        cell.accessoryType = IPSelectedAppearance() == indexPath.row ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    content.textProperties.color = IPPrimaryText();
    content.secondaryTextProperties.color = IPSecondaryText();
    content.imageProperties.tintColor = IPAccent();
    cell.contentConfiguration = content;
    IPStyleCell(cell);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        NSArray<NSNumber *> *values = @[@(IPThemeStyleBlue), @(IPThemeStyleLime), @(IPThemeStylePixel)];
        [NSUserDefaults.standardUserDefaults setInteger:values[(NSUInteger)indexPath.row].integerValue
                                                 forKey:IPThemeStyleDefaultsKey];
    }
    else
        [NSUserDefaults.standardUserDefaults setInteger:indexPath.row forKey:IPAppearanceModeDefaultsKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    ip_sync_alternate_icon();
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:IPThemeDidChangeNotification object:nil];
    });
}

@end

@interface WQGlobalSearchViewController : UITableViewController <UISearchResultsUpdating>
@end

@implementation WQGlobalSearchViewController {
    NSArray<NSDictionary<NSString *, id> *> *_results;
    WQScanCancellation *_cancellation;
    NSUInteger _generation;
    NSString *_status;
}

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.title = @"Global Search";
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.backgroundColor = IPBackground();
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = @"Search visited and saved locations";
    search.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    search.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    IPStyleSearchBar(search.searchBar);
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    _status = @"Type at least two characters to search across accessible locations.";
}

- (NSArray<NSString *> *)searchRoots
{
    NSMutableArray<NSString *> *candidates = [NSMutableArray new];
    for (NSDictionary *item in wq_recent_items(YES)) [candidates addObject:item[@"path"]];
    for (NSDictionary *item in wq_starred_locations()) [candidates addObject:item[@"path"]];
    [candidates addObjectsFromArray:@[wq_backup_root(), wq_app_backup_root()]];
    NSMutableArray<NSString *> *roots = [NSMutableArray new];
    for (NSString *candidate in candidates) {
        if (!candidate.length) continue;
        BOOL covered = NO;
        for (NSString *root in roots)
            if ([candidate isEqualToString:root] || [candidate hasPrefix:[root stringByAppendingString:@"/"]]) { covered = YES; break; }
        if (!covered) [roots addObject:candidate];
        if (roots.count == 16) break;
    }
    return roots;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    NSString *query = [searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [_cancellation cancel];
    _cancellation = [WQScanCancellation new];
    NSUInteger generation = ++_generation;
    if (query.length < 2) {
        _results = nil; _status = @"Type at least two characters to search across accessible locations.";
        [self.tableView reloadData]; return;
    }
    NSArray<NSString *> *roots = [self searchRoots];
    if (roots.count == 0) {
        _results = nil; _status = @"No search roots yet. Open or star folders first, then search again.";
        [self.tableView reloadData]; return;
    }
    _results = nil; _status = @"Searching accessible folders…"; [self.tableView reloadData];
    WQScanCancellation *cancellation = _cancellation;
    dispatch_async(wq_io(), ^{
        NSMutableArray<NSDictionary *> *queue = [NSMutableArray new];
        for (NSString *root in roots) [queue addObject:@{@"path": root, @"depth": @0}];
        NSMutableSet<NSString *> *visited = [NSMutableSet new];
        NSMutableArray *matches = [NSMutableArray new];
        NSUInteger examined = 0;
        while (queue.count && !cancellation.isCancelled && examined < 25000 && matches.count < 300) {
            NSDictionary *entry = queue.firstObject; [queue removeObjectAtIndex:0];
            NSString *dir = entry[@"path"];
            NSUInteger depth = [entry[@"depth"] unsignedIntegerValue];
            if ([visited containsObject:dir]) continue;
            [visited addObject:dir];
            NSArray<NSString *> *names = wq_list(dir, NULL);
            for (NSString *name in names) {
                if (cancellation.isCancelled) break;
                examined++;
                NSString *path = [dir stringByAppendingPathComponent:name];
                struct stat st;
                if (!wq_stat(path, &st) || S_ISLNK(st.st_mode)) continue;
                BOOL folder = S_ISDIR(st.st_mode);
                if ([name rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound)
                    [matches addObject:@{@"name": name, @"path": path, @"folder": @(folder)}];
                if (folder && depth < 10) [queue addObject:@{@"path": path, @"depth": @(depth + 1)}];
                if (examined >= 25000 || matches.count >= 300) break;
            }
        }
        BOOL limited = examined >= 25000 || matches.count >= 300;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_generation || cancellation.isCancelled) return;
            self->_results = matches;
            self->_status = matches.count ? (limited ? @"Showing the first matches; the safety limit was reached." : nil)
                                          : @"No matching files or folders in accessible locations.";
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{ return _results.count ? (NSInteger)_results.count : 1; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"global"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"global"];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    if (!_results.count) {
        content.text = _status;
        content.textProperties.numberOfLines = 0;
        content.image = [UIImage systemImageNamed:@"magnifyingglass"];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        NSDictionary *item = _results[(NSUInteger)indexPath.row];
        content.text = item[@"name"];
        content.secondaryText = item[@"path"];
        content.secondaryTextProperties.numberOfLines = 2;
        content.image = [UIImage systemImageNamed:[item[@"folder"] boolValue] ? @"folder.fill" : @"doc"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    content.textProperties.color = IPPrimaryText(); content.secondaryTextProperties.color = IPSecondaryText();
    content.imageProperties.tintColor = IPAccent(); cell.contentConfiguration = content; IPStyleCell(cell); return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ((NSUInteger)indexPath.row >= _results.count) return;
    NSDictionary *item = _results[(NSUInteger)indexPath.row]; NSString *path = item[@"path"];
    if ([item[@"folder"] boolValue])
        [self.navigationController pushViewController:[[WQDirViewController alloc] initWithPath:path title:item[@"name"]] animated:YES];
    else wq_open_file(self.navigationController, path, NO, WQOpenAuto);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{ return @"Search covers recently visited and starred folder trees that the sandbox escape has already made accessible. Undiscovered container parents cannot be listed globally by iOS."; }
@end

@interface WQRootViewController : UITableViewController
@end

@implementation WQRootViewController {
    NSArray<NSArray<NSString *> *> *_locations;  // title, path, symbol
    NSArray<NSDictionary<NSString *, NSString *> *> *_recentFolders;
    NSArray<NSDictionary<NSString *, NSString *> *> *_recentFiles;
    UIBarButtonItem *_clearRecentsItem;
    CGFloat _dashboardWidth;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title = @"iPixel-Files";
        _locations = @[
            @[@"App Data", @"/private/var/mobile/Containers/Data/Application", @"square.grid.2x2"],
            @[@"App Groups", @"/private/var/mobile/Containers/Shared/AppGroup", @"square.stack.3d.up"],
            @[@"Extension Data", @"/private/var/mobile/Containers/Data/PluginKitPlugin", @"puzzlepiece.extension"],
            @[@"Internal Daemons", @"/private/var/mobile/Containers/Data/InternalDaemon", @"gearshape.2"],
        ];
        if (wq_system_areas_reachable())
            _locations = [_locations arrayByAddingObject:@[@"System Data", @"/private/var/containers/Data/System", @"cpu"]];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.navigationItem.backButtonTitle = @"Home";
    UIBarButtonItem *appearance = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"paintpalette.fill"]
        style:UIBarButtonItemStylePlain target:self action:@selector(openAppearanceSettings)];
    appearance.accessibilityLabel = @"Appearance";
    _clearRecentsItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"clock.badge.xmark"]
        style:UIBarButtonItemStylePlain target:self action:@selector(confirmClearRecents)];
    _clearRecentsItem.accessibilityLabel = @"Clear Recents";
    self.navigationItem.rightBarButtonItems = @[appearance, _clearRecentsItem];
    self.tableView.backgroundColor = IPBackground();
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 84;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.tableFooterView = [self authorFooter];
    [self rebuildDashboard];
    [self refreshRecents];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshRecents)
        name:WQRecentsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(rebuildDashboard)
        name:UIContentSizeCategoryDidChangeNotification object:nil];
    dispatch_async(wq_io(), ^{
        NSString *recovery = wq_recover_interrupted_restore();
        if (recovery) {
            dispatch_async(dispatch_get_main_queue(), ^{
                wq_alert(self, @"Restore recovery", recovery);
            });
        }
        NSString *group = wq_app_group();
        if (!group) {
            dispatch_async(dispatch_get_main_queue(), ^{
                wq_alert(self, @"No App Group",
                         @"This app needs an App Group to reach other folders. Re-sign it with a tool that keeps the App Group entitlement.");
            });
        }
    });
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshRecents];
}

- (void)refreshRecents
{
    _recentFolders = wq_recent_items(YES);
    _recentFiles = wq_recent_items(NO);
    _clearRecentsItem.enabled = _recentFolders.count + _recentFiles.count > 0;
    [self.tableView reloadData];
}

- (void)confirmClearRecents
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear all recents?"
        message:@"This removes folder and file history only. It does not delete any files."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *__unused action) { wq_clear_recents(); }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openAppearanceSettings
{
    [self.navigationController pushViewController:[IPAppearanceSettingsViewController new] animated:YES];
}

// Auto Layout owns the cards; the header is remeasured for rotation and Dynamic Type.
- (UILabel *)dashboardLabel:(NSString *)text style:(UIFontTextStyle)style color:(UIColor *)color
{
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = IPTextFont(style);
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (void)openContainerCard:(UIButton *)sender
{
    NSUInteger index = (NSUInteger)sender.tag;
    UIViewController *next = index < _locations.count
        ? [[WQDirViewController alloc] initWithPath:_locations[index][1] title:_locations[index][0]]
        : [WQSystemGroupsViewController new];
    [self.navigationController pushViewController:next animated:YES];
}

- (void)rebuildDashboard
{
    CGFloat width = MAX(self.tableView.bounds.size.width, 320);
    _dashboardWidth = width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 1)];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12],
    ]];
    UIView *hero = [UIView new];
    hero.backgroundColor = IPElevatedSurface();
    hero.layer.cornerCurve = kCACornerCurveContinuous;
    hero.layer.cornerRadius = IPCornerRadius(28);
    UIView *heroFolders = wq_folder_stack_view(CGSizeMake(104, 104), YES);
    UILabel *heroTitle = [self dashboardLabel:@"Your files, beautifully organized."
        style:UIFontTextStyleTitle2 color:IPPrimaryText()];
    heroTitle.font = IPFont(20, UIFontWeightBold);
    UILabel *heroDetail = [self dashboardLabel:@"Explore containers, manage storage and keep every change protected."
        style:UIFontTextStyleFootnote color:IPSecondaryText()];
    UIStackView *heroCopy = [[UIStackView alloc] initWithArrangedSubviews:@[heroTitle, heroDetail]];
    heroCopy.axis = UILayoutConstraintAxisVertical;
    heroCopy.spacing = 7;
    UIStackView *heroRow = [[UIStackView alloc] initWithArrangedSubviews:@[heroCopy, heroFolders]];
    heroRow.axis = UILayoutConstraintAxisHorizontal;
    heroRow.alignment = UIStackViewAlignmentCenter;
    heroRow.spacing = 10;
    heroRow.translatesAutoresizingMaskIntoConstraints = NO;
    [hero addSubview:heroRow];
    [NSLayoutConstraint activateConstraints:@[
        [heroRow.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:22],
        [heroRow.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-14],
        [heroRow.topAnchor constraintEqualToAnchor:hero.topAnchor constant:16],
        [heroRow.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-16],
    ]];
    [stack addArrangedSubview:hero];

    UIButtonConfiguration *path = [UIButtonConfiguration filledButtonConfiguration];
    path.title = @"Go to a folder or file";
    path.subtitle = @"Open an absolute path";
    path.image = ip_pixel_glyph(@"arrow.right.circle");
    if (IPPixelUIEnabled()) {
        path.attributedTitle = [[NSAttributedString alloc] initWithString:path.title
            attributes:@{NSFontAttributeName: IPFont(15, UIFontWeightBold)}];
        path.attributedSubtitle = [[NSAttributedString alloc] initWithString:path.subtitle
            attributes:@{NSFontAttributeName: IPFont(11, UIFontWeightRegular)}];
    }
    path.imagePlacement = NSDirectionalRectEdgeTrailing;
    path.imagePadding = 16;
    path.baseBackgroundColor = IPSurface();
    path.baseForegroundColor = IPAccent();
    path.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    path.contentInsets = NSDirectionalEdgeInsetsMake(18, 20, 18, 20);
    UIButton *pathButton = [UIButton buttonWithConfiguration:path primaryAction:nil];
    pathButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [pathButton addTarget:self action:@selector(goToPath) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:pathButton];

    UIView *storage = [UIView new];
    storage.backgroundColor = IPSurface();
    storage.layer.cornerRadius = IPCornerRadius(26);
    UIStackView *storageStack = [UIStackView new];
    storageStack.axis = UILayoutConstraintAxisVertical;
    storageStack.spacing = 10;
    storageStack.translatesAutoresizingMaskIntoConstraints = NO;
    [storage addSubview:storageStack];
    [NSLayoutConstraint activateConstraints:@[
        [storageStack.leadingAnchor constraintEqualToAnchor:storage.leadingAnchor constant:22],
        [storageStack.trailingAnchor constraintEqualToAnchor:storage.trailingAnchor constant:-22],
        [storageStack.topAnchor constraintEqualToAnchor:storage.topAnchor constant:22],
        [storageStack.bottomAnchor constraintEqualToAnchor:storage.bottomAnchor constant:-22],
    ]];
    [storageStack addArrangedSubview:[self dashboardLabel:@"ON THIS DEVICE"
        style:UIFontTextStyleCaption1 color:IPAccent()]];
    UILabel *capacity = [self dashboardLabel:@"Reading storage…" style:UIFontTextStyleTitle2 color:IPPrimaryText()];
    [storageStack addArrangedSubview:capacity];
    UIProgressView *progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progress.progressTintColor = IPAccent();
    progress.trackTintColor = IPTrack();
    [storageStack addArrangedSubview:progress];
    UILabel *detail = [self dashboardLabel:@"Device storage" style:UIFontTextStyleCaption1 color:IPSecondaryText()];
    [storageStack addArrangedSubview:detail];
    [stack addArrangedSubview:storage];
    dispatch_async(wq_io(), ^{
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
        unsigned long long total = [attributes[NSFileSystemSize] unsignedLongLongValue];
        unsigned long long free = MIN(total, [attributes[NSFileSystemFreeSize] unsignedLongLongValue]);
        dispatch_async(dispatch_get_main_queue(), ^{
            capacity.text = total ? [NSString stringWithFormat:@"%@ available", wq_size_text(free)] : @"Storage unavailable";
            progress.progress = total ? (float)((double)(total - free) / total) : 0;
            detail.text = total ? [NSString stringWithFormat:@"%@ of %@ used", wq_size_text(total - free), wq_size_text(total)]
                                : @"Could not read device capacity";
        });
    });
    [stack addArrangedSubview:[self dashboardLabel:@"Explore containers" style:UIFontTextStyleTitle2 color:IPPrimaryText()]];
    NSArray *subtitles = @[@"Individual app folders", @"Shared app storage", @"Widgets & extensions",
                           @"Background services", @"System containers", @"Shared system folders"];
    NSUInteger count = _locations.count + (wq_system_areas_reachable() ? 1 : 0);
    for (NSUInteger i = 0; i < count; i += 2) {
        UIStackView *row = [UIStackView new];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 12;
        row.distribution = UIStackViewDistributionFillEqually;
        for (NSUInteger j = i; j < MIN(i + 2, count); j++) {
            NSArray *loc = j < _locations.count ? _locations[j] : @[@"System Groups", @"", @"lock.square.stack"];
            UIButtonConfiguration *cfg = [UIButtonConfiguration filledButtonConfiguration];
            cfg.title = loc[0];
            cfg.subtitle = subtitles[j];
            cfg.image = ip_pixel_glyph(loc[2]);
            if (IPPixelUIEnabled()) {
                cfg.attributedTitle = [[NSAttributedString alloc] initWithString:loc[0]
                    attributes:@{NSFontAttributeName: IPFont(15, UIFontWeightBold)}];
                cfg.attributedSubtitle = [[NSAttributedString alloc] initWithString:subtitles[j]
                    attributes:@{NSFontAttributeName: IPFont(11, UIFontWeightRegular)}];
            }
            // A leading icon and one shared text column keeps every card on a
            // single visual axis. UIButton's top placement centers the icon
            // even when its title/subtitle are leading-aligned.
            cfg.imagePlacement = NSDirectionalRectEdgeLeading;
            cfg.imagePadding = 14;
            cfg.titlePadding = 5;
            cfg.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;
            cfg.baseForegroundColor = IPCardForeground();
            cfg.baseBackgroundColor = IPCardColor(j);
            cfg.contentInsets = NSDirectionalEdgeInsetsMake(20, 18, 20, 18);
            cfg.background.cornerRadius = IPCornerRadius(26);
            cfg.cornerStyle = UIButtonConfigurationCornerStyleFixed;
            UIButton *button = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
            button.tag = (NSInteger)j;
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
            button.titleLabel.numberOfLines = 0;
            button.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", loc[0], subtitles[j]];
            [button.heightAnchor constraintGreaterThanOrEqualToConstant:132].active = YES;
            [button addTarget:self action:@selector(openContainerCard:) forControlEvents:UIControlEventTouchUpInside];
            [row addArrangedSubview:button];
        }
        if (row.arrangedSubviews.count == 1) [row addArrangedSubview:[UIView new]];
        [stack addArrangedSubview:row];
    }
    if (!wq_system_areas_reachable()) {
        [stack addArrangedSubview:[self dashboardLabel:
            @"System containers require iOS 27. The first Internal Daemons scan on iOS 26 can take a long time."
            style:UIFontTextStyleFootnote color:IPSecondaryText()]];
    }
    CGFloat height = [stack systemLayoutSizeFittingSize:CGSizeMake(width - 40, UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height + 20;
    header.frame = CGRectMake(0, 0, width, ceil(height));
    self.tableView.tableHeaderView = header;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    if (fabs(_dashboardWidth - self.tableView.bounds.size.width) > 1)
        [self rebuildDashboard];
}

// Project authorship, upstream attribution, and technique credits.
- (UIView *)authorFooter
{
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 234)];
    UIView *card = [UIView new];
    card.backgroundColor = IPElevatedSurface();
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.cornerRadius = IPCornerRadius(24);
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:card];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AppIcon60x60"]];
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.layer.cornerRadius = IPCornerRadius(13);
    icon.clipsToBounds = YES;
    [icon.widthAnchor constraintEqualToConstant:52].active = YES;
    [icon.heightAnchor constraintEqualToConstant:52].active = YES;
    UILabel *title = [UILabel new];
    title.text = @"iPixel-Files";
    title.font = IPFont(19, UIFontWeightBold);
    title.textColor = IPPrimaryText();
    UILabel *developer = [UILabel new];
    developer.text = @"Designed & developed by iPixelDev";
    developer.font = IPTextFont(UIFontTextStyleFootnote);
    developer.textColor = IPSecondaryText();
    UIStackView *identityText = [[UIStackView alloc] initWithArrangedSubviews:@[title, developer]];
    identityText.axis = UILayoutConstraintAxisVertical;
    identityText.spacing = 4;
    UIStackView *identity = [[UIStackView alloc] initWithArrangedSubviews:@[icon, identityText]];
    identity.axis = UILayoutConstraintAxisHorizontal;
    identity.alignment = UIStackViewAlignmentCenter;
    identity.spacing = 14;

    UIButton *(^link)(NSString *, NSString *, NSString *) = ^UIButton *(NSString *title, NSString *symbol, NSString *url) {
        UIButtonConfiguration *cfg = [UIButtonConfiguration tintedButtonConfiguration];
        cfg.title = title;
        cfg.image = [UIImage systemImageNamed:symbol];
        cfg.imagePadding = 6;
        cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        cfg.buttonSize = UIButtonConfigurationSizeSmall;
        return [UIButton buttonWithConfiguration:cfg primaryAction:[UIAction actionWithHandler:^(UIAction *__unused a) {
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
        }]];
    };
    UIStackView *links = [[UIStackView alloc] initWithArrangedSubviews:@[
        link(@"Source", @"chevron.left.forwardslash.chevron.right", @"https://github.com/ipixeldev/iPixel-Files"),
        link(@"Original", @"arrow.up.right.square", @"https://github.com/kolbicz/WQFiles"),
    ]];
    links.distribution = UIStackViewDistributionFillEqually;
    links.spacing = 12;

    UILabel *credit = [UILabel new];
    credit.text = @"Based on WQFiles by kolbicz\nworse_query by Taj C · enumeration inspired by KAMUI\nGPL-3.0-or-later";
    credit.numberOfLines = 0;
    credit.textAlignment = NSTextAlignmentCenter;
    credit.font = IPTextFont(UIFontTextStyleCaption1);
    credit.textColor = IPSecondaryText();

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[identity, links, credit]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-16],
        [card.topAnchor constraintEqualToAnchor:footer.topAnchor constant:12],
        [card.bottomAnchor constraintEqualToAnchor:footer.bottomAnchor constant:-16],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
    ]];
    return footer;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return (NSInteger)MIN((NSUInteger)4, _recentFolders.count);
    if (section == 1) return (NSInteger)MIN((NSUInteger)4, _recentFiles.count);
    return 9; // Containers are accessible cards in the dashboard header.
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return section == 0 ? (_recentFolders.count ? @"Recent Folders" : nil)
        : (section == 1 ? (_recentFiles.count ? @"Viewed Files" : nil) : @"Tools");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return section == 2
        ? @"Every destructive file action creates a safety copy first."
        : nil;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    if (![view isKindOfClass:UITableViewHeaderFooterView.class]) return;
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    header.textLabel.font = IPPixelUIEnabled() ? IPFont(15, UIFontWeightBold) : IPTextFont(UIFontTextStyleHeadline);
    header.textLabel.textColor = IPSecondaryText();
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section
{
    if (![view isKindOfClass:UITableViewHeaderFooterView.class]) return;
    UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
    footer.textLabel.font = IPPixelUIEnabled() ? IPFont(11, UIFontWeightRegular) : IPTextFont(UIFontTextStyleFootnote);
    footer.textLabel.textColor = IPSecondaryText();
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"r"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"r"];
    UIListContentConfiguration *c = cell.defaultContentConfiguration;
    if (indexPath.section < 2) {
        NSDictionary *item = indexPath.section == 0 ? _recentFolders[(NSUInteger)indexPath.row]
                                                     : _recentFiles[(NSUInteger)indexPath.row];
        c.text = item[@"name"];
        c.secondaryText = item[@"path"];
        c.secondaryTextProperties.numberOfLines = 2;
        c.image = ip_pixel_glyph(indexPath.section == 0 ? @"folder.fill" : @"doc");
    } else {
        NSArray *tools = @[@[@"Apps", @"square.grid.2x2"], @[@"Cache Cleaner", @"trash"], @[@"Go to Path…", @"arrow.right.circle"],
                           @[@"Starred", @"star.fill"], @[@"Global Search", @"magnifyingglass"], @[@"App Backups", @"clock.arrow.circlepath"], @[@"Backups", @"clock.arrow.circlepath"], @[@"Log", @"doc.plaintext"],
                           @[@"Dual Browser", @"rectangle.split.2x1"]];
        c.text = tools[(NSUInteger)indexPath.row][0];
        c.image = ip_pixel_glyph(tools[(NSUInteger)indexPath.row][1]);
    }
    if (indexPath.section == 2) {
        NSArray *details = @[@"Browse, back up & manage app data", @"Review caches and temporary files",
            @"Jump directly to a folder or file", @"Return to saved folders quickly", @"Search across accessible visited and saved folders", @"Restore or share complete app backups",
            @"Recover overwritten and deleted files", @"Activity, access & diagnostics",
            @"Keep two locations open and copy between containers"];
        c.secondaryText = details[(NSUInteger)indexPath.row];
    }
    c.textProperties.font = IPTextFont(UIFontTextStyleHeadline);
    c.textProperties.color = IPPrimaryText();
    c.secondaryTextProperties.color = IPSecondaryText();
    c.secondaryTextProperties.numberOfLines = 0;
    c.imageProperties.tintColor = IPAccent();
    c.imageProperties.maximumSize = CGSizeMake(26, 26);
    c.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(18, 18, 18, 12);
    cell.backgroundColor = IPSurface();
    cell.contentConfiguration = c;
    IPStyleCell(cell);
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UIViewController *next = nil;
    if (indexPath.section < 2) {
        NSDictionary *item = indexPath.section == 0 ? _recentFolders[(NSUInteger)indexPath.row]
                                                     : _recentFiles[(NSUInteger)indexPath.row];
        if (indexPath.section == 0) next = [[WQDirViewController alloc] initWithPath:item[@"path"] title:item[@"name"]];
        else { wq_open_file(self.navigationController, item[@"path"], NO, WQOpenAuto); return; }
    } else if (indexPath.row == 0) {
        next = [WQAppsViewController new];
    } else if (indexPath.row == 1) {
        next = [WQCacheCleanerViewController new];
    } else if (indexPath.row == 2) {
        [self goToPath];
        return;
    } else if (indexPath.row == 3) {
        next = [WQStarredViewController new];
    } else if (indexPath.row == 4) {
        next = [WQGlobalSearchViewController new];
    } else if (indexPath.row == 5) {
        [NSFileManager.defaultManager createDirectoryAtPath:wq_app_backup_root() withIntermediateDirectories:YES attributes:nil error:nil];
        next = [[WQDirViewController alloc] initWithPath:wq_app_backup_root() title:@"App Backups"];
    } else if (indexPath.row == 6) {
        [NSFileManager.defaultManager createDirectoryAtPath:wq_backup_root() withIntermediateDirectories:YES attributes:nil error:nil];
        next = [[WQDirViewController alloc] initWithPath:wq_backup_root() title:@"Backups"];
    } else if (indexPath.row == 7) {
        next = [WQLogViewController new];
    } else {
        next = [WQDualBrowserViewController new];
    }
    [self.navigationController pushViewController:next animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section > 1) return nil;
    NSDictionary *item = indexPath.section == 0 ? _recentFolders[(NSUInteger)indexPath.row]
                                                 : _recentFiles[(NSUInteger)indexPath.row];
    NSString *path = item[@"path"]; BOOL folder = indexPath.section == 0;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"Remove" handler:^(UIContextualAction *__unused action, UIView *__unused source, void (^done)(BOOL)) {
            wq_remove_recent(path, folder); done(YES);
        }];
    remove.image = [UIImage systemImageNamed:@"xmark"];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[remove]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (void)goToPath
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Go to Path" message:@"A folder or file path"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.text = UIPasteboard.generalPasteboard.hasStrings && [UIPasteboard.generalPasteboard.string hasPrefix:@"/"]
            ? UIPasteboard.generalPasteboard.string : @"/private/var/";
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.clearButtonMode = UITextFieldViewModeAlways;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Open" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused a) {
        NSString *path = alert.textFields.firstObject.text.stringByStandardizingPath;
        if (![path hasPrefix:@"/"]) return;
        dispatch_async(wq_io(), ^{
            struct stat st;
            BOOL exists = wq_stat(path, &st);
            BOOL isDir = exists && S_ISDIR(st.st_mode);
            if (exists && S_ISLNK(st.st_mode)) {
                struct stat target;
                isDir = stat(path.fileSystemRepresentation, &target) == 0 && S_ISDIR(target.st_mode);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!exists) {
                    wq_alert(self, @"Not found", path);
                    return;
                }
                if (!isDir) { wq_open_file(self.navigationController, path, NO, WQOpenAuto); return; }
                [self.navigationController pushViewController:[[WQDirViewController alloc] initWithPath:path title:nil]
                                                     animated:YES];
            });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - App

@interface IPSplashViewController : UIViewController
@end

@implementation IPSplashViewController
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = IPBackground();
    UIView *glow = [UIView new];
    glow.translatesAutoresizingMaskIntoConstraints = NO;
    glow.backgroundColor = [IPAccent() colorWithAlphaComponent:0.10];
    glow.layer.cornerRadius = 150;
    [self.view addSubview:glow];
    UIView *folders = wq_folder_stack_view(CGSizeMake(248, 248), YES);
    [self.view addSubview:folders];
    [NSLayoutConstraint activateConstraints:@[
        [glow.widthAnchor constraintEqualToConstant:300],
        [glow.heightAnchor constraintEqualToConstant:300],
        [glow.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [glow.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [folders.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [folders.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
    CABasicAnimation *breathe = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    breathe.fromValue = @0.92;
    breathe.toValue = @1.04;
    breathe.duration = 1.15;
    breathe.autoreverses = YES;
    breathe.repeatCount = HUGE_VALF;
    breathe.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [glow.layer addAnimation:breathe forKey:@"splashBreathe"];
}
@end

@interface WQSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation WQSceneDelegate

- (void)installRootAnimated:(BOOL)animated
{
    IPInstallAppearance();
    ip_sync_alternate_icon();
    self.window.overrideUserInterfaceStyle = IPPreferredInterfaceStyle();
    self.window.tintColor = IPAccent();
    UIViewController *root = [[WQNavigationController alloc] initWithRootViewController:[WQRootViewController new]];
    if (!animated || !self.window.rootViewController) {
        self.window.rootViewController = root;
        return;
    }
    [UIView transitionWithView:self.window duration:0.25
                       options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowAnimatedContent
                    animations:^{ self.window.rootViewController = root; }
                    completion:nil];
}

- (void)themeDidChange:(NSNotification *)notification
{
    [self installRootAnimated:YES];
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options
{
    IPInstallAppearance();
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window = window;
    window.overrideUserInterfaceStyle = IPPreferredInterfaceStyle();
    window.tintColor = IPAccent();
    window.rootViewController = [IPSplashViewController new];
    [window makeKeyAndVisible];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(themeDidChange:)
        name:IPThemeDidChangeNotification object:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self installRootAnimated:YES];
    });
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end

@interface WQAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation WQAppDelegate

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)session
                              options:(UISceneConnectionOptions *)options
{
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
    config.delegateClass = WQSceneDelegate.class;
    return config;
}

@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        // Container folders get their bundle id from the LaunchServices database
        // when the identifier attribute can't be read (iOS 27.2).
        wq_set_container_label_resolver(wq_bundle_id_for_container);
        wq_set_container_list_provider(wq_ls_container_paths);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(WQAppDelegate.class));
    }
}
