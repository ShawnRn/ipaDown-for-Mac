//
//  ContentView.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI

/// 主视图
struct ContentView: View {
    @Environment(NavigationManager.self) private var nav
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(200)
        } detail: {
            detailView
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        ControlGroup {
                            Button {
                                nav.goBack()
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(nav.backStack.isEmpty)
                            
                            Button {
                                nav.goForward()
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(nav.forwardStack.isEmpty)
                        }
                        .controlGroupStyle(.navigation)
                    }
                }
        }
    }
    
    @ViewBuilder
    private var detailView: some View {
        ZStack {
            switch nav.selectedPage {
            case .accounts:
                AccountView().id(NavigationPage.accounts)
            case .search:
                SearchView().id(NavigationPage.search)
            case .versions:
                VersionView().id(NavigationPage.versions)
            case .downloads:
                DownloadView().id(NavigationPage.downloads)
            case .about:
                AboutView().id(NavigationPage.about)
            case .settings:
                SettingsView().id(NavigationPage.settings)
            }
        }
        .transition(.identity)
    }
    
    // MARK: - 动画辅助
    
    /// 跨组切换动画（LiquidBlur）
    private var smoothTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: LiquidBlurModifier(radius: 16, opacity: 0, scale: 0.95),
                identity: LiquidBlurModifier(radius: 0, opacity: 1, scale: 1.0)
            ),
            removal: .modifier(
                active: LiquidBlurModifier(radius: 16, opacity: 0, scale: 1.05),
                identity: LiquidBlurModifier(radius: 0, opacity: 1, scale: 1.0)
            )
        )
    }
    
    /// 组内切换动画（平移）
    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

struct LiquidBlurModifier: ViewModifier {
    var radius: CGFloat
    var opacity: Double
    var scale: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
            .scaleEffect(scale)
    }
}

#Preview {
    ContentView()
        .environment(AccountManager())
        .environment(SearchManager())
        .environment(VersionManager())
        .environment(DownloadManager())
        .environment(NavigationManager())
}
