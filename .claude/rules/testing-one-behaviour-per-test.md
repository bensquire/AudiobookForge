---
title: One Behaviour Per Test, Named as a Sentence
impact: HIGH
impactDescription: A test of several things fails for one and hides the rest
tags: [testing, naming, scope, xctest]
paths: ["AudiobookForgeTests/**/*.swift"]
---

## One Behaviour Per Test, Named as a Sentence

**Impact: HIGH**

A test pins one behaviour, and its name says which, as
`test_subject_behaviour` that reads in the report:
`test_stitch_remux_ordersChaptersAtCorrectBoundariesWithCorrectAudio`,
`test_cancel_whileRunning_terminatesTheJobAndMarksCancelled`. A name with
"and" in it that lists unrelated checks is usually two tests (a name with
"and" that describes one observable outcome is fine). When the same behaviour
is asked of several inputs, loop over a table inside one test with the input
in every message, rather than copy the test.

Test the behaviour, not the implementation: what the decoded output sounds
like, where the chapter markers fall, what the queue item reports — not which
private function ran. `@testable` is for reaching a real internal seam like
`LineBuffer` or `EncodeJob.ebur128MeasureArgs`, not for asserting on
scaffolding.

**Incorrect:**

```swift
func test_encodeWorks() {
    // checks duration, chapters, tags, bitrate and loudness in one go
}
```

**Correct:**

```swift
func test_gain_off_preservesSourceLoudness() async throws { … }
func test_gain_manualBoost_raisesLoudnessByExactlyThatMuch() async throws { … }
func test_lineBuffer_holdsPartialLineAcrossChunks() { … }
```
