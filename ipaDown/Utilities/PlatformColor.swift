//
//  PlatformColor.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/21.
//

import SwiftUI

/// 跨平台颜色扩展
extension Color {
    #if os(macOS)
    /// 窗口背景色
    static let platformWindowBackground = Color(nsColor: .windowBackgroundColor)
    /// 控件背景色
    static let platformControlBackground = Color(nsColor: .controlBackgroundColor)
    #else
    /// 窗口背景色
    static let platformWindowBackground = Color(uiColor: .systemBackground)
    /// 控件背景色
    static let platformControlBackground = Color(uiColor: .secondarySystemBackground)
    #endif
}
