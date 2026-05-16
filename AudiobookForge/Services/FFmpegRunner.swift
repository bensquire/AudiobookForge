import Foundation

/// Run the bundled ffmpeg as a child process and surface progress + stderr.
/// Uses event-driven I/O (`readabilityHandler` + `terminationHandler`) so
/// neither stderr nor process-wait blocks a cooperative-pool thread for the
/// duration of the encode.
struct FFmpegRunner {
    enum RunError: Error, LocalizedError {
        case notFound
        case nonZeroExit(Int32, String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notFound: return "ffmpeg binary not found"
            case .nonZeroExit(let code, let tail):
                return "ffmpeg exited with code \(code)\n\n…\(tail)"
            case .cancelled: return "Cancelled"
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

        // Set up termination → continuation BEFORE run() so we can't miss it.
        let exitStatus: Int32 = await withCheckedContinuation { cont in
            process.terminationHandler = { proc in
                cont.resume(returning: proc.terminationStatus)
            }
            cancelToken.setOnCancel { [weak process] in
                process?.terminate()
            }
            do {
                try process.run()
            } catch {
                cont.resume(returning: -1)
            }
        }

        // Drain any tail bytes ffmpeg flushed just before exit.
        stderr.fileHandleForReading.readabilityHandler = nil
        let remaining = stderr.fileHandleForReading.readDataToEndOfFile()
        if !remaining.isEmpty {
            for line in String(decoding: remaining, as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: false) {
                tail.append(String(line))
            }
        }

        if cancelToken.isCancelled { throw RunError.cancelled }
        if exitStatus != 0 {
            throw RunError.nonZeroExit(exitStatus, tail.joined())
        }
        return tail.joined()
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
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false
    private var _onCancel: (() -> Void)?

    init() {}

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isCancelled
    }

    func setOnCancel(_ handler: @escaping () -> Void) {
        lock.lock()
        let wasCancelled = _isCancelled
        _onCancel = handler
        lock.unlock()
        // If we were already cancelled before the handler was set, fire it
        // immediately so the caller doesn't miss the signal.
        if wasCancelled { handler() }
    }

    func cancel() {
        lock.lock()
        _isCancelled = true
        let handler = _onCancel
        lock.unlock()
        handler?()
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
            let lineData = data.subdata(in: 0..<nl)
            data.removeSubrange(0...nl)
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

    init(capacity: Int) { self.capacity = capacity }

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
