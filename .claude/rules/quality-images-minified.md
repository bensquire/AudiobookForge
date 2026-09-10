---
title: Every Image Is as Small as It Can Be Without Showing It
impact: MEDIUM
impactDescription: A README screenshot stored as an unoptimised PNG is a slow page for nothing
tags: [quality, images, assets, size, webp, png]
paths: ["images/**", "README.md", "AudiobookForge/Assets.xcassets/**"]
---

## Every Image Is as Small as It Can Be Without Showing It

**Impact: MEDIUM**

An image that is *presentation* — the README screenshot, the app icon —
is minified to the highest degree that introduces no visible artefact. In order:

1. **The right container.** A photograph is WebP (or JPEG); flat graphics,
   screenshots with text and icons are PNG.
2. **Lossless first.** `oxipng -o max --strip safe` for PNG; `jpegtran
   -optimize -progressive` for JPEG. Identical pixels, smaller file.
3. **Then lossy, to the edge.** `cwebp -q 90 -m 6` or JPEG quality 85–90.
   Lower until an artefact shows, then back up one step.
4. **Look.** Side by side with the original at 1:1, on the busiest region.

Report the before and after sizes in the commit.

This rule does not touch *test input*: `AudiobookForgeTests/Fixtures/` is left
exactly as it is. Those files carry tags the probe reads and samples the tests
measure; re-encoding them is not optimisation, it is changing the test.

**Incorrect:**

```
images/screenshot.png   95 KB   (never run through oxipng)
```

**Correct:**

```
images/screenshot.png   71 KB   oxipng -o max --strip safe (was 95 KB); identical pixels
```
