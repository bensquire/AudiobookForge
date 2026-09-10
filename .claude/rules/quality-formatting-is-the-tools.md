---
title: Formatting Is Decided by the Tools
impact: MEDIUM
impactDescription: No formatting diffs, no style arguments in review, no drift between machines
tags: [quality, formatting, swiftformat, swiftlint, hooks]
paths: ["ForgeCore/**/*.swift", "AudiobookForge/**/*.swift", "ForgeCLI/**/*.swift", "AudiobookForgeTests/**/*.swift"]
---

## Formatting Is Decided by the Tools

**Impact: MEDIUM**

SwiftFormat and `.swiftformat` are the style; SwiftLint and `.swiftlint.yml`
say which rules matter here and why the rest are off. Both run at pinned
versions (`scripts/install-lint-tools.sh`, into `build/tools/bin`) so a local
run and CI agree; the hooks in `.claude/hooks` apply them to every edited
Swift file and measure line length against `.swiftformat`'s `--maxwidth`.
`scripts/lint.sh` is the whole tree. Do not argue with either in code, and do
not hand-format around them.

Two things the formatter will do to you: it hoists `await` out of an
`XCTAssert`/`XCTUnwrap` autoclosure, which does not compile, so bind the
awaited value first; and a comment beginning `MARK` (as in
`// MARKETING_VERSION`) becomes a `MARK:` section. Write around both.

When a hook reports a finding, fix it before handing over; the lint hooks are
advisory so that a formatting hiccup never blocks an edit.

**Incorrect:**

```swift
// swiftlint:disable identifier_name   ← already off in the config
XCTAssertEqual(try await integratedLoudness(of: out), source)   // hoisted, then broken
```

**Correct:**

```swift
let measured = try await integratedLoudness(of: out)
XCTAssertEqual(measured, source, accuracy: 0.5)
```
