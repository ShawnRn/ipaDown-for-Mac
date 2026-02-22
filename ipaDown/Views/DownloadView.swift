//
//  DownloadView.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI

struct DownloadView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @State private var selectedTask: IPADownloadTask?
    @State private var shareURL: IdentifiableURL?
    
    var body: some View {
        NavigationStack {
            List {
                if downloadManager.tasks.isEmpty {
                    ContentUnavailableView(
                        "没有下载任务",
                        systemImage: "arrow.down.circle",
                        description: Text("搜索并添加 IPA 以后，下载的任务会显示在这里。")
                    )
                } else {
                    ForEach(downloadManager.tasks) { task in
                        DownloadTaskRow(
                            task: task,
                            onTogglePause: {
                                downloadManager.togglePause(task: task)
                            },
                            onRemove: {
                                downloadManager.removeTask(task)
                            },
                            onShare: {
                                handleShare(task)
                            }
                        )
                        #if os(iOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                downloadManager.removeTask(task)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            
                            Button {
                                downloadManager.togglePause(task: task)
                            } label: {
                                if task.status.isActive || task.status == .waiting {
                                    Label("暂停", systemImage: "pause.fill")
                                } else {
                                    Label("继续", systemImage: "play.fill")
                                }
                            }
                            .tint(.orange)
                        }
                        #endif
                    }
                }
            }
            .navigationTitle("下载管理")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        #if os(macOS)
                        Button {
                            downloadManager.showDownloadFolder()
                        } label: {
                            Label("打开下载目录", systemImage: "folder")
                        }
                        #endif
                        
                        Button {
                            downloadManager.clearCompleted()
                        } label: {
                            Label("清除已完成", systemImage: "trash")
                        }
                    }
                }
            }
            .sheet(item: $shareURL) { item in
                #if os(iOS)
                ActivityView(activityItems: [item.url])
                #else
                EmptyView()
                #endif
            }
        }
    }
    
    // 使得 URL 遵循 Identifiable 以便在 sheet 中使用
    struct IdentifiableURL: Identifiable {
        let id = UUID()
        let url: URL
    }
    
    private func handleShare(_ task: IPADownloadTask) {
        let fileName = task.fileName
        // 动态拼接最新沙盒路径，防止重启后使用旧的 filePath 绝对路径导致 "File not found"
        let sourceURL = downloadManager.downloadDirectory.appendingPathComponent(fileName)
        
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            print("❌ [UI] Share failed: File not found at \(sourceURL.path)")
            return
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let destinationURL = tempDir.appendingPathComponent(fileName)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            
            _ = sourceURL.startAccessingSecurityScopedResource()
            defer { sourceURL.stopAccessingSecurityScopedResource() }
            
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            self.shareURL = IdentifiableURL(url: destinationURL)
            print("✅ [UI] IPA copied to temp for sharing: \(destinationURL.path)")
        } catch {
            print("❌ [UI] Failed to copy IPA to temp: \(error)")
        }
    }
}

struct DownloadTaskRow: View {
    let task: IPADownloadTask
    let onTogglePause: () -> Void
    let onRemove: () -> Void
    let onShare: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            AsyncImage(url: task.iconURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "app.dashed")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(task.appName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text("v\(task.displayVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if task.status == .downloading || task.status == .verifying || task.status == .signing {
                    ProgressView(value: task.progress)
                        .progressViewStyle(.linear)
                        .tint(.green)
                    
                    HStack {
                        Text(task.status.description)
                        Spacer()
                        Text(task.speed)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(task.status.description)
                        if task.status == .completed {
                            Text("· \(task.totalBytesString)")
                        } else if task.status == .failed, let error = task.error {
                            Text("· \(error)")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(task.status == .completed ? .green : .secondary)
                }
            }
            
            Spacer()
            
            #if os(macOS)
            HStack(spacing: 12) {
                if task.status != .completed {
                    Button(task.status.isActive ? "暂停" : "继续") { onTogglePause() }
                        .buttonStyle(.bordered)
                }
                
                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .padding(4)
            }
            .opacity(isHovering ? 1 : 0)
            #else
            HStack(spacing: 8) {
                if task.status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 20))
                    
                    // 分享单独拉出来，规避 Menu 内部触发 ShareSheet 可能导致的 SwiftUI 挂死
                    Button {
                        onShare()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20))
                            .foregroundStyle(.blue)
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                            .background(Color.blue.opacity(0.1).clipShape(Circle()))
                    }
                }
                
                Menu {
                    if task.status != .completed {
                        Button {
                            onTogglePause()
                        } label: {
                            if task.status.isActive || task.status == .waiting {
                                Label("暂停", systemImage: "pause.fill")
                            } else {
                                Label("继续下载", systemImage: "play.fill")
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color.secondary.opacity(0.1).clipShape(Circle()))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            #endif
        }
        .padding(.vertical, 6)
        #if os(macOS)
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.platformControlBackground.opacity(0.4))
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        #else
        .contextMenu {
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        #endif
    }
}
