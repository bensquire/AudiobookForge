---
name: run-app
description: Build, launch, and drive the AudiobookForge macOS app UI programmatically (AppleScript + AXIdentifiers) to verify changes end-to-end
---

# Run and drive AudiobookForge

## Build & launch

```bash
scripts/build.sh                 # xcodegen + Debug build, ~1 min warm
open build/Build/Products/Debug/AudiobookForge.app
```

Prereqs (already granted on Ben's machine, both to the terminal app e.g. Ghostty):
**Accessibility** (System Events UI scripting) and **Screen Recording** (`screencapture -x`).
The screen must be **unlocked** — a locked screen makes `osascript` hang or return
`missing value`, windows report count 0, and screenshots come back black. Check a
screenshot isn't black before trusting any "window not found" conclusion.

## Driving: use AXIdentifiers, not positions

Every interactive control carries a `.accessibilityIdentifier`. Full map:

- `chapters.addFiles / .chooseFiles / .clear / .table / .rowTitle`
- `encode.bitrate / .gain / .chooseOutput / .addToQueue`
- `metadata.search / .provider / .runSearch / .clearSearch / .searchResult /
  .chooseCover / .clearCover / .title / .subtitle / .author / .narrator /
  .series / .seriesPosition / .year / .genre / .description`
- `queue.clearDone / .item / .item.status` (status is a static text whose value is
  Waiting/Running/Done/Failed — read it to poll state) `/ .item.reveal / .item.duplicate
  / .item.edit / .item.retry / .item.remove / .item.cancel`

Gotchas learned the hard way:

- `entire contents of window 1` is **flaky** (sometimes returns nothing, and takes
  ~60s with a full 57-row table). Use a recursive `UI elements` walk instead.
- The metadata pane's subtree isn't exposed until the window has actually been
  **raised/rendered** — `activate` + `perform action "AXRaise" of window 1` first.
- `whose value of attribute "AXIdentifier" is ...` cannot filter `entire contents`
  directly; hence the handler below.
- NSOpenPanels and confirmationDialogs are system surfaces — no identifiers there.
  Drive panels with ⇧⌘G (Go to Folder) + typed path + two returns; dialogs by
  button name ("Discard", "Replace", "Cancel").
- ⌘↩ triggers Add to Queue (its keyboard shortcut) without any lookup.

Template:

```applescript
on findIn(e, ident)
  tell application "System Events"
    try
      if (value of attribute "AXIdentifier" of e) is ident then return e
    end try
    try
      repeat with k in (UI elements of e)
        set hit to my findIn(k, ident)
        if hit is not missing value then return hit
      end repeat
    end try
  end tell
  return missing value
end findIn

on gotoInPanel(pathText) -- inside an open NSOpenPanel
  tell application "System Events" to tell process "AudiobookForge"
    keystroke "g" using {command down, shift down}
    delay 1
    keystroke pathText
    delay 0.5
    keystroke return
    delay 2
    keystroke return
  end tell
end gotoInPanel

tell application "AudiobookForge" to activate
delay 0.5
tell application "System Events" to tell process "AudiobookForge"
  perform action "AXRaise" of window 1
  set w to window 1
end tell
tell application "System Events" to click (my findIn(w, "chapters.chooseFiles"))
delay 1.5
my gotoInPanel("/path/to/mp3/folder")
-- import + probe of ~57 files takes a few seconds; then:
tell application "System Events" to keystroke return using {command down} -- Add to Queue
```

## Verify results

Screenshots: `screencapture -x out.png` then Read the file (look at it — black = locked).
Encodes are fast (57-file / 15h book ≈ 1 min; parallel per-file AAC then concat).
Output lands at `<outputDir>/{author}/{title}/{title}.m4b` (default template).
Inspect with the bundled ffmpeg:

```bash
FF=build/Build/Products/Debug/AudiobookForge.app/Contents/Resources/bin/ffmpeg
"$FF" -i "book.m4b" 2>&1 | grep -E "Duration|Stream|title|artist|Chapter #"
```

Expect: correct total duration, one aac stream at the chosen bitrate, a
`Chapter #0:N` per source file with per-file titles, and ©nam/©ART tags.

## Notes

- Settings persist across relaunches via `SettingsStore` (bitrate/gain/template in
  UserDefaults; output dir as security-scoped bookmark + plain-path fallback). A
  deleted output dir is dropped on load, so ⌘↩ can still no-op on a fresh machine.
- Debug builds are **ad-hoc signed and sandboxed** (scripts/build.sh) — required
  because UserNotifications refuses unsigned bundles (UNErrorDomain Code=1). First
  launch after a container wipe shows the notification permission prompt; the
  queue-drained banner shows even with the app frontmost (ForegroundPresenter
  delegate) and auto-dismisses after ~5s like any banner. QueueNotifier NSLogs
  auth/delivery failures — capture stderr by launching the binary directly
  (`.app/Contents/MacOS/AudiobookForge > log 2>&1 &`); the unified log drops them.
- Sandboxed app ⇒ UserDefaults + containers live under
  `~/Library/Containers/com.bensquire.AudiobookForge/`.
