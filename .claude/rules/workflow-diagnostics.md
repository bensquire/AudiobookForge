---
title: Diagnostics Are Gated to Keep, Separate to Throw Away
impact: MEDIUM
impactDescription: A debug block woven into the encoder has to be edited out of the encoder
tags: [workflow, diagnostics, environment, ffmpeg]
paths: ["ForgeCore/**", "ForgeCLI/**"]
---

## Diagnostics Are Gated to Keep, Separate to Throw Away

**Impact: MEDIUM**

Diagnostics worth keeping are gated behind a `FORGE_*` environment variable
and read once, at the edge: `FORGE_FFMPEG_DIR` is read in `Forge.main` and
handed to `Bundled`, never inside ForgeCore. ffmpeg's own stderr is already
captured — the failure tail on a non-zero exit, the banner for probes — so a
diagnostic is usually "keep more of what ffmpeg said", not a new print.
Diagnostics for one investigation go in a separate file, marked temporary,
and are deleted before handover — never woven into `EncodeJob`, where
stripping them means editing the encoder.

**Incorrect (a dump inline in the encode loop):**

```swift
if ProcessInfo.processInfo.environment["DEBUG_ARGS"] != nil {
    print(args.joined(separator: " "))   // in phase 1, between the limiter and run()
}
```

**Correct (its own file, one call, one deletion; or a kept, gated switch read at the edge):**

```swift
// ForgeCLI/Debug.swift — TEMPORARY, not for commit
func dumpPlan(_ spec: EncodeSpec) { … }

// Forge.main
if let dir = ProcessInfo.processInfo.environment["FORGE_FFMPEG_DIR"] {
    Bundled.setOverrideDirectory(URL(fileURLWithPath: dir))
}
```
