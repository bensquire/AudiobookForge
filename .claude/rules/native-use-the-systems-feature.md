---
title: Use the System's Feature, Not a Copy of It
impact: HIGH
impactDescription: The OS version already handles accessibility, Dark Mode, localisation and next year's macOS
tags: [native, macos, appkit, swiftui, sf-symbols, notifications]
paths: ["AudiobookForge/**/*.swift"]
---

## Use the System's Feature, Not a Copy of It

**Impact: HIGH**

AudiobookForge should feel like a Mac app Apple could have shipped: it behaves
the way the user's other apps behave, by using what macOS provides rather than
building a version of its own. Before writing a control, a panel, a picker or
an alert, ask whether the OS has one. It usually does.

- **Choosing files** is `fileImporter` / `NSOpenPanel`, plus drag and drop
  onto the window; folders are walked, not asked about.
- **Icons** are SF Symbols, chosen for their meaning, at the system's sizes
  and weights. No bitmaps for things a symbol says.
- **Finishing** is a `UserNotifications` banner (with the foreground
  presenter so it shows while the app is frontmost), not a custom toast.
- **Confirming a destructive step** is `confirmationDialog` / `alert`.
- **Persisting a picked folder** across launches is a security-scoped
  bookmark, not a plain path the sandbox will refuse.
- **Text, colour and spacing** are `Font` styles, semantic colours and
  standard control sizes. Nothing hard-coded that the system defines.

Native is not generic: the chapter table, the queue rows and the metadata
search are the app's own work — built from the system's parts.

**Incorrect (a toast of our own):**

```swift
struct DoneBanner: View { … withAnimation { show = true } … }
```

**Correct (the system's):**

```swift
UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: …, content: content, trigger: nil))
```
