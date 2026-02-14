//
//  DownloadView.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI

/// 下载管理视图
struct DownloadView: View {
    @Environment(DownloadManager.self) private var downloadManager
    
    @State private var selection: Set<IPADownloadTask.ID> = []
    @State private var showClearConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 任务列表
            if downloadManager.tasks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("暂无下载任务")
                        .foregroundStyle(.secondary)
                    Text("在搜索页或历史版本页开始下载")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                tasksList
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    downloadManager.showDownloadFolder()
                } label: {
                    Label("打开目录", systemImage: "folder")
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if !downloadManager.tasks.filter({ $0.status == .completed }).isEmpty {
                        showClearConfirmation = true
                    }
                } label: {
                    Label("清除已完成", systemImage: "trash")
                }
                .help("清除所有已完成的任务")
                .confirmationDialog(
                    "确定要清除所有已完成的任务吗？",
                    isPresented: $showClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("清除", role: .destructive) {
                        downloadManager.clearCompleted()
                    }
                    Button("取消", role: .cancel) {}
                }
            }
        }
    }
    
    private var tasksList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(downloadManager.tasks) { task in
                    DownloadTaskRow(
                        task: task,
                        isSelected: selection.contains(task.id),
                        onShowInFinder: {
                            downloadManager.showInFinder(task)
                        },
                        onRemove: {
                            downloadManager.removeTask(task)
                            if selection.contains(task.id) {
                                selection.remove(task.id)
                            }
                        },
                        onTogglePause: {
                            downloadManager.togglePause(task: task)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            if selection.contains(task.id) {
                                selection.remove(task.id)
                            } else {
                                selection.insert(task.id)
                            }
                        } else {
                            selection = [task.id]
                        }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .onTapGesture {
            // Click empty space to deselect
            selection.removeAll()
        }
    }
}

// MARK: - 下载任务行

struct DownloadTaskRow: View {
    @Bindable var task: IPADownloadTask
    let isSelected: Bool
    var onShowInFinder: () -> Void
    var onRemove: () -> Void
    var onTogglePause: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // 左侧状态条
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 4)
                .padding(.vertical, 8)
                .opacity(isSelected ? 1 : 0)
                .padding(.leading, -8)
            
            // App 图标
            AsyncImage(url: task.iconURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "app")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 1, y: 1)
            
            // 任务信息
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(task.appName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("v\(task.displayVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 8) {
                    if task.status == .downloading {
                        ProgressView(value: task.progress)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                            .frame(width: 100)
                        
                        Text("\(task.sizeProgressString) · \(task.speed)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else if let error = task.error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    } else if task.status == .completed {
                        Text("\(task.sizeProgressString) · 已完成")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(task.status.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // 操作按钮
            if isHovering || isSelected {
                HStack(spacing: 8) {
                    if task.status == .completed {
                        ActionButton(icon: "square.and.arrow.up", color: .blue) {
                            shareViaAirDrop()
                        }
                        .help("AirDrop 分享")
                        
                        ActionButton(icon: "folder", color: .blue) {
                            onShowInFinder()
                        }
                    } else {
                        ActionButton(
                            icon: (task.status == .paused || task.status == .failed) ? "play.fill" : "pause.fill",
                            color: .orange
                        ) {
                            onTogglePause()
                        }
                    }
                    
                    ActionButton(icon: "xmark", color: .red) {
                        onRemove()
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor).opacity(0.6))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    private func shareViaAirDrop() {
        guard let url = task.filePath else { return }
        let sharingService = NSSharingService(named: .sendViaAirDrop)
        if let service = sharingService, service.canPerform(withItems: [url]) {
            service.perform(withItems: [url])
        }
    }
}

struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(color.opacity(0.1)))
        }
        .buttonStyle(.borderless)
    }
}
