---
title: The Shortcuts and Menus Every Mac User Knows
impact: HIGH
impactDescription: An invented shortcut is one the user has to learn; a missing menu item is one they cannot find
tags: [native, macos, keyboard, shortcuts, menus]
paths: ["AudiobookForge/**/*.swift"]
---

## The Shortcuts and Menus Every Mac User Knows

**Impact: HIGH**

Every action the user can take from a button can be taken from the menu bar,
and the common ones carry the platform's shortcut:

| Action | Shortcut |
|---|---|
| Add files or a folder | ⌘O |
| Add to Queue | ⌘↩ |
| Clear the current book | ⌘⌫, after the confirmation |
| Remove selected chapters | ⌫ |
| Confirm, cancel | Return, Escape |
| Close, minimise, hide, quit | ⌘W, ⌘M, ⌘H, ⌘Q — never overridden; ⌘Q waits for the queue |

A new action takes the shortcut the platform's guidelines give it, or none. A
shortcut is never invented where Apple has assigned one, and never reused for
a second meaning. Menus are the standard set in the standard order — App,
File, Edit, View, Window, Help — with the app's items placed in the group they
belong to; File › New is removed because there is nothing to create. This
table states the convention; not every row exists in the app yet.

**Incorrect (a new top-level menu for two items; a shortcut with a meaning of its own):**

```swift
CommandMenu("Forge") { Button("Encode") { … }.keyboardShortcut("e") }
```

**Correct:**

```swift
CommandGroup(replacing: .newItem) {}
Button("Add to Queue") { … }.keyboardShortcut(.return, modifiers: [.command])
```

Reference: Apple Human Interface Guidelines, Keyboard and Menus.
