---
title: A Failure Reads as a Sentence
impact: MEDIUM
impactDescription: A bare comparison fails as a pair of numbers with no story
tags: [testing, assertions, messages, xctest]
paths: ["AudiobookForgeTests/**/*.swift"]
---

## A Failure Reads as a Sentence

**Impact: MEDIUM**

An `XCTAssert…` carries a message that says what was measured and what it
was, unless the expression already says it (`queue.items.isEmpty`). In a loop
the message names the input. `XCTUnwrap` for the thing the rest of the test
cannot run without, with a message saying what was missing. A helper that
asserts on the caller's behalf takes `file:` and `line:` so the failure lands
on the test, not the helper.

**Incorrect:**

```swift
XCTAssertEqual(hz, p.hz, accuracy: p.hz * 0.05)
XCTAssertGreaterThanOrEqual(seen.count, 3)
```

**Correct:**

```swift
XCTAssertEqual(hz, p.hz, accuracy: p.hz * 0.05, "audio inside \(p.name)", file: file, line: line)
XCTAssertGreaterThanOrEqual(seen.count, 3, "expected multiple progress reports, got \(seen)")
let stderr = try XCTUnwrap(captured, "ffmpeg produced no stderr")
```
