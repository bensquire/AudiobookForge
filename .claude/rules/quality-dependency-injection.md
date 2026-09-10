---
title: Dependencies and Settings Are Handed In as Values
impact: HIGH
impactDescription: Code that reaches for a global cannot be tested, varied or reused without it
tags: [quality, dependency-injection, values, testability]
paths: ["ForgeCore/**/*.swift", "ForgeCLI/**/*.swift", "AudiobookForgeTests/**/*.swift"]
---

## Dependencies and Settings Are Handed In as Values

**Impact: HIGH**

A type takes its collaborators and its settings as values, and whoever calls
it hands them in. `EncodeJob` takes an `EncodeSpec` and a progress callback at
init; `EncodeSettings` carries bitrate, gain and template; `LibraryScanner`
takes its chapter probe as a closure; `SettingsStore.load(defaults:)` takes the
`UserDefaults`. No singletons in the work itself, no reading the environment
or the disk inside it. The environment is read only at the edges: `Forge.main`
reads `FORGE_FFMPEG_DIR` once and tells `Bundled`; the app delegate wires
notifications into `QueueManager`'s callbacks. Tests hand in a temp directory,
a fixture URL, a suite-named `UserDefaults`.

When a knob is added, it is added once — on the type that uses it — and reached
through the value that carries that type, not mirrored as a second flag on
every caller.

**Incorrect (a setting read from the environment inside the encoder; a callback set later by reaching in):**

```swift
let cap = Int(ProcessInfo.processInfo.environment["FORGE_JOBS"] ?? "4")!
job.onProgress = { … }            // mutable state on a job that is otherwise immutable
```

**Correct:**

```swift
let job = EncodeJob(spec: spec) { fraction, label in … }
let scanner = LibraryScanner(chapterFormat: probe)
```
