//
//  AboutView.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI
#if os(macOS)
import Sparkle
#endif

struct AboutView: View {
    @State private var showLicenses = false
    @State private var showChangelog = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 32) {
                // App Logo & Basic Info
                VStack(spacing: 16) {
                    PlatformImage.appIcon
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                        .background {
                            Circle()
                                .fill(Color.accentColor.opacity(0.1))
                                .frame(width: 130, height: 130)
                                .blur(radius: 20)
                        }
                    
                    VStack(spacing: 4) {
                        Text("ipaDown")
                            .font(.system(size: 24, weight: .bold))
                        
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Text("轻量级、全原生的 App Store 应用下载工具。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                
                // Action Buttons
                HStack(spacing: 24) {
                    AboutLinkButton(icon: "doc.text.fill", title: "开源许可") {
                        showLicenses = true
                    }
                    .sheet(isPresented: $showLicenses) {
                        LicenseView()
                            #if os(macOS)
                            .frame(width: 550, height: 450)
                            #endif
                    }
                    
                    AboutLinkButton(icon: "globe", title: "GitHub", isExternal: true, url: "https://github.com/ShawnRn/ipaDown-for-Mac")
                    
                    AboutLinkButton(icon: "clock.arrow.circlepath", title: "更新日志") {
                        showChangelog = true
                    }
                    .sheet(isPresented: $showChangelog) {
                        ChangelogView()
                            #if os(macOS)
                            .frame(width: 550, height: 450)
                            #endif
                    }
                }
            }
            
            Spacer()
            
            // Check for Updates Section
            VStack(spacing: 12) {
                #if os(macOS)
                Button {
                    // 优先使用静态 shared 实例访问，如果失败则尝试强转系统 delegate
                    if let delegate = AppDelegate.shared {
                        delegate.checkForUpdates()
                    } else if let delegate = NSApplication.shared.delegate as? AppDelegate {
                        delegate.checkForUpdates()
                    } else {
                        print("Error: Could not access AppDelegate via shared or NSApp.delegate")
                    }
                } label: {
                    Label("检查更新", systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                #endif
                
                Text("Made with ❤️ by Shawn Rain")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                Link("shawnrain.me@gmail.com", destination: URL(string: "mailto:shawnrain.me@gmail.com")!)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .buttonStyle(.plain)
                
                Text("MIT Copyright (c) 2026-present Shawn Rain")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Subcomponents

struct AboutLinkButton: View {
    let icon: String
    let title: String
    var isExternal: Bool = false
    var url: String = ""
    var action: (() -> Void)? = nil
    
    @State private var isHovered = false
    
    var body: some View {
        Group {
            if isExternal, let linkUrl = URL(string: url) {
                Link(destination: linkUrl) {
                    buttonContent
                }
            } else {
                Button {
                    action?()
                } label: {
                    buttonContent
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
    
    private var buttonContent: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isHovered ? Color.accentColor : .primary.opacity(0.8))
            }
            
            Text(title)
                .font(.caption)
                .foregroundStyle(isHovered ? .primary : .secondary)
        }
        .frame(width: 70)
    }
}

#Preview {
    AboutView()
}
