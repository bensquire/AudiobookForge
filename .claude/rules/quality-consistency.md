---
title: Match the Code Around You
impact: HIGH
impactDescription: One idiom for one job, so a reader learns it once
tags: [quality, consistency, idioms, reuse]
paths: ["ForgeCore/**/*.swift", "AudiobookForge/**/*.swift", "ForgeCLI/**/*.swift", "AudiobookForgeTests/**/*.swift"]
---

## Match the Code Around You

**Impact: HIGH**

New code reads like the file it lands in: the same naming, comment density,
error style, and idioms. Before writing a helper, look for the one that exists
— `FileManager.isDirectory(at:)`, `ChapterImport.chapter(for:probed:)`,
`ConcurrencyLimiter.hardwareCap`, `PercentGate`,
`EncodeJob.ebur128MeasureArgs`, `OutputPathResolver.uniqueURL` — and call it.
In tests, `AudioFixtures.swift` has the WAV writer, the AAC fixture, the
chapter and spec builders, the loudness and frequency probes, `waitUntil`, and
the `FFmpegTestCase` base; `QueueTestCase` has the draft builder. A second
spelling of the same thing — the percent gate written out twice, the
`ObjCBool` directory check in four files — is a bug waiting for one of them to
drift.

**Incorrect (a fresh spelling of an existing helper):**

```swift
var isDir: ObjCBool = false
guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { … }
```

**Correct:**

```swift
guard FileManager.default.isDirectory(at: url) else { … }
```
