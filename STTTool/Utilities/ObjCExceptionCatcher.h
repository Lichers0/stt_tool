#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Executes a block and catches any Objective-C exceptions.
/// Returns YES if the block executed without throwing, NO otherwise.
FOUNDATION_EXPORT BOOL ObjCTryCatch(void (NS_NOESCAPE ^tryBlock)(void),
                                     NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
