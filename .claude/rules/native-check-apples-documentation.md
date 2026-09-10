---
title: Check Apple's Documentation Before Using Its API
impact: HIGH
impactDescription: A guessed signature compiles by luck; a copied feature is one the OS already had
tags: [native, documentation, scrapple, apple, hig, wwdc]
paths: ["AudiobookForge/**/*.swift", "ForgeCore/**/*.swift"]
---

## Check Apple's Documentation Before Using Its API

**Impact: HIGH**

Before using a system API you are not certain of, before building anything the
system might already provide, and before stating a platform convention as fact,
look it up. `scrapple` holds Apple's framework documentation, WWDC transcripts
and sample code offline — not the Human Interface Guidelines, whose
conventions are in the design talks; the `apple-docs` skill says how to ask it.
A symbol name is the best query. A decision that rests on what a page says
carries the page's path in a one-line comment, so the next reader can check it
too. A doc that contradicts a rule here is raised with the user, not followed
or ignored in silence. This matters most around AVFoundation (asset loading,
chapter metadata groups, `AVAssetReader`), UserNotifications, the sandbox and
security-scoped bookmarks, and SwiftUI's file importer and drop APIs.

**Incorrect (guessed, and a copy of what the OS has):**

```swift
.frame(width: 340)                       // the queue pane's width, chosen by eye
struct FolderPicker: View { … }          // a picker, when fileImporter exists
```

**Correct (looked up, and named):**

```sh
scrapple search "loadChapterMetadataGroups" --type doc --limit 3 --human
```

```swift
// /documentation/avfoundation/avasset/loadchaptermetadatagroups(withtitlelocale:containingitemswithcommonkeys:)
let groups = try await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [.commonKeyTitle])
```

Reference: `scrapple` (github.com/searlsco/scrapple); Apple Developer Documentation.
