---
name: build
description: Build, test, lint and package AudiobookForge — the XcodeGen app, its forge CLI and the bundled ffmpeg — and what the release scripts do. Use when building the app or the CLI, running the suite or one test class, linting or formatting, setting up a fresh checkout, or asked how a release is cut. Launching and driving the UI is the run-app skill.
---

# Building AudiobookForge

The Xcode project is generated. `project.yml` is the source and
`AudiobookForge.xcodeproj` is git-ignored, so every script runs
`xcodegen generate` first and a project change goes in `project.yml`; an edit made
in the generated project is lost on the next build. The targets are the app
(`AudiobookForge/`), the `forge` CLI (`ForgeCLI/`), the framework both link
(`ForgeCore/`) and the XCTest bundle (`AudiobookForgeTests/`). `CLAUDE.md` lists the
everyday commands; this is the fuller reference.

## Prerequisites

- Xcode 26.6, which CI and the release workflow pin. Deployment target macOS 14,
  Apple silicon only, since the bundled ffmpeg is arm64.
- `xcodegen` and `pkg-config` from Homebrew; `scripts/bootstrap.sh` installs them
  when they are missing.
- The bundled ffmpeg in `AudiobookForge/Resources/bin/` (git-ignored).
  `scripts/bootstrap.sh` builds it once from source — ffmpeg and fdk-aac at the
  versions pinned in `scripts/build-ffmpeg.sh`, working in `.build-ffmpeg/` — and
  skips the build while the binary reports the pinned version. Delete the binary to
  force a rebuild.
- SwiftFormat at a pinned version. `scripts/install-lint-tools.sh` downloads it
  into `build/tools/bin` the first time lint runs; Homebrew's copy is not used, because a minor version bump changes what `--strict` reports.
- The Swift packages (swift-argument-parser, Yams) resolve on the first build, which
  needs the network once.

## Commands

| Command | What it does |
|---|---|
| `scripts/build.sh` (or `debug`) | Debug app into `build/Build/Products/Debug/AudiobookForge.app`, ad-hoc signed and sandboxed, because UserNotifications refuses an unsigned bundle. 7 s with nothing to recompile. |
| `scripts/build.sh release` | Release app, unsigned, into `build/Build/Products/Release/` — CI's smoke build. |
| `scripts/test.sh` | Builds the `forge` CLI first (the test bundle links ForgeCore only, so a green suite alone says nothing about ForgeCLI compiling), then runs the whole suite: 230 tests in 4.1 s, 17 s for the script warm. |
| `scripts/test.sh -only OutputPathResolverTests` | One test class, as `-only-testing:AudiobookForgeTests/<Class>`. 8 s warm. For one method, run the script's `xcodebuild … test` line with `-only-testing:AudiobookForgeTests/<Class>/<method>`. |
| `scripts/lint.sh` | SwiftFormat in lint mode, a check that no line is over 130 columns, then Xcode's `swift format` for no `try!`, force unwrap or implicitly unwrapped optional (`scripts/safety-rules.swift-format`), over `AudiobookForge`, `AudiobookForgeTests`, `ForgeCore` and `ForgeCLI`. 0.45 s. |
| `scripts/format.sh` | SwiftFormat, writing; run lint again after. |
| `open build/Build/Products/Debug/AudiobookForge.app` | Launch the debug build. |
| `FORGE_FFMPEG_DIR=AudiobookForge/Resources/bin build/Build/Products/Debug/forge scan -c <config>` | The CLI. Give it a scratch config with its own `stateDir:`; `~/.forge` is the user's real state and `scan` overwrites its manifest. |
| `rm -rf build` | There is no clean script. This removes the derived data and the pinned lint tools, which the next lint downloads again. |

`xcpretty` is not installed here, so `scripts/test.sh` falls through to plain
`xcodebuild` output. Where it is installed, a failing run prints twice, because the
fallback runs the suite again.

## What CI checks

`.github/workflows/build.yml` runs on pushes to `main` and on pull requests (macOS 26,
Xcode 26.6): `scripts/lint.sh`, the bundled ffmpeg (cached on the hash of
`scripts/build-ffmpeg.sh`), `xcodegen generate`, `scripts/build.sh release`, a Release
build of ForgeCLI with `forge --version`, then the whole suite in Debug, and it uploads
the unsigned app. `scripts/lint.sh && scripts/test.sh` matches the lint and test steps;
add `scripts/build.sh release` to match the smoke build.

`.githooks/pre-commit` runs `scripts/lint.sh` and `scripts/test.sh`; it is on once
`git config core.hooksPath .githooks` has been set.

## Release

Run only when the user asks. Pushing a `v*` tag runs
`.github/workflows/release.yml`: an archive signed with Developer ID, notarization of
the app, a DMG made with `create-dmg`, the DMG signed and notarized, and a GitHub
Release with the ffmpeg and fdk-aac attribution. `scripts/release.sh <version>` does
the same locally into `dist/` without publishing; it needs the Developer ID
certificate in the login keychain, `APPLE_TEAM_ID`, `APPLE_API_KEY_ID`,
`APPLE_API_ISSUER_ID` and `APPLE_API_KEY_PATH`, and `create-dmg`. `RELEASING.md` has
the one-time setup and what goes wrong. `scripts/build.sh archive` makes an
`.xcarchive` alone, which also needs signing.
