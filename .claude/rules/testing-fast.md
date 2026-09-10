---
title: Fast, but Not Over Accuracy
impact: MEDIUM
impactDescription: A test that is quick because it cannot see the defect is not a test; a slow suite is one nobody runs
tags: [testing, performance, accuracy, fixtures]
paths: ["AudiobookForgeTests/**/*.swift"]
---

## Fast, but Not Over Accuracy

**Impact: MEDIUM**

A test is first for what it proves, then as cheap as that allows — never the
other way round. The suite runs in about four seconds. Speed is bought by not
paying for what the test does not need: a fixture several tests read is built
once (`SharedFixtures.tenMinuteTone`); a rule about one unit is pinned on that
unit (`LineBuffer` on bytes, `PercentGate` on fractions) not on a whole
encode; a source WAV is written at 8 kHz where the encoder resamples anyway.

Speed is never bought by making the test see less. The cancel-mid-run tests
use ten minutes of audio because ffmpeg encodes ~500× realtime here and
nothing shorter leaves a window for the cancel to land in; the audio tests use
several seconds of tone because a loudness meter needs that to settle. A
fixture shrunk until the defect would not show, or a tolerance loosened so a
fast fixture clears it, is a faster test that no longer tests.

**Incorrect (fast because it cannot see):**

```swift
try writeSineWav(to: wav, seconds: 30, frequency: 440)   // encodes in 60 ms; cancel lands after exit
XCTAssertEqual(lufs, target, accuracy: 6)                // loosened until the short tone passes
```

**Correct (cheap where it costs nothing to be; exact where it counts):**

```swift
let wav = SharedFixtures.tenMinuteTone      // once per process, 8 kHz source
XCTAssertEqual(lufs, target, accuracy: 1.5)  // what a 4 s tone can hit; stated
```
