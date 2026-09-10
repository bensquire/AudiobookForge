---
title: A TODO Entry Is One Line, Under Its Status
impact: MEDIUM
impactDescription: The TODO is a list to scan, not a place to keep reasoning
tags: [workflow, todo, planning]
paths: ["TODO.md", "README.md"]
---

## A TODO Entry Is One Line, Under Its Status

**Impact: MEDIUM**

The list of what is left has one section per status — To do; Tried, measured,
taken out; Might do; Done; Deliberately not doing — and every feature is one
line under its section: `NAME - Description`. The description is short: what
it is, or what the next attempt should do, in a sentence. Each section stays in
order of what would change most about what someone can do with the app. A
feature moves between sections; it is never listed twice.

The reasoning — what was measured, what went wrong, why it was taken out —
lives in the commit that did it and the code that carries it, not here. A
figure that sets the bar may appear (`suite 23 s → 4 s`); a paragraph may not.
Today the list is the README's "Improvement Ideas"; a `TODO.md` at the root
is the user's local tracker and stays out of commits unless they say otherwise.

**Incorrect:**

```
## Persistable projects

The queue is lost on quit because QueueManager holds items in memory … (four
paragraphs on Codable, document types and the sandbox)
```

**Correct:**

```
## To do

- Persistable projects - A `.audiobookforge` document so the queue survives quit; judge on a 20-item queue across a relaunch.
```
