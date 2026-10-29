#if os(macOS)
import Foundation
import Darwin

/// Process 生命周期由锁保护，取消可以在启动之前或运行期间到达。
/// 通过 terminationHandler 收尾，避免跨线程调用 waitUntilExit 的运行循环依赖。
nonisolated final class UnfairPlayProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var started = false
    private var cancelled = false

    init(executable: URL, arguments: [String], log: FileHandle) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice
    }

    private func launch(_ continuation: CheckedContinuation<Int32, any Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { continuation.resume(throwing: CancellationError()); return }
        process.terminationHandler = { process in
            continuation.resume(returning: process.terminationReason == .exit ? process.terminationStatus : -1)
        }
        do {
            try process.run()
            started = true
        } catch {
            process.terminationHandler = nil
            continuation.resume(throwing: error)
        }
    }

    private func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if started && process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    func run() async throws -> Int32 {
        try await withTaskCancellationHandler {
            let status = try await withCheckedThrowingContinuation { launch($0) }
            try Task.checkCancellation()
            return status
        } onCancel: { self.cancel() }
    }
}
#endif
