//
//  LicenseView.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI

struct LicenseItem: Identifiable {
    let id = UUID()
    let name: String
    let license: String?
    let description: String
    let type: String
}

struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let licenses: [LicenseItem] = [
        LicenseItem(
            name: "Asspp",
            license: "MIT",
            description: "Seamless multi-account App Store management.\nhttps://github.com/Lakr233/Asspp",
            type: "Downloader Logic Reference"
        ),
        LicenseItem(
            name: "ipatool.js",
            license: "MIT",
            description: "App Store download tool implemented in Node.js.\nhttps://github.com/wf021325/ipatool.js",
            type: "Key Parameters & Protocol Reference"
        ),
        LicenseItem(
            name: "Sparkle",
            license: nil,
            description: "A software update framework for macOS.\nhttps://sparkle-project.org/",
            type: "Update Framework"
        ),
        LicenseItem(
            name: "Antigravity",
            license: "AI Native",
            description: "Developed with ❤️ using Antigravity, the powerful AI coding assistant by Google DeepMind.\nhttps://antigravity.google/",
            type: "Core Development Assistant"
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Motrix Style Header
            HStack(spacing: 16) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("开源许可")
                        .font(.title2.bold())
                    Text("感谢这些伟大的开源项目，它们让 ipaDown 的诞生成为可能。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(24)
            
            // Content
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(licenses) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            // Row 1: Name + License + Type
                            HStack {
                                Text(item.name)
                                    .font(.headline)
                                
                                if let license = item.license {
                                    Text(license)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                                
                                Spacer()
                                
                                Text(item.type)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.1))
                                    .foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                            }
                            
                            // Row 2: Description
                            Text(item.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(4)
                        }
                        .padding(16)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    colorScheme == .dark
                                    ? Color.black.opacity(0.2)
                                    : Color.primary.opacity(0.03) // 浅色模式下使用极淡的灰色
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
    LicenseView()
        .frame(width: 500, height: 400)
}
