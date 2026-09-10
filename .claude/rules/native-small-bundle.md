---
title: Small, Because ffmpeg Is the Only Weight
impact: MEDIUM
impactDescription: The app is under 7 MB, more than half of it the bundled ffmpeg; growth elsewhere is a signal
tags: [native, macos, bundle, dependencies, size, ffmpeg]
paths: ["project.yml", "scripts/build-ffmpeg.sh", "AudiobookForge/**"]
---

## Small, Because ffmpeg Is the Only Weight

**Impact: MEDIUM**

`AudiobookForge.app` is about 6.8 MB, of which the bundled ffmpeg is 3.6 MB,
and it embeds no frameworks: `ForgeCore` is a static library linked into the
app, and the app target has no package dependencies (the CLI's ArgumentParser
and Yams never enter the bundle). ffmpeg itself is built with
`--disable-everything` and only the decoders, muxers, filters and protocols
the app uses enabled — no network protocols, no video, no ffprobe. That is a
consequence of using the system's features and a check on it: a feature that
arrives with a dependency, a second binary, or an ffmpeg component enabled
"just in case" is a sign the wrong path was taken. Check
`du -sh build/Build/Products/Debug/AudiobookForge.app` after
`scripts/build.sh`; growth needs a reason.

**Incorrect:**

```yaml
# project.yml, app target
dependencies:
  - package: SomeAudioToolkit     # for a waveform view AVFoundation can draw
```

```sh
--enable-decoder=h264            # nothing here has video
```

**Correct:**

```swift
import AVFoundation   // already on every Mac
```
