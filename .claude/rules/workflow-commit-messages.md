---
title: Commit Messages Are Prose With the Measurements
impact: HIGH
impactDescription: The history is where the reasoning is kept
tags: [workflow, git, commits, history]
---

## Commit Messages Are Prose With the Measurements

**Impact: HIGH**

When told to commit, the message says what changed and why, in prose, with the
measurements that justified it — the file or fixture, the figure before, the
figure after — and what was tried and taken out, if anything was. One commit
per change of meaning: work that was already in the tree and is not part of the
change goes in its own commit, described honestly. End with the attribution
lines the session prescribes.

**Incorrect:**

```
Fix progress bar and cleanup
```

**Correct:**

```
Report progress from ffmpeg's carriage-return stats lines

ffmpeg ends every in-flight stats report with \r and only the last with \n;
the line buffer split on \n alone, so the encode bar sat at 0 % for whole
books and jumped to Done. Split on both. A 240 s encode now delivers 38
progress callbacks instead of 2. Suite 4.0 s (was 3.9 s).
```
