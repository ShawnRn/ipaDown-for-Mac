#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 使用系统 CommerceKit 为 Apple Store 请求体生成 SAP 签名。
///
/// 实现通过运行时动态加载私有框架，因此不会在链接阶段产生私有框架依赖。
FOUNDATION_EXPORT NSData * _Nullable IPACommerceKitCreateSAPSignature(
    NSData *data,
    NSError * _Nullable * _Nullable error
);

NS_ASSUME_NONNULL_END
