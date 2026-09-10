---
title: Metadata Is What the User Chose
impact: HIGH
impactDescription: A tag the user did not pick, or one from a book they had already cleared, is a wrong tag on a file they keep for years
tags: [product, metadata, search, tags, honesty]
paths: ["ForgeCore/**/*.swift", "AudiobookForge/Views/**/*.swift"]
---

## Metadata Is What the User Chose

**Impact: HIGH**

What ends up in the `.m4b` is either what the source files carried (title,
artist, album read by `AudioProbe`) or what the user picked: a search result
they clicked, a cover they chose, a field they typed. A search is a suggestion
until applied; nothing from it lands in the draft on its own. A result that
arrives after the draft was cleared or replaced belongs to a book that is no
longer there and is dropped (`resetToken`, cancelled search tasks). Fields the
user left blank stay blank in the file — no guessed year, no invented series.

**Incorrect (the first hit applied because it is probably right):**

```swift
let found = try await MetadataSearch.search(query: q)
project.metadata.title = found.first?.title ?? project.metadata.title
```

**Correct (shown, then applied only on the user's pick, only to the same draft):**

```swift
results = Array(found.prefix(8))
// … SearchResultRow(onApply: { apply(result) }) …
guard project.resetToken == tokenAtRequest else { return }
project.metadata.title = enriched.title
```
