//
//  PlatformImage.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/21.
//

import SwiftUI

/// 跨平台图像辅助
enum PlatformImage {
    /// 获取 App 图标
    static var appIcon: Image {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage)
        #else
        if let uiImage = UIImage(named: "AppLogoHD") {
            Image(uiImage: uiImage)
        } else if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primary["CFBundleIconFiles"] as? [String],
           let iconName = iconFiles.last,
           let uiImage = UIImage(named: iconName) {
            Image(uiImage: uiImage)
        } else if let uiImage = UIImage(named: "ipaDown") {
            Image(uiImage: uiImage)
        } else {
            Image(systemName: "app.fill")
        }
        #endif
    }
}
