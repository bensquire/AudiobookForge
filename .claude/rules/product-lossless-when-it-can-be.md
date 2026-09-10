---
title: Lossless When It Can Be
impact: CRITICAL
impactDescription: A book that could have been remuxed and was re-encoded instead lost quality for nothing
tags: [product, remux, aac, lossless, encode]
paths: ["ForgeCore/**/*.swift"]
---

## Lossless When It Can Be

**Impact: CRITICAL**

When every chapter is already AAC with one sample rate and channel layout and
the user asked for "Match source", the book is remuxed: one ffmpeg over the
concat demuxer with `-c:a copy`, seconds for a 25-hour book and not one sample
touched. Re-encoding happens only when something must change the samples — a
non-AAC source, a chosen bitrate, any gain mode. `EncodeJob.canRemux` is the
one place that decision is made, and a change that would send a remuxable book
down the encode path (a filter added unconditionally, a default bitrate that is
not `.source`) breaks the promise.

**Incorrect (a filter that forces every book through the encoder):**

```swift
args += ["-af", "aresample=44100"]   // now nothing can be copied
```

**Correct (the remux path stays reachable; the encoder is for what needs it):**

```swift
if Self.canRemux(chapters: spec.chapters, settings: spec.settings) {
    try await runRemuxOnePass(…)      // -c:a copy
} else {
    try await runReencodeParallel(…)  // libfdk_aac, per chapter, then concat-copy
}
```
