---
title: A TODO Entry Is One Line
impact: MEDIUM
impactDescription: The TODO is a list to scan, not a place to keep reasoning
tags: [workflow, todo, planning]
paths: ["TODO.md", "README.md"]
---

## A TODO Entry Is One Line

**Impact: MEDIUM**

The list of what is left is the README's "Improvement Ideas": a checklist,
one entry per feature, `- [ ] Name — description`. The description is short:
what it is, or what the next attempt should do, in a clause. The list stays in
order of what would change most about what someone can do with the app, and a
feature is never listed twice.

The reasoning — what was measured, what went wrong, why it was taken out —
lives in the commit that did it and the code that carries it, not here. A
figure that sets the bar may appear (`suite 23 s → 4 s`); a paragraph may not.
A `TODO.md` at the root is the user's local tracker and stays out of commits
unless they say otherwise.

**Incorrect:**

```
## Persistable projects

The queue is lost on quit because QueueManager holds items in memory … (four
paragraphs on Codable, document types and the sandbox)
```

**Correct:**

```
## Improvement Ideas

- [ ] Persistable projects (`.audiobookforge` document type) — queue survives quit; judge on a 20-item queue across a relaunch
```
