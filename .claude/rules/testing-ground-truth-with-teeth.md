---
title: Ground Truth Is the Decoded Audio, and the Bar Has Teeth
impact: HIGH
impactDescription: Metadata can say "57 chapters" on a file whose audio is in the wrong order
tags: [testing, ground-truth, audio, loudness, fixtures]
paths: ["AudiobookForgeTests/**/*.swift"]
---

## Ground Truth Is the Decoded Audio, and the Bar Has Teeth

**Impact: HIGH**

A fixture is a generated tone with a known frequency and a known loudness, so
the output can be judged by decoding it: the tone heard in the middle of each
chapter (`dominantFrequency`) proves which audio landed where; the integrated
loudness (`integratedLoudness`, the same ebur128 pass the encoder uses)
proves what a gain mode did. Chapter markers and tags are checked too, but
they are not the proof. When a test says a result is good, it also says,
where it can, what the alternative would have measured, so the bar cannot be
cleared by accident: a lift-only book is checked against its *source*
loudness, not the target, because "reached -16 LUFS" would also pass a mode
that attenuates. A tolerance carries the reason for its size. When a bug is
fixed, a test pins it, with the measurement that showed it.

**Incorrect (a bar with no teeth — passes on an encode that did nothing):**

```swift
XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
XCTAssertEqual(markers.count, 3)
```

**Correct (the audio itself, and the alternative measured too):**

```swift
let hz = try await dominantFrequency(of: out, start: 2.5, duration: 1)
XCTAssertEqual(hz, 600, accuracy: 30, "audio inside chapter Two")
let result = try await integratedLoudness(of: loudOut)
XCTAssertEqual(result, loudSource, accuracy: 0.75)   // untouched, not "at target"
```
