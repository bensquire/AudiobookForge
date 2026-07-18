import Foundation

/// Run the bundled ffmpeg as a child process and surface progress + stderr.
/// Uses event-driven I/O (`readabilityHandler` + `terminationHandler`) so
/// neither stderr nor process-wait blocks a cooperative-pool thread for the
/// duration of the encode.
enum FFmpegRunner {
    enum RunError: Error, LocalizedError {
        case notFound
        case spawnFailed(String)
        case nonZeroExit(Int32, String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notFound: "ffmpeg binary not found"
            case let .spawnFailed(reason):
                "Couldn't launch the bundled ffmpeg: \(reason)"
            case let .nonZeroExit(code, tail):
                "ffmpeg exited with code \(code)\n\n…\(tail)"
            case .cancelled: "Cancelled"
            }
        }
    }

    /// Run ffmpeg. `totalDuration` lets us turn `time=` lines into a 0…1 fraction.
    @discardableResult
    static func run(
        arguments: [String],
        totalDuration: TimeInterval,
        onProgress: @escaping (Double, String) -> Void,
        cancelToken: CancelToken = .init()
    ) async throws -> String {
        guard let ffmpeg = Bundled.binary("ffmpeg") else { throw RunError.notFound }
        // A cancel (token or Task) that lands before we spawn means the
        // caller no longer wants the result — don't launch at all.
        if cancelToken.isCancelled || Task.isCancelled { throw RunError.cancelled }

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-hide_banner", "-nostdin", "-y"] + arguments

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice

        let tail = LineTail(capacity: 40)
        let buffer = LineBuffer()

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            for line in buffer.append(chunk) {
                tail.append(line)
                if let secs = Self.parseTime(line) {
                    let frac = totalDuration > 0
                        ? min(1.0, max(0.0, secs / totalDuration))
                        : 0
                    onProgress(frac, line.trimmingCharacters(in: .whitespaces))
                }
            }
        }

        // Swift Task cancellation folds into the shared token so that a
        // failing sibling in a task group (which cancels this task) also
        // terminates our ffmpeg child instead of letting it run to the end.
        let exitStatus: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                // Termination → continuation is wired BEFORE run() so we
                // can't miss an instant exit.
                process.terminationHandler = { proc in
                    cont.resume(returning: proc.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: RunError.spawnFailed(error.localizedDescription))
                    return
                }
                Self.armKill(cancelToken, process)
            }
        } onCancel: {
            cancelToken.cancel()
        }

        // Drain any tail bytes ffmpeg flushed just before exit.
        stderr.fileHandleForReading.readabilityHandler = nil
        let remaining = stderr.fileHandleForReading.readDataToEndOfFile()
        if !remaining.isEmpty {
            for line in String(decoding: remaining, as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: false)
            {
                tail.append(String(line))
            }
        }

        if cancelToken.isCancelled { throw RunError.cancelled }
        if exitStatus != 0 {
            throw RunError.nonZeroExit(exitStatus, tail.joined())
        }
        return tail.joined()
    }

    /// One-shot ffmpeg invocation that captures full stderr. Used by
    /// short metadata probes and the ebur128 measurement pass. Returns
    /// nil if the bundled binary is missing or `process.run()` throws.
    /// If `cancelToken` fires mid-run, the child is terminated and any
    /// stderr captured so far is returned (callers typically treat that
    /// as "couldn't measure" and fall back).
    static func captureStderr(
        arguments: [String],
        cancelToken: CancelToken = .init()
    ) async -> String? {
        guard let ffmpeg = Bundled.binary("ffmpeg") else { return nil }
        if cancelToken.isCancelled { return nil }

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-hide_banner", "-nostdin"] + arguments

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice

        // Drain stderr proactively. Filters like `ebur128` print
        // continuously; reading only inside `terminationHandler` lets
        // the kernel pipe buffer (~64 KB) fill, ffmpeg blocks on its
        // next write, and the process never exits → deadlock with zero
        // CPU. Same pattern as `run()`.
        let buffer = StderrBuffer()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
        }

        return await withCheckedContinuation { cont in
            process.terminationHandler = { _ in
                stderr.fileHandleForReading.readabilityHandler = nil
                let remaining = stderr.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty { buffer.append(remaining) }
                cont.resume(returning: buffer.text())
            }
            do {
                try process.run()
            } catch {
                stderr.fileHandleForReading.readabilityHandler = nil
                cont.resume(returning: nil)
                return
            }
            Self.armKill(cancelToken, process)
        }
    }

    /// Register `process.terminate()` on the token. Must be called only
    /// AFTER a successful `process.run()` — `terminate()` on a
    /// never-launched Process raises an ObjC exception. `setOnCancel`
    /// fires the handler immediately if the token was cancelled while
    /// we were spawning, so the gap is covered.
    private static func armKill(_ token: CancelToken, _ process: Process) {
        token.setOnCancel { [weak process] in
            guard let process, process.isRunning else { return }
            process.terminate()
        }
    }

    /// Parse `…time=01:23:45.67 …` from an ffmpeg progress line.
    private static func parseTime(_ line: String) -> TimeInterval? {
        guard let range = line.range(of: "time=") else { return nil }
        let after = line[range.upperBound...]
        let token = after.prefix { !$0.isWhitespace }
        let parts = token.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2])
        else { return nil }
        return h * 3600 + m * 60 + s
    }
}

/// Thread-safe cancellation signal shared between caller (any actor) and
/// the ffmpeg invocation. `cancel()` may arrive from the UI's MainActor
/// while `run()` is reading stderr on a background queue.
///
/// Handlers are **appended**, not replaced — multiple layers can each
/// register interest in the cancel without clobbering each other. (This
/// matters for EncodeJob, which both cascades to per-chunk tokens AND
/// passes the token to `FFmpegRunner.run` which registers its own
/// `process.terminate()` handler.)
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false
    private var handlers: [() -> Void] = []

    init() {}

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isCancelled
    }

    /// A token that cancels when this one does. A child created after
    /// the parent was already cancelled is born cancelled (`setOnCancel`
    /// fires immediately), which closes the "cancel landed before the
    /// child existed" race in one place instead of per call site.
    func makeChild() -> CancelToken {
        let child = CancelToken()
        setOnCancel { child.cancel() }
        return child
    }

    func setOnCancel(_ handler: @escaping () -> Void) {
        lock.lock()
        let wasCancelled = _isCancelled
        if !wasCancelled { handlers.append(handler) }
        lock.unlock()
        // If we were already cancelled before the handler was registered,
        // fire it immediately so the caller doesn't miss the signal.
        if wasCancelled { handler() }
    }

    func cancel() {
        lock.lock()
        if _isCancelled {
            lock.unlock()
            return
        }
        _isCancelled = true
        let snapshot = handlers
        handlers.removeAll()
        lock.unlock()
        snapshot.forEach { $0() }
    }
}

/// Drain target for `captureStderr` — raw bytes, locked so the
/// readabilityHandler closure can append concurrently with the
/// terminationHandler's final flush.
private final class StderrBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    func text() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Accumulates bytes from `readabilityHandler` and yields complete lines.
/// Locked so the captured reference can be used from the Sendable closure.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var lines: [String] = []
        while let nl = data.firstIndex(of: 0x0A) {
            let lineData = data.subdata(in: 0 ..< nl)
            data.removeSubrange(0 ... nl)
            lines.append(String(decoding: lineData, as: UTF8.self))
        }
        return lines
    }
}

/// Bounded ring of recent stderr lines for failure tail reporting. Appended
/// to from the I/O queue, read once after exit — locked because both sides
/// can race on the final flush.
final class LineTail: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    func append(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        lines.append(s)
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
    }

    func joined() -> String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}
