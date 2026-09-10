---
title: Every Test Arranges, Acts and Asserts
impact: HIGH
impactDescription: A test with a step missing tests something other than it claims
tags: [testing, aaa, structure, xctest]
paths: ["AudiobookForgeTests/**/*.swift"]
---

## Every Test Arranges, Acts and Asserts

**Impact: HIGH**

Every test has three steps, in this order, each present and identifiable, and
the file marks them `// Arrange`, `// Act`, `// Assert`:

1. **Arrange** — build the input. A fixture from `AudioFixtures.swift`, a
   draft from `QueueTestCase.makeDraft`, a `SharedFixtures` URL all count.
2. **Act** — the one call under test. One act per test where the design
   allows; a test that acts twice is two tests, or a test of the pair.
3. **Assert** — `XCTAssert…` against what the act produced; `XCTUnwrap` for
   the thing the rest cannot run without.

The steps need not be on separate lines — a short test can be one line — but a
reader should be able to point at the input, the call, and the check.

**Incorrect (the act hidden inside the assert; no act at all):**

```swift
XCTAssertEqual(try await EncodeJob(spec: makeSpec(in: tmp, chapters: chapters, bitrate: .k64)).run().pathExtension, "m4b")

func test_fixtureHasThreeFiles() { XCTAssertEqual(plan.count, 3) }
```

**Correct:**

```swift
// Arrange
let job = EncodeJob(spec: makeSpec(in: tmp, chapters: chapters, bitrate: .k64))

// Act
let out = try await job.run()

// Assert
try await assertStitched(out, plan: plan)
```
