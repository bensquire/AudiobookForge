---
title: Challenge a Rule When It Is in the Way
impact: CRITICAL
impactDescription: The rules serve the best system; a rule that blocks a better one is a defect to raise, not a wall to work around
tags: [workflow, rules, architecture, standards, judgement]
---

## Challenge a Rule When It Is in the Way

**Impact: CRITICAL**

These rules exist to make the best system, not to be obeyed for their own
sake. When following one would make the code, the architecture, a standard
or the product worse — or when a better way exists that a rule forbids —
raise it with the user, plainly: which rule, what it costs here, what the
alternative is, and what it would take. Then wait. Sometimes the answer is to
rearchitect, change a standard, or rewrite the rule.

Do not silently comply, and do not silently break it: both hide the decision.
A rule the user has just confirmed stands.

**Incorrect (working around it, or working under it in silence):**

```
The rule says remux when the sources are AAC, so I've made the gain filter a
no-op on AAC books rather than re-encode them.
```

**Correct (the case made, the decision left with the user):**

```
"Lossless when it can be" and the new auto-if-quiet mode collide on an AAC
book that measures loud: the measurement pass says no gain is needed, but
canRemux was decided before measuring, so the book is re-encoded for nothing.
Fixing it means measuring before the remux decision, which adds an ffmpeg pass
to every AAC book. Want that, or keep remux-first as written?
```
