---
title: A Comment Is Short, and Says Why
impact: HIGH
impactDescription: A comment costs every reader time and every token money; it earns that or it goes
tags: [quality, comments, documentation, measurements, brevity]
paths: ["ForgeCore/**/*.swift", "AudiobookForge/**/*.swift", "ForgeCLI/**/*.swift"]
---

## A Comment Is Short, and Says Why

**Impact: HIGH**

A comment adds what the code cannot say — why this, what was measured, what was
rejected — in as few plain words as will still read. It never restates a method
or property name. A claim carries its measurement: file, before, after. A
constant carries the measurement that set it. No flourish, no anecdote told
twice, no comment about code that has gone (the branch once carried a
paragraph about a `nonisolated` keyword that no longer existed).

**Incorrect (restates the name; no provenance; flowery):**

```swift
/// Returns the hardware cap.
static let hardwareCap = 12

/// The measurement cap. We found through extensive experimentation across a
/// wide variety of audiobooks that two minutes is more than sufficient …
```

**Correct (the why and the number, then stop):**

```swift
/// EBU R128's integrated value settles within ~30–60 s of continuous speech;
/// two minutes is ~0.3 LU from the full-file figure on typical chapters.
static let ebur128MeasureCapSeconds: Int = 120
```
