---
title: Fast Where It Counts, and Measured
impact: HIGH
impactDescription: Twelve ffmpeg children each report twice a second; a drop of 500 files probes them all
tags: [quality, performance, concurrency, ffmpeg, allocation]
paths: ["ForgeCore/**/*.swift"]
---

## Fast Where It Counts, and Measured

**Impact: HIGH**

The cost is in a few places — the ffmpeg fan-out (bounded by
`ConcurrencyLimiter.hardwareCap`, at most 12 children), the progress callback
(gated to whole percents by `PercentGate` so a report is not a Task spawn and
an actor hop), and the probe pass over a dropped folder (bounded inside
`captureStderr` so no caller can forget). Those are written for the machine;
everything else is written for the reader. Which is which is decided by
measuring: the suite's own time, `-stats_period` in a test, `time` on a real
encode, and a comment on a fast path says what it cost before and after.

Do not optimise prose code, and do not leave a hot path allocating. A
long-lived object built from a closure keeps its whole scope alive; a struct
copies the fields it needs.

**Incorrect (a Task per progress tick; unbounded fan-out):**

```swift
onProgress: { frac, _ in Task { await aggregator.report(…) } }   // ~2/s × 12 children, mostly no-ops
for url in files { group.addTask { await AudioProbe.probe(url) } }  // 500 ffmpegs at once
```

**Correct (gated, bounded, and the measurement kept):**

```swift
onProgress: { frac, secs in
    guard gate.step(frac) != nil else { return }   // 99 % of reports stop here
    Task { await aggregator.report(chunk: index, seconds: secs) … }
}
```
