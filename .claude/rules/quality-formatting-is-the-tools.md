---
title: Formatting Is Decided by the Tools
impact: MEDIUM
impactDescription: No formatting diffs, no style arguments in review, no drift between machines
tags: [quality, formatting, swiftformat, hooks]
paths: ["ForgeCore/**/*.swift", "AudiobookForge/**/*.swift", "ForgeCLI/**/*.swift", "AudiobookForgeTests/**/*.swift"]
---

## Formatting Is Decided by the Tools

**Impact: MEDIUM**

SwiftFormat and `.swiftformat` are the style and the linter. It runs at a
pinned version (`scripts/install-lint-tools.sh`, into `build/tools/bin`) so a
local run and CI agree; the hooks in `.claude/hooks` apply it to every edited
Swift file and measure line length against `.swiftformat`'s `--maxwidth`.
`scripts/lint.sh` is the whole tree: SwiftFormat in lint mode, then no line
over 130 columns, since SwiftFormat leaves a long string or comment it cannot
wrap, then Xcode's `swift format` for the three rules SwiftFormat lacks — no
`try!`, no force unwrap, no implicitly unwrapped optional
(`scripts/safety-rules.swift-format`; XCTest files are exempt from the first
two). Route a nil into the error path the code already has; where a value
truly cannot be nil, `// swift-format-ignore: NeverForceUnwrap` on the line
above, with the reason. Do not argue with the tools in code, and do not
hand-format around them.

Two things the formatter will do to you: it hoists `await` out of an
`XCTAssert`/`XCTUnwrap` autoclosure, which does not compile, so bind the
awaited value first; and a comment beginning `MARK` (as in
`// MARKETING_VERSION`) becomes a `MARK:` section. Write around both.

When a hook reports a finding, fix it before handing over; the hooks are
advisory so that a formatting hiccup never blocks an edit.

**Incorrect:**

```swift
XCTAssertEqual(try await integratedLoudness(of: out), source)   // hoisted, then broken
```

**Correct:**

```swift
let measured = try await integratedLoudness(of: out)
XCTAssertEqual(measured, source, accuracy: 0.5)
```
