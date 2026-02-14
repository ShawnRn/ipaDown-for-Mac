//
//  SidebarView.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI

/// 导航页面
enum NavigationPage: String, CaseIterable, Identifiable {
    case accounts = "accounts"
    case search = "search"
    case versions = "versions"
    case downloads = "downloads"
    case about = "about"
    case settings = "settings"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .accounts: "账号管理"
        case .search: "App 搜索"
        case .versions: "历史版本"
        case .downloads: "下载管理"
        case .about: "关于"
        case .settings: "偏好设置"
        }
    }
    
    var icon: String {
        switch self {
        case .accounts: "person.crop.circle"
        case .search: "magnifyingglass"
        case .versions: "clock.arrow.circlepath"
        case .downloads: "arrow.down.circle"
        case .about: "info.circle"
        case .settings: "gearshape"
        }
    }
}

/// Motrix 风格侧边栏
struct SidebarView: View {
    @Environment(NavigationManager.self) private var nav
    @Environment(AccountManager.self) private var accountManager
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var sidebarNamespace
    @State private var hoveredPage: NavigationPage? = nil
    
    // Pages to show in the top list
    private let topPages: [NavigationPage] = [.accounts, .search, .versions, .downloads]
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Navigation Items
            VStack(spacing: 6) {
                ForEach(topPages) { page in
                    SidebarItem(
                        page: page,
                        isSelected: nav.selectedPage == page,
                        isHovered: hoveredPage == page,
                        badgeCount: badgeCount(for: page),
                        namespace: sidebarNamespace
                    ) {
                        nav.navigate(to: page)
                    }
                    .onHover { isHovered in
                        hoveredPage = isHovered ? page : nil
                    }
                }
            }
            .padding(.top, 52)
            .padding(.horizontal, 10)
            
            Spacer()
            
            // Bottom Items (Settings & About)
            VStack(spacing: 6) {
                // Settings
                let settingsPage = NavigationPage.settings
                SidebarItem(
                    page: settingsPage,
                    isSelected: nav.selectedPage == settingsPage,
                    isHovered: hoveredPage == settingsPage,
                    badgeCount: 0,
                    namespace: sidebarNamespace
                ) {
                    nav.navigate(to: settingsPage)
                }
                .onHover { isHovered in
                    hoveredPage = isHovered ? settingsPage : nil
                }

                // About
                let aboutPage = NavigationPage.about
                SidebarItem(
                    page: aboutPage,
                    isSelected: nav.selectedPage == aboutPage,
                    isHovered: hoveredPage == aboutPage,
                    badgeCount: 0,
                    namespace: sidebarNamespace
                ) {
                    nav.navigate(to: aboutPage)
                }
                .onHover { isHovered in
                    hoveredPage = isHovered ? aboutPage : nil
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 20)
        }
        .frame(width: 200)
        .background(Color(nsColor: .windowBackgroundColor)) 
        .ignoresSafeArea()
    }
    
    private func badgeCount(for page: NavigationPage) -> Int {
        switch page {
        case .accounts:
            return accountManager.accounts.count
        case .downloads:
            return downloadManager.tasks.filter { $0.status.isActive }.count
        default:
            return 0
        }
    }
}

// MARK: - Components

struct SidebarItem: View {
    let page: NavigationPage
    let isSelected: Bool
    let isHovered: Bool
    let badgeCount: Int
    let namespace: Namespace.ID
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: page.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? .white : .primary)
                
                Text(page.title)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .white : .primary)
                
                Spacer()
                
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(isSelected ? .white.opacity(0.2) : .secondary.opacity(0.15))
                        }
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    // Hover effect
                    if isHovered && !isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.secondary.opacity(0.08))
                    }
                    
                    // Selection effect
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 4, y: 2)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SidebarView()
        .environment(AccountManager())
        .environment(DownloadManager())
        .environment(NavigationManager())
        .frame(width: 200, height: 600)
}
