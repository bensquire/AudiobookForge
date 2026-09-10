---
title: Add a Case and Its Behaviour, Not an `if`
impact: HIGH
impactDescription: A special case on shared infrastructure is a band-aid the next change tears off
tags: [quality, extensibility, altitude, design]
paths: ["ForgeCore/**/*.swift", "ForgeCLI/**/*.swift"]
---

## Add a Case and Its Behaviour, Not an `if`

**Impact: HIGH**

The places the tool grows are enumerations with a single mechanism behind
them: a `GainBoost` is a case with its label, config spelling and gain rule,
and every mode goes through `resolvePhase0GainFilter`; a `Bitrate` is a case
that decodes and validates itself; a `MetadataSearch.Provider` is a case with
its own request; an `AudioCodec` is a case with its remux-friendliness.
`CaseIterable` is what lets the picker, the CLI's accepted-spellings message
and the tests list every case without being told. Adding a mode means adding a
case and its behaviour — not an `if` in the encoder for the new one.

When a change wants a special case on shared code, the fix is usually one
level deeper: make the shared mechanism carry what the case needs (a gain
floor on the offset calculation, rather than a second measurement pass for
lift-only).

**Incorrect (the encoder learns about one case):**

```swift
if spec.settings.gainBoost == .autoIfQuiet && bookI >= target { skipFilter = true }
```

**Correct (the case carries what it needs through the one mechanism):**

```swift
let offset = Self.gainOffsetDB(from: bookI, liftOnly: spec.settings.gainBoost == .autoIfQuiet)
guard offset != 0 else { return nil }
```
