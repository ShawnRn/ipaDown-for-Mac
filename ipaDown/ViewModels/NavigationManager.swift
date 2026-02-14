//
//  NavigationManager.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI
import Observation

/// 导航过渡类型
enum NavTransitionType {
    case slide   // 组内平移
    case smooth  // 跨组模糊 (LiquidBlur)
}

/// 全局导航管理器
@Observable
@MainActor
class NavigationManager {
    /// 当前呈现的页面
    var selectedPage: NavigationPage = .search
    
    /// 上一个页面（用于协助判断动画方向或过渡类型）
    var previousPage: NavigationPage = .search
    
    /// 当前激活的过渡类型
    var activeTransition: NavTransitionType = .slide
    
    /// 导航历史（回退栈）
    var backStack: [NavigationPage] = []
    
    /// 前进记录
    var forwardStack: [NavigationPage] = []
    
    /// 内部标志位，防止 navigate 内部触发二次逻辑
    private var isNavigating = false
    
    // MARK: - Core Methods
    
    /// 跳转到指定页面
    func navigate(to page: NavigationPage) {
        guard selectedPage != page else { return }
        
        // 判断过渡类型
        activeTransition = getTransitionType(from: selectedPage, to: page)
        
        previousPage = selectedPage
        if !isNavigating {
            backStack.append(selectedPage)
            forwardStack.removeAll()
        }
        
        // 直接更新状态，不再使用 withAnimation
        selectedPage = page
    }
    
    /// 回退到上一页
    func goBack() {
        guard let lastPage = backStack.popLast() else { return }
        
        isNavigating = true
        forwardStack.append(selectedPage)
        navigate(to: lastPage)
        isNavigating = false
    }
    
    /// 前进到下一页
    func goForward() {
        guard let nextPage = forwardStack.popLast() else { return }
        
        isNavigating = true
        backStack.append(selectedPage)
        navigate(to: nextPage)
        isNavigating = false
    }
    
    // MARK: - Private Helpers
    
    private func getTransitionType(from: NavigationPage, to: NavigationPage) -> NavTransitionType {
        let topGroup: Set<NavigationPage> = [.accounts, .search, .versions, .downloads]
        let isFromTop = topGroup.contains(from)
        let isToTop = topGroup.contains(to)
        
        // 如果是从顶层到底层，或底层到顶层，使用 smooth (LiquidBlur)
        return isFromTop == isToTop ? .slide : .smooth
    }
}
