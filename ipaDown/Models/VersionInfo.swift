//
//  VersionInfo.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// 版本信息模型
struct VersionInfo: Identifiable, Hashable, Equatable {
    var id: String { externalVersionId }
    
    var externalVersionId: String   // 版本 ID（Apple 内部标识）
    var displayVersion: String?     // 显示版本号, e.g. "8.0.69"
    var releaseDate: Date?          // 发布日期
    var isLoading: Bool = false     // 是否正在加载详情
    
    var formattedDate: String {
        guard let date = releaseDate else { return "未知" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    // MARK: - Sorting Helpers
    var releaseDateComparable: Date { releaseDate ?? .distantPast }
    var displayVersionComparable: String { displayVersion ?? "" }
}
