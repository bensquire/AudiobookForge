---
title: Hand Work Over for the User to Try
impact: CRITICAL
impactDescription: The user judges a feature in the app, not in a report
tags: [workflow, handover, build, app, cli]
---

## Hand Work Over for the User to Try

**Impact: CRITICAL**

When a change the user can see in the app is done and checked, put it in front
of them there. A change to the CLI, the tests, the rules or the docs is handed
over as what it is: the command to run, the suite's result, the file to read.

1. `scripts/build.sh debug`, so `AudiobookForge.app` carries the change
   (ad-hoc signed and sandboxed, like a release).
2. Relaunch it: `pkill -x AudiobookForge; open build/Build/Products/Debug/AudiobookForge.app`.
   The prep area starts empty; four settings persist in `UserDefaults`
   (bitrate, gain, filename template, output folder as a security-scoped
   bookmark) under `~/Library/Containers/com.bensquire.AudiobookForge`, so say
   which the trial assumes. The `run-app` skill drives the UI by accessibility
   identifier when the trial needs a script.
3. Say what to look at and what the figures were.
4. Stop.

**Incorrect (declaring done from the command line):**

```
The suite passes and forge scan reports 12 books. Done.
```

**Correct (the app relaunched, the eye pointed):**

```
Rebuilt and relaunched. Drop the Dune folder: the queue row's bar should now
move through the encode instead of sitting at 0 % and jumping to Done. Output
lands at ~/Desktop/AudiobookForge Output/Frank Herbert/Dune/Dune.m4b.
```
