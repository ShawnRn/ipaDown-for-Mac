# ipaDown (Mac & iOS)

> This is a vibe-coded project.
> Developed with ❤️ using **Antigravity**.

<img src="./pics/Icon.png" width="128" height="128" style="float: left; margin-right: 20px;">

**一款使用 Swift 开发的、轻量级 Apple App Store 应用下载工具，支持 macOS 原生运行及导出 iOS IPA。**

[简体中文](./README_zh-CN.md) | [English](./README.md)

![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20iOS-lightgrey.svg?style=flat)
![Language](https://img.shields.io/badge/language-Swift-orange.svg?style=flat)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat)

---

## 📸 界面预览

<p align="center">
  <img src="./pics/Screenshot-1.png" width="45%" />
  <img src="./pics/Screenshot-2.png" width="45%" />
</p>

---

## 📖 简介

**ipaDown** 是一款使用 Swift 开发的跨平台应用下载工具，旨在帮助用户直接从 App Store 获取应用包，并支持在 macOS 上生成适配「巨魔/侧载」的 iOS `.ipa` 文件。

> 💡 **灵感来源**
>
> 本项目灵感来源于发布于 **吾爱破解论坛** 的 **ipaDown Windows 版**。本项目旨在将其核心功能原生迁移至 macOS 平台，并结合 Apple 生态特性进行深度优化，为 Mac 用户提供流畅、纯净的使用体验。

基于系统原生 API 构建，核心网络层集成 `aria2`，确保了极致的下载性能与原生的交互体验。

## ✨ 核心功能

- **原生体验**：使用 SwiftUI 构建，拥有丝般顺滑的 macOS 原生界面与动画。
- **账号管理**：支持多 Apple ID 管理，一键切换商店国家/地区（Storefront）。
- **高级搜索**：支持 App 关键词搜索及历史版本 ID 获取。
- **高速下载**：内置 `aria2` 后端，支持多线程并发下载与断点续传。
- **自动保活**：全自动 Token 刷新机制，确保会话持久有效。
- **跨平台支持**：支持导出专供 iOS/iPadOS 设备安装的 `.ipa` 格式，完美兼容 TrollStore、Sideloadly 等安装方式。
- **自动打包**：集成双端自动打包脚本，一键生成 macOS `.dmg` 与 iOS `.ipa`。
- **自动更新**：集成 Sparkle 框架（仅 Mac 端），时刻保持最新版本。

## 📦 安装指南

### 下载安装包
请前往 [Releases](https://github.com/ShawnRn/ipaDown-for-Mac/releases) 页面下载最新的 `.dmg` 安装包。

### 源码编译

1. **克隆仓库**
   ```bash
   git clone https://github.com/ShawnRn/ipaDown-for-Mac.git
   cd ipaDown-for-Mac
   ```

2. **打开项目**
   使用 Xcode 打开 `ipaDown-for-Apple.xcodeproj` 文件。

3. **一键自动打包 (推荐)**
   直接运行内置的打包脚本，即可在 `build_output` 目录下生成 macOS 和 iOS 的成品包：
   ```bash
   chmod +x ./scripts/build_all.sh
   ./scripts/build_all.sh
   ```

4. **手动编译**
   - 使用 Xcode 选择 `ipaDown` Scheme。
   - 打开 `ipaDown-for-Apple.xcodeproj`，按下 `Cmd + R` 即可运行。
   - 若要导出 iOS 包，请在 Xcode 中将目标设备切换为 `Any iOS Device` 后进行 Archive。

## 🛠 技术栈

- **UI**: SwiftUI (macOS 13.0+)
- **Core**: Swift 5.9+
- **Network**: aria2c (embedded)
- **Update**: Sparkle
- **Design**: 遵循 Apple Human Interface Guidelines

## 📝 开源许可

本项目采用 [MIT License](LICENSE) 许可证。

---

<p align="center">
  Made with ❤️ by Shawn Rain
</p>
