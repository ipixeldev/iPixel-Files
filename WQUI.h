//
//  WQUI.h
//  WQ Files shared UI helpers
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

static inline UIBarButtonItemStyle wq_primary_button_style(void)
{
    if (@available(iOS 26.0, *)) return UIBarButtonItemStyleProminent;
    return UIBarButtonItemStylePlain;
}

dispatch_queue_t wq_io(void);
void wq_alert(UIViewController *host, NSString *title, NSString *_Nullable message);
NSString *wq_size_text(unsigned long long size);
UIView *wq_device_header(CGFloat width);
UIView *wq_folder_stack_view(CGSize size, BOOL animated);
float wq_progress_from_text(NSString *_Nullable text);

@interface WQLoadingCardCell : UITableViewCell
- (void)configureWithTitle:(NSString *)title
                    status:(NSString *_Nullable)status
                  progress:(float)progress;
@end
// "iPhone 17 Pro Max (iPhone18,2) · iOS 27.0.1 (24A446)"
NSString *wq_device_line(void);
UIImage *_Nullable wq_app_icon(NSString *_Nullable bundleID);
void wq_file_thumbnail(NSString *path, CGSize size,
                       void (^completion)(UIImage *_Nullable image));

NS_ASSUME_NONNULL_END
