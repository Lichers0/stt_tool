#import "ObjCExceptionCatcher.h"

BOOL ObjCTryCatch(void (NS_NOESCAPE ^tryBlock)(void), NSError * _Nullable * _Nullable error) {
    @try {
        tryBlock();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"ObjCException"
                                         code:-1
                                     userInfo:@{
                NSLocalizedDescriptionKey: exception.reason ?: exception.name
            }];
        }
        return NO;
    }
}
