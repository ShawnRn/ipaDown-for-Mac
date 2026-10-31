#import "SAPSigner.h"

#import <dispatch/dispatch.h>
#import <dlfcn.h>

// The runtime technique is adapted from ipatool-sapfix (MIT License):
// https://github.com/maksimryabkin/ipatool-sapfix

static NSString * const IPACommerceKitErrorDomain = @"com.shawnrain.ipaDown.sap";

@interface IPACKSigningSession : NSObject
- (instancetype)initWithStoreClient:(nullable id)storeClient;
- (void)openSessionWithCompletionHandler:(void (^)(void))completionHandler;
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;
- (void)closeSession;
- (BOOL)isSessionOpen;
@end

static NSError *IPACommerceKitError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:IPACommerceKitErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static Class IPACommerceKitSigningSessionClass(NSError **error) {
    static void *commerceKitHandle = NULL;
    static NSString *loadErrorMessage = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        commerceKitHandle = dlopen(
            "/System/Library/PrivateFrameworks/CommerceKit.framework/CommerceKit",
            RTLD_LAZY | RTLD_LOCAL
        );
        if (commerceKitHandle == NULL) {
            const char *message = dlerror();
            loadErrorMessage = message == NULL
                ? @"当前系统没有可用的 CommerceKit"
                : [NSString stringWithUTF8String:message];
        }
    });

    if (commerceKitHandle == NULL) {
        if (error != NULL) {
            *error = IPACommerceKitError(1, loadErrorMessage ?: @"无法加载 CommerceKit");
        }
        return Nil;
    }

    Class signingSessionClass = NSClassFromString(@"CKSigningSession");
    if (signingSessionClass == Nil && error != NULL) {
        *error = IPACommerceKitError(2, @"当前系统的 CommerceKit 不支持 SAP 签名");
    }
    return signingSessionClass;
}

static NSData *IPACreateSAPSignatureInCurrentPool(NSData *data, NSError **error) {
    Class signingSessionClass = IPACommerceKitSigningSessionClass(error);
    if (signingSessionClass == Nil) {
        return nil;
    }

    // CommerceKit 的签名会话不是线程安全的；账号自动刷新与手动登录可能并发发生。
    @synchronized (signingSessionClass) {

        IPACKSigningSession *session = [(id)[signingSessionClass alloc] initWithStoreClient:nil];
        if (session == nil) {
            if (error != NULL) {
                *error = IPACommerceKitError(3, @"无法创建 Apple SAP 签名会话");
            }
            return nil;
        }

        dispatch_semaphore_t opened = dispatch_semaphore_create(0);
        [session openSessionWithCompletionHandler:^{
            dispatch_semaphore_signal(opened);
        }];

        long waitResult = dispatch_semaphore_wait(
            opened,
            dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)
        );
        if (waitResult != 0) {
            [session closeSession];
            if (error != NULL) {
                *error = IPACommerceKitError(4, @"打开 Apple SAP 签名会话超时");
            }
            return nil;
        }

        if ([session respondsToSelector:@selector(isSessionOpen)] && !session.isSessionOpen) {
            [session closeSession];
            if (error != NULL) {
                *error = IPACommerceKitError(5, @"Apple SAP 签名会话未能打开");
            }
            return nil;
        }

        NSError *signingError = nil;
        NSData *signature = [session signData:data error:&signingError];
        [session closeSession];

        if (signature.length == 0) {
            if (error != NULL) {
                *error = signingError ?: IPACommerceKitError(6, @"Apple SAP 签名结果为空");
            }
            return nil;
        }
        return signature;
    }

}

NSData *IPACommerceKitCreateSAPSignature(NSData *data, NSError **error) {
    // NSError** is autoreleasing. Publishing it from inside a drained pool
    // leaves Swift with a dangling object on failure. Retain both results in
    // strong locals, then publish the error in the caller's pool.
    NSError *retainedError = nil;
    NSData *retainedSignature = nil;
    @autoreleasepool {
        retainedSignature = IPACreateSAPSignatureInCurrentPool(data, &retainedError);
    }
    if (error != NULL) {
        *error = retainedError;
    }
    return retainedSignature;
}
