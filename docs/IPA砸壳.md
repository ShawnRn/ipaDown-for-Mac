# IPA 砸壳（macOS）

在「下载管理」点击「IPA 砸壳」，或在已完成任务旁点击「砸壳」。

首次点击「开始配置向导」，按步骤完成：

1. 检查内置工具与本机环境。
2. 登录原生 Mac App Store，安装并打开一个 iPhone / iPad 应用；向导自动扫描，亦可手动选择。
3. 向导复用下载记录或通过 ipaDown 当前选择的账号下载匹配 IPA，核对 Bundle ID 和真实 FairPlay 授权 selector；样本不必与 Mac 应用版本完全相同，后续仍须通过完整解密验证。
4. 点击「授权并自动生成」。macOS 弹出管理员授权窗口，密码由系统接收，不进入 ipaDown。UnfairPlay 提取本机授权状态、恢复模型并验证匹配 IPA。
5. 完成后选择要解密的 IPA，点击「砸壳并另存」。

也可导入已生成的 v2/v3 私有模型。模型复制到 `Application Support/ipaDown/UnfairPlay/models`，目录权限 0700、文件权限 0600。导入按内容去重。不同账号或授权状态可保存多个模型，匹配与完整性校验交由 UnfairPlay 执行。

此功能不会上传模型，也不会重签名 IPA。砸壳原件始终保留，输出不得覆盖既有文件；失败和取消会在子进程结束后清理临时明文。关闭砸壳窗口可让普通解密在后台继续；退出整个应用前应等待结束。

## 系统限制

首次模型生成需要受支持的正式版 Apple 芯片 Mac。具体系统构建、账号授权状态、selector 以及 IPA 材料必须得到上游验证。部分路径需额外的精确 `fairplayd` arm64e 参考文件；向导在失败时提供选择入口，随后可重试。程序不会为未知路径跳过验证。

Mac App Store 登录、首次安装和系统授权由用户完成。iOS 不包含这套本地进程与系统采集功能。

## 构建

Xcode macOS 构建阶段调用 `scripts/build_unfairplay.sh`，首次需要 Git、网络和 Go 1.26+。脚本固定上游提交 `2fad9dcb9506674b92aad5833fad8988d69edc75`，构建 arm64 / amd64 通用程序，缓存到 `.build`，嵌入 `Contents/Helpers/unfairplay` 并附带完整许可证。iOS 构建跳过该步骤。

运行 `scripts/test_decryption.sh` 验证进程退出、取消、输出保护与失败清理；运行 `scripts/test_purchase.sh` 验证购买接口的许可与认证错误分类。测试仅使用合成材料。

真实 FairPlay 恢复与解密验收需要用户的私有授权材料；构建通过和模拟进程测试不代表该部分已在所有系统上实测。
