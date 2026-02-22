//
//  TaskInspectorView.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import SwiftUI
import Charts

/// 任务详情检查器 (右侧面板)
struct TaskInspectorView: View {
    @Bindable var task: IPADownloadTask
    var onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                // Icon
                AsyncImage(url: task.iconURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "app")
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 2, y: 1)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.appName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    
                    HStack {
                        Text("v\(task.displayVersion)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        
                        // Status Badge
                        Text(task.status.displayName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.1))
                            .foregroundStyle(statusColor)
                            .clipShape(Capsule())
                    }
                }
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // 速度走势 (仅在有数据时显示)
                    if !task.speedHistory.isEmpty {
                        InspectorSection(title: "速度走势") {
                            Text("\(task.speed)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Capsule())
                        } content: {
                            SpeedChartView(history: task.speedHistory, isComplete: task.status == .completed)
                                .frame(height: 120)
                        }
                    }
                    
                    // 分块进度 (模拟)
                    InspectorSection(title: "分块进度") {
                        // 简单的进度条模拟分块
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.1))
                                Capsule()
                                    .fill(statusColor)
                                    .frame(width: geo.size.width * task.progress)
                            }
                        }
                        .frame(height: 8)
                        
                        HStack {
                            Text("\(Int(task.progress * 100))%")
                            Spacer()
                            Text(task.sizeProgressString)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    
                    // 下载信息
                    InspectorSection(title: "下载") {
                        InspectorRow(label: "链接", value: task.downloadURL ?? "-")
                        InspectorRow(label: "保存位置", value: task.filePath?.path ?? "等待中")
                        InspectorRow(label: "MD5", value: task.md5 ?? "-")
                    }
                    
                    // 进度
                    InspectorSection(title: "进度") {
                        InspectorRow(label: "已下载", value: ByteCountFormatter.string(fromByteCount: task.receivedBytes, countStyle: .file))
                        InspectorRow(label: "总大小", value: ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file))
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 320)
        .background(Color.platformControlBackground)
        .overlay(alignment: .leading) {
            Divider()
        }
    }
    
    private var statusColor: Color {
        switch task.status {
        case .downloading: return .blue
        case .completed: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}

struct InspectorSection<Header: View, Content: View>: View {
    let title: String
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content
    
    init(title: String, @ViewBuilder header: () -> Header = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.header = header()
        self.content = content()
    }
    
    // Convenience for no header
    init(title: String, @ViewBuilder content: () -> Content) where Header == EmptyView {
        self.init(title: title, header: { EmptyView() }, content: content)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                header
            }
            
            VStack(spacing: 8) {
                content
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary.opacity(0.5))
            }
        }
    }
}

struct InspectorRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

struct SpeedChartView: View {
    let history: [Int64]
    var isComplete: Bool
    
    // Smooth the data
    private var smoothedHistory: [Int64] {
        guard history.count > 4 else { return history }
        let windowSize = 3
        var result: [Int64] = []
        for i in 0..<history.count {
            let start = max(0, i - windowSize / 2)
            let end = min(history.count - 1, i + windowSize / 2)
            let window = history[start...end]
            let avg = window.reduce(0, +) / Int64(window.count)
            result.append(avg)
        }
        return result
    }
    
    var body: some View {
        Chart {
            ForEach(Array(smoothedHistory.enumerated()), id: \.offset) { index, speed in
                LineMark(
                    x: .value("Time", index),
                    y: .value("Speed", Double(speed))
                )
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Time", index),
                    y: .value("Speed", Double(speed))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden) // Minimalist look for sidebar
    }
}
