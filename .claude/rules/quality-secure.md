---
title: Sandboxed, Two Hosts, One Child, Nothing Overwritten
impact: HIGH
impactDescription: An audiobook tool that reads the wrong file, phones anywhere else, or clobbers a library has broken trust
tags: [quality, security, privacy, sandbox, network, process]
paths: ["ForgeCore/**/*.swift", "AudiobookForge/**/*.swift", "ForgeCLI/**/*.swift", "project.yml", "scripts/**"]
---

## Sandboxed, Two Hosts, One Child, Nothing Overwritten

**Impact: HIGH**

- **Sandboxed, with four entitlements and no more.** App Sandbox,
  user-selected read-write, app-scope bookmarks (so the output folder survives
  relaunch), and network client. No entitlement is added without the feature
  that needs it. `SecurityScope` holds the grants for picked URLs and balances
  every one, as the platform requires: released when nothing in the draft or
  the queue refers to them, and at termination. A cover read once uses a
  start/stop pair rather than going through it at all.
- **Network is two HTTPS hosts.** Audnexus and the iTunes Search API, for
  metadata the user asked to look up. `MetadataSearch.fetch` refuses any other
  scheme, checks for 2xx, times out in 15 s and caps a cover at 20 MB. Nothing
  is sent but the query. No telemetry.
- **One child process, ours.** The bundled ffmpeg, resolved by `Bundled` from
  the app bundle; in a release build never from `PATH`. Arguments are an array,
  never a shell string, and every path is absolute. Nothing else is spawned.
- **Input is untrusted.** Provider records are decoded into typed DTOs; an
  ASIN is validated before it is spliced into a URL path; a cover is checked
  by ImageIO before ffmpeg sees it; a config value that is not an accepted
  spelling fails at load.
- **Output is written safely.** `.partial` beside the destination, one rename
  on success; see `product-never-clobber-the-users-files`.
- **Signed, hardened and notarised.** `release.yml` signs with Developer ID
  and the hardened runtime, including the embedded ffmpeg, and notarises the
  app and the DMG.

**Incorrect:**

```swift
let url = URL(string: "https://api.audnex.us/books/\(result.id)")!   // id straight from the network
let (data, _) = try await URLSession.shared.data(from: url)        // any status, 60 s
```

**Correct:**

```swift
guard result.source == .audnexus, isASIN(result.id) else { return result }
let data = try await fetch(url)   // https only, 2xx only, 15 s
```
