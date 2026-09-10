import Foundation
import Observation

/// Owns the encode queue and a single background worker that processes
/// pending items serially. UI observes `items` directly.
@MainActor
@Observable
public final class QueueManager {
    public var items: [QueueItem] = []

    private var running: (item: QueueItem, job: EncodeJob)?
    /// The worker parks on this stream between batches. Yielding wakes
    /// it; finishing it (deinit / `shutdown()`) ends the loop. The
    /// worker holds `self` only while draining, so an idle manager can
    /// actually be deallocated — a parked `CheckedContinuation` inside a
    /// method on `self` never could.
    private let wake: AsyncStream<Void>.Continuation
    private var pumpTask: Task<Void, Never>?

    /// Held while a batch is being processed. Keeps the system awake and
    /// exempts us from App Nap — a multi-hour encode with the window
    /// occluded or the lid closed must not be throttled or suspended.
    private var activityToken: NSObjectProtocol?
    private var batchSucceeded = 0
    private var batchFailed = 0

    /// Fired when the worker picks up the first item of a batch — the app
    /// layer uses this to request notification permission at a moment the
    /// user has clearly started long-running work.
    public var onBatchStarted: () -> Void = {}
    /// Fired when the queue drains after processing ≥1 item, with the
    /// batch's succeeded/failed counts. Default no-op keeps unit tests
    /// free of UserNotifications (which needs a host app bundle).
    public var onBatchFinished: (_ succeeded: Int, _ failed: Int) -> Void = { _, _ in }

    public var isProcessing: Bool {
        running != nil
    }

    public init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        wake = continuation
        pumpTask = Task { @MainActor [weak self] in
            for await _ in stream {
                guard let self else { return }
                await drain()
            }
        }
    }

    deinit {
        wake.finish()
    }

    /// Stop everything for app termination: pending items are cancelled,
    /// the running ffmpeg children are terminated, and this returns once
    /// the worker has unwound — so `.partial` files and the work
    /// directory are cleaned up before the process exits rather than
    /// orphaned with ffmpeg still writing into them.
    public func shutdown() async {
        for item in items where item.status.isPending {
            item.status = .cancelled
        }
        running?.job.cancelToken.cancel()
        wake.finish()
        pumpTask?.cancel()
        await pumpTask?.value
        pumpTask = nil
    }

    // MARK: - Public API

    /// What the queue *would* write to disk if the draft were enqueued
    /// right now. Shared by the live "Will save as…" hint and `enqueue` so
    /// the preview and reality can't diverge.
    public func plannedOutputURL(for draft: AudiobookProject) -> URL? {
        guard let outDir = draft.settings.outputDirectory else { return nil }
        let desired = EncodeJob.resolveOutputURL(
            in: outDir,
            metadata: draft.metadata,
            template: draft.settings.filenameTemplate
        )
        let claimed = inFlightOutputURLs()
        return OutputPathResolver.uniqueURL(for: desired) { claimed.contains($0) }
    }

    @discardableResult
    public func enqueue(from draft: AudiobookProject) -> QueueItem? {
        guard draft.canEnqueue, let outURL = plannedOutputURL(for: draft) else {
            return nil
        }

        let spec = EncodeSpec(
            chapters: draft.chapters,
            metadata: draft.metadata,
            settings: draft.settings,
            outputURL: outURL
        )

        var fingerprints: [URL: SourceFingerprint] = [:]
        for c in draft.chapters {
            if let fp = SourceFingerprint.capture(c.sourceURL) {
                fingerprints[c.sourceURL] = fp
            }
        }

        let item = QueueItem(spec: spec, sourceFingerprints: fingerprints)
        items.append(item)
        wakePump()
        return item
    }

    public func cancel(_ item: QueueItem) {
        if item.id == running?.item.id {
            running?.job.cancelToken.cancel()
        } else if item.status.isPending {
            item.status = .cancelled
        }
    }

    public func remove(_ item: QueueItem) {
        if item.id == running?.item.id {
            cancel(item)
            return
        }
        items.removeAll { $0.id == item.id }
    }

    /// Move a finished item back into the queue. Output path is re-deduped
    /// so a retry doesn't clobber a previous successful sibling.
    public func retry(_ item: QueueItem) {
        guard item.status.isFinished else { return }
        let claimed = inFlightOutputURLs()
        let outURL = OutputPathResolver.uniqueURL(for: item.spec.outputURL) {
            claimed.contains($0)
        }
        var spec = item.spec
        spec.outputURL = outURL
        let fresh = QueueItem(spec: spec, sourceFingerprints: item.sourceFingerprints)
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = fresh
        } else {
            items.append(fresh)
        }
        wakePump()
    }

    public func clearFinished() {
        items.removeAll { $0.status.isFinished }
    }

    // MARK: - Worker loop

    /// Run every pending item to completion, then close the batch.
    private func drain() async {
        while !Task.isCancelled, let next = items.first(where: { $0.status.isPending }) {
            startBatchIfNeeded()
            await process(next)
        }
        finishBatch()
    }

    private func startBatchIfNeeded() {
        guard activityToken == nil else { return }
        onBatchStarted()
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Encoding audiobooks"
        )
    }

    private func finishBatch() {
        guard let token = activityToken else { return }
        ProcessInfo.processInfo.endActivity(token)
        activityToken = nil
        if batchSucceeded + batchFailed > 0 {
            onBatchFinished(batchSucceeded, batchFailed)
        }
        batchSucceeded = 0
        batchFailed = 0
    }

    private func wakePump() {
        wake.yield()
    }

    private func process(_ item: QueueItem) async {
        item.status = .running
        item.progress = 0
        item.progressLabel = "Starting…"

        if let problem = preflight(item) {
            let msg = (problem as? LocalizedError)?.errorDescription ?? "\(problem)"
            conclude(item, with: .failed(msg))
            item.progressLabel = nil
            return
        }

        let job = EncodeJob(spec: item.spec)
        job.onProgress = { [weak item] frac, label in
            // Progress hops arrive via unstructured Tasks and can land
            // after the job returned; don't let a late one overwrite
            // the terminal `progress = 1` / cleared label.
            guard let item, item.status.isRunning else { return }
            item.progress = frac
            item.progressLabel = label
        }
        running = (item, job)
        defer {
            running = nil
            item.progressLabel = nil
        }

        do {
            let finalURL = try await job.run()
            item.finalOutputURL = finalURL
            item.progress = 1
            conclude(item, with: .succeeded)
        } catch let e as FFmpegRunner.RunError {
            if case .cancelled = e {
                conclude(item, with: .cancelled)
            } else {
                conclude(item, with: .failed(e.errorDescription ?? "\(e)"))
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            conclude(item, with: .failed(msg))
        }
    }

    /// Single seam for terminal transitions so the batch counters can't
    /// drift from item status (cancelled counts as neither succeeded nor
    /// failed in the drain notification).
    private func conclude(_ item: QueueItem, with status: QueueItem.Status) {
        item.status = status
        switch status {
        case .succeeded: batchSucceeded += 1
        case .failed: batchFailed += 1
        default: break
        }
    }

    private func preflight(_ item: QueueItem) -> Error? {
        for chapter in item.spec.chapters {
            let url = chapter.sourceURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                return EncodeError.missingSourceFile(url)
            }
            if let expected = item.sourceFingerprints[url],
               let actual = SourceFingerprint.capture(url),
               actual != expected
            {
                return EncodeError.sourceChanged(url)
            }
        }
        return nil
    }

    /// Output URLs that pending or running items already plan to write —
    /// used so two back-to-back enqueues with the same template don't
    /// both target the same path.
    private func inFlightOutputURLs() -> Set<URL> {
        Set(items.compactMap { $0.status.isActive ? $0.spec.outputURL : nil })
    }
}
