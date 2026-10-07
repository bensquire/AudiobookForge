---
title: A Change Is Checked, Not Believed
impact: CRITICAL
impactDescription: Two CLI compile errors once got past a green test run because the suite never built the CLI
tags: [workflow, verification, tests, lint, build]
paths: ["ForgeCore/**", "AudiobookForge/**", "ForgeCLI/**", "AudiobookForgeTests/**", "scripts/**"]
---

## A Change Is Checked, Not Believed

**Impact: CRITICAL**

Before saying a change is done:

1. **`scripts/lint.sh`** — SwiftFormat at the pinned version, no line over 130
   columns, and no `try!`, force unwrap or implicitly unwrapped optional, over
   every target. The edit hooks run per file; this is the
   whole tree.
2. **`scripts/test.sh`**, the whole suite. It builds the `forge` CLI first
   (the test bundle links ForgeCore directly and would never compile the CLI
   otherwise), then runs ~230 tests in a few seconds. The audio tests need the
   bundled ffmpeg (`scripts/build-ffmpeg.sh`); they skip, not fail, without it.
3. **The real thing**, for anything touching encoding, probing or the queue:
   encode a real book in the relaunched app, or run `forge scan` against a
   scratch config (never the default `~/.forge`, which is the user's state).
   Inspect the output with the bundled ffmpeg — duration, one AAC stream at the
   chosen bitrate, a chapter per source file, the book tags — and, for a gain
   change, its integrated loudness with `-af ebur128`.

Report what was run and what it showed. A check that was skipped is named as
skipped, not left out.

**Incorrect (one class, no lint, no real file):**

```
Ran EncodeJobHelpersTests; passes. Done.
```

**Correct:**

```
lint clean; 211 tests in 4.1 s; encoded the 57-file Dune folder in the app:
15 h 02 m, 57 chapters, aac 64 kb/s, -16.2 LUFS with auto-normalize (was -21.4).
```
