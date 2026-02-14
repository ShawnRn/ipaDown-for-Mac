# ipaDown for Mac

> This is a vibe-coded project.
> Developed with ❤️ using **Antigravity**.

<img src="./pics/Icon.png" width="128" height="128" style="float: left; margin-right: 20px;">

**一款使用 Swift 开发的、轻量级 macOS App Store 应用下载工具。**

[简体中文](./README_zh-CN.md) | [English](./README.md)

![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=flat)
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

**ipaDown for Mac** 是一款使用 Swift 开发的 `.ipa` 文件下载工具，旨在帮助用户直接从 App Store 获取应用包。

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
- **系统集成**：支持原生系统通知及 AirDrop 快速分享已下载文件。
- **自动更新**：集成 Sparkle 框架，时刻保持最新版本。

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
   使用 Xcode 打开 `ipaDown-for-Mac.xcodeproj` 文件。

3. **编译运行**
   选择 `ipaDown` Scheme，按下 `Cmd + R` 即可运行。

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
