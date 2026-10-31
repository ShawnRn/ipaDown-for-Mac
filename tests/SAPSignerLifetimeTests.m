#import <Foundation/Foundation.h>
#import "SAPSigner.h"

@interface IPATestSigningSession : NSObject
@end
@implementation IPATestSigningSession
- (instancetype)initWithStoreClient:(id)client { return [super init]; }
- (void)openSessionWithCompletionHandler:(void (^)(void))completion { completion(); }
- (BOOL)isSessionOpen { return YES; }
- (NSData *)signData:(NSData *)data error:(NSError **)error {
    if (data.length == 1) { return [NSData dataWithBytes:"ok" length:2]; }
    if (error) { *error = [NSError errorWithDomain:@"synthetic-sap" code:42 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"synthetic error %lu", (unsigned long)data.length]}]; }
    return nil;
}
- (void)closeSession {}
@end

int main(void) {
    for (NSUInteger i = 0; i < 1000; i++) {
        @autoreleasepool {
            NSError *error = nil;
            NSData *result = IPACommerceKitCreateSAPSignature([NSData data], &error);
            NSCAssert(result == nil && error.code == 42, @"Failure must preserve NSError");
            NSCAssert([error.localizedDescription isEqualToString:@"synthetic error 0"], @"Error must survive inner pool");
            NSData *success = IPACommerceKitCreateSAPSignature([NSData dataWithBytes:"x" length:1], &error);
            NSCAssert(success.length == 2 && error == nil, @"Success must preserve data and clear error");
            NSCAssert(IPACommerceKitCreateSAPSignature([NSData data], NULL) == nil, @"NULL error pointer must work");
        }
    }
    puts("PASS: 1000 failure/success/NULL-error cycles across autorelease-pool boundary");
}
