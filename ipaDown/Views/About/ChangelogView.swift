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
        ChangelogItem(
            version: "1.0.0",
            date: "2026-02-14",
            changes: [
                "ipaDown for Mac 初始版本。 ",
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
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    ChangelogView()
        .frame(width: 500, height: 400)
}
