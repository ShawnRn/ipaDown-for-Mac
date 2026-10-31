//
//  ChangelogView.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI

struct ChangelogItem: Identifiable {
    let id = UUID()
    let version: String
    let date: String
    let changes: [String]
}

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let changelogs: [ChangelogItem] = [
        ChangelogItem(version: "1.5.0", date: "2026-10-31", changes: [
            "修复 SAP 签名失败时错误对象提前释放导致的崩溃。",
            "已有应用直接请求下载，仅在服务端明确缺少许可时获取许可，避免前置请求超时阻塞。",
            "macOS 新增基于 UnfairPlay 的本机 IPA 砸壳，支持首次模型配置向导和已有模型导入。",
            "模型按真实授权状态匹配，可复用于其他 IPA；原文件保留，结果另存。",
            "简化砸壳界面，将模型管理移至配置入口，突出文件选择与完成结果。",
            "修复已有应用许可被误报为 Token 过期、初始化子进程文件访问及重复砸壳报告重名问题。"
        ]),
        ChangelogItem(
            version: "1.4.5",
            date: "2026-10-21",
            changes: [
                "修复 Apple 认证接口未带尾随斜杠导致返回 HTTP 204 空响应的问题。",
                "优化双重验证输入体验，消除系统光标泄漏问题，增加未收到推送时的验证码获取指引。",
                "微调登录弹窗 Apple 标志的光学居中与质感呈现。"
            ]
        ),
        ChangelogItem(
            version: "1.4.4",
            date: "2026-08-31",
            changes: [
                "适配 Apple 新版 SAP 安全认证，修复登录时 HTTP 403 错误。",
                "登录端点改为通过 Apple bag 动态解析，并安全处理 Store Pod 重定向。",
                "完善 Token 刷新与双重验证码续期流程，改进认证错误提示。"
            ]
        ),
        ChangelogItem(
            version: "1.4.3",
            date: "2026-08-02",
            changes: [
                "修复 Apple 账号登录接口报 HTTP 404 网络错误的问题。"
            ]
        ),
        ChangelogItem(
            version: "1.4",
            date: "2026-03-22",
            changes: [
                "修复下载时「License not found」错误，支持自动获取未 Get 的免费应用。",
                "修复暂停下载被误标为失败的问题。",
                "重构账号管理持久化，迁移至私有 JSON 文件存储，卸载后零残留。",
                "重新设计账号页面，统一卡片布局，模态登录表单适配 macOS 与 iOS。",
                "签名服务跨平台适配，使用 ZIPFoundation 重写签名注入。",
                "新增 iOS/iPadOS 全面适配，两步验证、下载管理等 UI 深度优化。",
                "大量 UI 细节优化，全局 AccentColor、空状态标准化等。",
                "修复多个稳定性问题，包括 macOS 崩溃和 iOS 分享面板异常。",
            ]
        ),
        ChangelogItem(
            version: "1.3",
            date: "2026-02-22",
            changes: [
                "新增支持 iPhone/iPad。",
                "微调了 UI。",
                "修复了一些 Bugs。"
            ]
        ),
        ChangelogItem(
            version: "1.1",
            date: "2026-02-15",
            changes: [
                "优化了界面细节。"
            ]
        ),
        ChangelogItem(
            version: "1.0",
            date: "2026-02-14",
            changes: [
                "🎉 ipaDown for Mac 的首个 Release 版本。",
                "支持多账号管理与地区快速切换。",
                "支持 App 搜索与获取历史版本 ID。",
                "实现账号 Token 自动刷新与 StoreFront 状态维护。"
            ]
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Motrix Style Header
            HStack(spacing: 16) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("更新日志")
                        .font(.title2.bold())
                    Text("记录 ipaDown 进化的点点滴滴。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(24)
            
            // Content
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(changelogs) { item in
                        VStack(alignment: .leading, spacing: 16) {
                            // Version Info
                            HStack {
                                Text("v\(item.version)")
                                    .font(.title3.bold())
                                
                                Spacer()
                                
                                Text(item.date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            // Changes List
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(item.changes, id: \.self) { change in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                            .font(.system(size: 14))
                                            .padding(.top, 2)
                                        
                                        Text(change)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .lineSpacing(4)
                                    }
                                }
                            }
                        }
                        .padding(20)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    colorScheme == .dark
                                    ? Color.black.opacity(0.2)
                                    : Color.primary.opacity(0.03)
                                )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            
            // Footer
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("完成")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .background(Color.platformWindowBackground)
    }
}

#Preview {
    ChangelogView()
        #if os(macOS)
        .frame(width: 500, height: 400)
        #endif
}
