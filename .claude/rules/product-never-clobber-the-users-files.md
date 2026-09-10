---
title: The User's Files Are Never Clobbered
impact: CRITICAL
impactDescription: An audiobook library is years of files; one overwrite or one flattened book is unrecoverable
tags: [product, files, safety, output, import]
paths: ["ForgeCore/**/*.swift", "AudiobookForge/**/*.swift", "ForgeCLI/**/*.swift"]
---

## The User's Files Are Never Clobbered

**Impact: CRITICAL**

- **Sources are read, never written.** Nothing touches a chapter file: no tag
  rewrite, no move, no delete.
- **Output lands in one rename.** Every encode writes `<name>.m4b.partial`
  beside the destination and renames on success, so a cancel or a crash leaves
  no stub `.m4b` and nothing half-written at the final path.
- **A collision is a new name, never an overwrite.** `OutputPathResolver`
  bumps to `Title (2).m4b`, `(3)`, … against the disk *and* the queue's
  in-flight paths, at enqueue and again at encode start.
- **A finished book is refused on import.** A file that already carries
  chapters (mp4 `chpl`/`chap`, ID3 `CHAP`) is a forged audiobook; importing it
  as one chapter would silently flatten it. `ChapterImport.partitionFinished`
  keeps it out and the alert says why.
- **The CLI's manifest is state, not truth.** `forge scan` writes only under
  `stateDir`; it never writes into a library root.

**Incorrect (write straight to the destination; overwrite on collision):**

```swift
try FileManager.default.removeItem(at: finalURL)
args += [finalURL.path]
```

**Correct:**

```swift
let finalURL = OutputPathResolver.uniqueURL(for: spec.outputURL)
let partialURL = parent.appendingPathComponent(finalURL.lastPathComponent + ".partial")
// … ffmpeg writes partialURL …
try FileManager.default.moveItem(at: partialURL, to: finalURL)
```
