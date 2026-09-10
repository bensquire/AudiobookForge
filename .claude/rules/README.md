---
title: AudiobookForge Rules Index
impact: LOW
impactDescription: About the rules themselves; loads only when a rule is being written
tags: [meta, rules]
paths: [".claude/rules/*.md"]
---

# AudiobookForge Rules

Modular, machine-readable rules for working on AudiobookForge. Each file is one
rule, named `{section}-{rule-name}.md`, with YAML frontmatter Claude Code reads:
a rule with `paths` loads only when a matching file is in play; one without
applies always. `_sections.md` defines the sections and their order;
`_template.md` is the shape of a new rule. Brought over from the Prospect repo
and reworded for this codebase; the panorama-specific rules stayed behind.

## Rules Index

### Product

- [product-lossless-when-it-can-be](product-lossless-when-it-can-be.md) - Remux AAC sources; re-encode only when samples must change
- [product-never-clobber-the-users-files](product-never-clobber-the-users-files.md) - Sources read only; `.partial` then rename; collisions get ` (2)`; a chaptered book is refused
- [product-metadata-is-what-the-user-chose](product-metadata-is-what-the-user-chose.md) - Tags come from the files or the pick; nothing applied that was not picked

### Workflow

- [workflow-challenge-the-rules](workflow-challenge-the-rules.md) - A rule in the way is raised with the user, not obeyed or broken in silence
- [workflow-no-commits-unless-told](workflow-no-commits-unless-told.md) - Never commit or push unless told to
- [workflow-hand-over-for-trial](workflow-hand-over-for-trial.md) - Build, relaunch, say what to look at, stop
- [workflow-checking-work](workflow-checking-work.md) - Lint, the whole suite, then the app or the CLI on real files
- [workflow-commit-messages](workflow-commit-messages.md) - Prose, with the measurements
- [workflow-diagnostics](workflow-diagnostics.md) - Env-gated to keep, separate file to throw away
- [workflow-todo-entries](workflow-todo-entries.md) - One line per feature, under its status section

### Quality

- [quality-separation-of-concerns](quality-separation-of-concerns.md) - ForgeCore knows no window; dependencies run one way
- [quality-dependency-injection](quality-dependency-injection.md) - Settings and collaborators handed in as values
- [quality-readability](quality-readability.md) - Code reads like the prose around it
- [quality-consistency](quality-consistency.md) - Match the code around you; reuse the helper that exists
- [quality-extensible](quality-extensible.md) - Add a case and its behaviour, not an `if`
- [quality-performant](quality-performant.md) - Fast where it counts, and measured
- [quality-secure](quality-secure.md) - Sandboxed; two HTTPS hosts; one child process; nothing overwritten
- [quality-comments-carry-measurements](quality-comments-carry-measurements.md) - Short, says why, carries the number; never restates a name
- [quality-formatting-is-the-tools](quality-formatting-is-the-tools.md) - SwiftFormat and SwiftLint decide, at pinned versions
- [quality-images-minified](quality-images-minified.md) - The right container, lossless first, then lossy to the edge, judged at 1:1

### Testing

- [testing-arrange-act-assert](testing-arrange-act-assert.md) - Each step present, in order
- [testing-one-behaviour-per-test](testing-one-behaviour-per-test.md) - One behaviour, named as a sentence
- [testing-ground-truth-with-teeth](testing-ground-truth-with-teeth.md) - Judge the decoded audio; say what the alternative measures
- [testing-deterministic](testing-deterministic.md) - Generated fixtures, no clock, no network, no order
- [testing-fast](testing-fast.md) - Fast by paying only for what the test needs, never by seeing less
- [testing-failure-reads-as-a-sentence](testing-failure-reads-as-a-sentence.md) - Messages on every assertion

### Native

- [native-use-the-systems-feature](native-use-the-systems-feature.md) - Panels, SF Symbols, notifications, drag and drop
- [native-keyboard-and-menus](native-keyboard-and-menus.md) - The shortcuts every Mac user knows
- [native-small-bundle](native-small-bundle.md) - ffmpeg is the bundle; nothing else grows it
- [native-check-apples-documentation](native-check-apples-documentation.md) - Look it up in `scrapple` before using, copying or asserting

### Communication

- [communication-plain-language](communication-plain-language.md) - ISO 24495-1: relevant, findable, understandable, usable
