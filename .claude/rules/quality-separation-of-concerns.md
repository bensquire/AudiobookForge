---
title: Each Part Does One Job, and Knows Only Its Neighbours
impact: HIGH
impactDescription: ForgeCore is testable headlessly and shared with the CLI because nothing in it knows about a window
tags: [quality, architecture, separation-of-concerns, layers]
paths: ["ForgeCore/**/*.swift", "AudiobookForge/**/*.swift", "ForgeCLI/**/*.swift"]
---

## Each Part Does One Job, and Knows Only Its Neighbours

**Impact: HIGH**

The layers are the targets, and the dependencies run one way. `ForgeCore`
(probe, import rules, chapter file, encode, queue, metadata lookup, settings)
imports no AppKit or SwiftUI; `AudiobookForge` holds the views, the app
delegate and `QueueNotifier`, and calls the core; `ForgeCLI` is the same core
with a command line on it. Within the core, `FFmpegRunner` spawns and reads;
`AudioProbe` and `EncodeJob` decide what to run; `QueueManager` sequences jobs
and owns the UI-facing items; values (`EncodeSpec`, `Chapter`, `BookMetadata`,
`EncodeSettings`) flow between them and nothing reaches back.

A change that needs the core to import a UI framework, a view to build ffmpeg
arguments, or `FFmpegRunner` to know what a chapter is, is at the wrong layer.

**Incorrect (a view deciding something the core owns):**

```swift
let added = importable.map { url, p in
    Chapter(sourceURL: url, title: p.title ?? url.lastPathComponent, …)   // import policy in a view
}
```

**Correct (the core states the rule; the view applies it):**

```swift
// ForgeCore
public static func chapter(for url: URL, probed: AudioProbe.Probed) -> Chapter
// view
let added = importable.map { ChapterImport.chapter(for: $0.url, probed: $0.info) }
```
