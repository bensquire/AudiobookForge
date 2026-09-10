# AudiobookForge

AudiobookForge turns a folder of audio files into one chaptered `.m4b`: probe
the files, look up the book's metadata, and encode in a background queue with
the bundled ffmpeg. Three promises follow from that, and every change is held
to them:

- **Lossless when it can be.** AAC sources at "Match source" are remuxed with
  `-c:a copy`; samples are re-encoded only when a bitrate or a gain mode
  demands it.
- **The user's files are never clobbered.** Sources are read only; output is
  written as `.partial` and renamed once; a collision gets ` (2)`; a book that
  already has chapters is refused on import rather than flattened.
- **Metadata is what the user chose.** From the files, or from the search
  result they clicked. Nothing invented, nothing applied to a draft they had
  already cleared.

## Layout

| Target | What it is |
|---|---|
| `ForgeCore/` | The headless framework: probe, import rules, chapter file, encode, queue, metadata lookup, settings. No AppKit or SwiftUI, so all of it is testable and shared with the CLI. |
| `AudiobookForge/` | The SwiftUI app: views, the app delegate that owns the queue's lifecycle, the notification banner. |
| `ForgeCLI/` | `forge`, a batch pipeline over the same core (`scan` today; plan/run later). Config in `~/.forge/forge.yml`. |
| `AudiobookForgeTests/` | XCTest. Unit tests on the pure logic; integration tests that run the real bundled ffmpeg on generated tones and committed MP3s and judge the decoded audio. |
| `scripts/` | Bootstrap, the ffmpeg build, build/test/lint/format, release and notarisation. |
| `project.yml` | The XcodeGen spec; the `.xcodeproj` is generated and gitignored. |

## Commands

```
scripts/bootstrap.sh     # deps + build the bundled ffmpeg (once, ~5 min)
scripts/build.sh debug   # AudiobookForge.app into build/Build/Products/Debug, ad-hoc signed and sandboxed
scripts/test.sh          # builds the forge CLI, then the whole suite (~210 tests, ~4 s)
scripts/lint.sh          # pinned SwiftFormat + SwiftLint over every target; CI runs exactly this
scripts/format.sh        # the same tools, writing
FORGE_FFMPEG_DIR=AudiobookForge/Resources/bin build/Build/Products/Debug/forge scan -c <config>
```

`forge` needs `FORGE_FFMPEG_DIR` outside the app bundle and refuses to scan
without it (or `--no-probe`). Never point it at the default `~/.forge` when
testing: that directory is the user's real state, and `scan` overwrites its
manifest. Use a scratch config with its own `stateDir:`.

## Where the rest lives

- `.claude/rules/` — one rule per file, grouped by section: product, workflow,
  quality, testing, native, communication. `README.md` there is the index and
  `_template.md` the shape of a new one. A rule with `paths` loads itself when
  a matching file is in play.
- `.claude/hooks/` — format, lint and measure every Swift file as it is
  edited, with the pinned tools from `scripts/install-lint-tools.sh`.
- `.claude/skills/run-app/` — how to build, launch and drive the app by
  accessibility identifier for an end-to-end check.
- `.claude/skills/apple-docs/` — how to ask `scrapple`, the offline index of
  Apple's documentation, before using a system API or building what the
  system already has.
- `.githooks/pre-commit` — lint and the suite before every commit; enable with
  `git config core.hooksPath .githooks`.
- Four settings persist between launches, in `UserDefaults` under
  `~/Library/Containers/com.bensquire.AudiobookForge`: bitrate, gain, filename
  template, and the output folder as a security-scoped bookmark. The prep area
  and the queue do not persist. Check them after a relaunch.
- `TODO.md` at the root is the user's local tracker and stays out of commits
  unless they say otherwise; the README's "Improvement Ideas" is the shared
  list.
