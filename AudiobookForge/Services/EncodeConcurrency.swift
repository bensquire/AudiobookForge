import Foundation

/// Counting semaphore — async/await flavour. `acquire()` suspends when
/// `inFlight` would exceed `max`; `release()` wakes the next waiter (FIFO).
/// Used by the parallel-encode phase to cap how many ffmpeg children we
/// spawn at once. The cap prevents pathological fan-out on long books
/// (a 100-chapter audiobook shouldn't try to run 100 ffmpegs in
/// parallel — most cores would just queue on the scheduler anyway and
/// disk contention would actually slow things down).
actor ConcurrencyLimiter {
    private let cap: Int
    private var inFlight: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(max: Int) {
        precondition(max >= 1, "ConcurrencyLimiter cap must be positive")
        cap = max
    }

    func acquire() async {
        if inFlight < cap {
            inFlight += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            // Hand the slot directly to the waiter — don't dec+inc.
            next.resume()
        } else {
            inFlight -= 1
        }
    }
}

/// Sums per-chunk encode progress (in seconds of source audio processed)
/// into a single 0…1 fraction for the parallel-encode UI. Each chunk is
/// clamped to its own duration so a late `time=` line can't overshoot
/// and push the total past 100%.
///
/// Phase 1 (the encode fan-out) reports 0..0.95 of the bar; Phase 2 (the
/// final `-c:a copy` concat) takes 0.95..1.0 — that step is seconds even
/// for long books so a flat jump there is fine.
actor ProgressAggregator {
    private let total: TimeInterval
    private let chunkDurations: [TimeInterval]
    private var perChunk: [Int: TimeInterval] = [:]

    init(chunkDurations: [TimeInterval]) {
        self.chunkDurations = chunkDurations
        total = chunkDurations.reduce(0, +)
    }

    func report(chunk: Int, seconds: TimeInterval) {
        guard chunkDurations.indices.contains(chunk) else { return }
        let capped = min(seconds, chunkDurations[chunk])
        perChunk[chunk] = max(perChunk[chunk] ?? 0, capped)
    }

    /// 0..0.95. Phase 2 picks up at 0.95.
    var phase1Fraction: Double {
        guard total > 0 else { return 0 }
        let sum = perChunk.values.reduce(0, +)
        return min(0.95, (sum / total) * 0.95)
    }
}
