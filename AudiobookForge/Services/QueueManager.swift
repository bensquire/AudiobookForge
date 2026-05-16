import Foundation
import Observation

/// Owns the encode queue and a single background worker that processes
/// pending items serially. UI observes `items` directly.
@MainActor
@Observable
final class QueueManager {
    var items: [QueueItem] = []

    private var running: (item: QueueItem, job: EncodeJob)?
    private var pumpWakeup: CheckedContinuation<Void, Never>?
    private var pumpTask: Task<Void, Never>?

    var isProcessing: Bool {
        running != nil
    }

    init() {
        pumpTask = Task { @MainActor [weak self] in
            await self?.pumpLoop()
        }
    }

    // MARK: - Public API

    /// What the queue *would* write to disk if the draft were enqueued
    /// right now. Shared by the live "Will save as…" hint and `enqueue` so
    /// the preview and reality can't diverge.
    func plannedOutputURL(for draft: AudiobookProject) -> URL? {
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
    func enqueue(from draft: AudiobookProject) -> QueueItem? {
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

    func cancel(_ item: QueueItem) {
        if item.id == running?.item.id {
            running?.job.cancelToken.cancel()
        } else if item.status.isPending {
            item.status = .cancelled
        }
    }

    func remove(_ item: QueueItem) {
        if item.id == running?.item.id {
            cancel(item)
            return
        }
        items.removeAll { $0.id == item.id }
    }

    /// Move a finished item back into the queue. Output path is re-deduped
    /// so a retry doesn't clobber a previous successful sibling.
    func retry(_ item: QueueItem) {
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

    func clearFinished() {
        items.removeAll { $0.status.isFinished }
    }

    // MARK: - Worker loop

    private func pumpLoop() async {
        while !Task.isCancelled {
            guard let next = items.first(where: { $0.status.isPending }) else {
                await waitForWork()
                continue
            }
            await process(next)
        }
    }

    private func waitForWork() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.pumpWakeup = cont
        }
    }

    private func wakePump() {
        if let cont = pumpWakeup {
            pumpWakeup = nil
            cont.resume()
        }
    }

    private func process(_ item: QueueItem) async {
        item.status = .running
        item.progress = 0
        item.progressLabel = "Starting…"

        if let problem = preflight(item) {
            let msg = (problem as? LocalizedError)?.errorDescription ?? "\(problem)"
            item.status = .failed(msg)
            item.progressLabel = nil
            return
        }

        let job = EncodeJob(spec: item.spec)
        job.onProgress = { [weak item] frac, label in
            guard let item else { return }
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
            item.status = .succeeded
        } catch let e as FFmpegRunner.RunError {
            if case .cancelled = e {
                item.status = .cancelled
            } else {
                item.status = .failed(e.errorDescription ?? "\(e)")
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            item.status = .failed(msg)
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
