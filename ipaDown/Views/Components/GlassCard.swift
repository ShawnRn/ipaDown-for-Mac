//
//  GlassCard.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI

/// 通用 Liquid Glass 卡片组件
struct GlassCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

/// 可互动的 Glass 卡片
struct InteractiveGlassCard<Content: View>: View {
    let content: Content
    var tintColor: Color?
    
    init(tintColor: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tintColor = tintColor
        self.content = content()
    }
    
    var body: some View {
        content
            .padding()
            .glassEffect(
                {
                    var glass = Glass.regular.interactive()
                    if let tint = tintColor {
                        glass = glass.tint(tint)
                    }
                    return glass
                }(),
                in: .rect(cornerRadius: 16)
            )
    }
}

/// 列表行的 Glass 效果修饰符
struct GlassListRow: ViewModifier {
    var isSelected: Bool = false
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(
                isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                in: .rect(cornerRadius: 12)
            )
    }
}

extension View {
    func glassListRow(isSelected: Bool = false) -> some View {
        modifier(GlassListRow(isSelected: isSelected))
    }
}
