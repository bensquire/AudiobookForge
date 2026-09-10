---
title: Every Run Gives the Same Answer
impact: HIGH
impactDescription: A flaky test is a test nobody trusts
tags: [testing, determinism, fixtures, network]
paths: ["AudiobookForgeTests/**/*.swift"]
---

## Every Run Gives the Same Answer

**Impact: HIGH**

Fixtures are generated (`writeSineWav`, `makeAacFixture`) or committed
(`Fixtures/mp3`), never fetched. No network: `MetadataSearch`'s transport is
tested through its guards and DTOs, not against Audnexus. No wall-clock
dependence and no sleeping for luck: a test that waits for the queue polls a
condition with `waitUntil` and fails on timeout. No dependence on another
test having run first or on the order tests run in; each test gets its own
temp directory from `FFmpegTestCase` / `QueueTestCase`. A test that needs the
bundled ffmpeg checks `Bundled.binary("ffmpeg")` and skips cleanly when it is
not built, so CI without it stays green rather than red.

**Incorrect:**

```swift
try await Task.sleep(for: .seconds(1))          // hope the worker got there
let found = try await MetadataSearch.search(query: "Dune")   // the network
```

**Correct:**

```swift
try await waitUntil { item.status.isRunning }
let books = try JSONDecoder().decode([AudnexusBook].self, from: capturedJSON)
```
