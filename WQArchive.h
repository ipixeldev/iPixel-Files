#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSArray<NSDictionary<NSString *, id> *> *_Nullable WQArchiveList(
    NSString *path, NSString *_Nullable *_Nullable errorText);
BOOL WQArchiveExtract(NSString *path, NSString *destination,
    NSString *_Nullable *_Nullable errorText);

NS_ASSUME_NONNULL_END
