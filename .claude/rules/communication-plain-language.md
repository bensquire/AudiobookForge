---
title: Messages to the User Are Plain Language
impact: MEDIUM
impactDescription: The reader gets what they need, can find it, understand it and use it — ISO 24495-1:2023
tags: [communication, plain-language, iso-24495]
---

## Messages to the User Are Plain Language

**Impact: MEDIUM**

Messages follow ISO 24495-1:2023's four principles: the reader gets what they
need, can find it, can understand it, and can use it.

- **Lead with what matters.** The outcome or the answer first; the reasoning
  after. If something failed, say so in the first line.
- **Make it findable.** Headings and short lists when a message has more than
  one part. One idea per paragraph.
- **Make it understandable.** Short sentences. Everyday words where they will
  do; a term of art only where it is the precise one, defined the first time.
  Active voice: say who did what.
- **Make it usable.** Numbers carry their unit and what they are compared with.
  End with what the reader can do next, or that nothing is needed. Never bury a
  caveat.
- **Say what was done, not what was intended.** A test that was not run was not
  run. A check skipped is named as skipped. A file that was overwritten by
  accident is reported in the first line.

**Incorrect:**

```
I've made some improvements to the progress reporting which should help with
the bar not moving; there may be some edge cases but overall it's better.
```

**Correct:**

```
The progress bar moves during encodes now: 38 callbacks on a 240 s chapter
(was 2, both at exit). The remaining gap is the measurement phase, which
reports per chapter and so steps rather than glides; it is in the TODO.
Nothing is committed.
```

Reference: ISO 24495-1:2023, Plain language — Part 1: Governing principles and guidelines.
