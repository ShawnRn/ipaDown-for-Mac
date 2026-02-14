//
//  SearchManager.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// 搜索管理 ViewModel
@Observable
class SearchManager {
    /// 搜索关键词
    var searchText = ""
    
    /// 国家代码
    var countryCode = "CN"
    
    /// 设备类型
    var deviceType: DeviceType = .iPhone
    
    /// 搜索结果数量限制
    var resultLimit = 10
    
    /// 搜索结果
    var results: [AppSoftware] = []
    
    /// 搜索中
    var isSearching = false
    
    /// 错误信息
    var errorMessage: String?
    
    /// 选中的 App
    var selectedApp: AppSoftware?
    
    private let logger = AppLogger.shared
    
    // MARK: - 搜索操作
    
    /// 执行搜索（自动判断输入类型：关键词/链接/ID）
    func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        isSearching = true
        errorMessage = nil
        
        do {
            results = try await SearchService.parseInput(query, countryCode: countryCode)
            
            // 如果 parseInput 返回的是单个精确查找结果，自动选中
            if results.count == 1 {
                selectedApp = results.first
            }
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
        
        isSearching = false
    }
    
    /// 按名称搜索
    func searchByName() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        isSearching = true
        errorMessage = nil
        
        do {
            results = try await SearchService.search(
                term: query,
                countryCode: countryCode,
                limit: resultLimit,
                deviceType: deviceType
            )
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
        
        isSearching = false
    }
    
    /// 清空搜索结果
    func clearResults() {
        results = []
        selectedApp = nil
        errorMessage = nil
    }
}
