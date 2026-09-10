---
title: Code Reads Like the Prose Around It
impact: HIGH
impactDescription: The next reader is a person, usually months later, often the author
tags: [quality, readability, naming]
paths: ["ForgeCore/**/*.swift", "AudiobookForge/**/*.swift", "ForgeCLI/**/*.swift", "AudiobookForgeTests/**/*.swift"]
---

## Code Reads Like the Prose Around It

**Impact: HIGH**

Names say what a thing is in the words the domain uses — `canRemux`,
`partitionFinished`, `plannedOutputURL`, `hasDraftWork` — so a call site reads
as a sentence. Short names are right where the convention uses them (`i`,
`url`, `pct`) and wrong anywhere else. A function does what its name says and
nothing more; one that needs "and" in its name is two. Nesting is shallow; the
early `guard` says what a function refuses. No cleverness that needs a comment
to decode — if the trick is necessary, the comment explains why it is, with
the measurement.

**Incorrect:**

```swift
func proc(_ c: [Chapter], _ s: EncodeSettings, _ f: Bool) -> [String] {
    if f { if c.count > 0 { /* … forty lines … */ } }
    return []
}
```

**Correct:**

```swift
/// Whether every chapter can be concatenated with `-c:a copy` at the user's setting.
static func canRemux(chapters: [Chapter], settings: EncodeSettings) -> Bool {
    guard settings.bitrate == .source, settings.gainBoost == .off else { return false }
    …
}
```
