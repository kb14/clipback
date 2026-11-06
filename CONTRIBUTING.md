# Contributing

Bug reports and pull requests are welcome. For anything bigger than a fix, open an issue first so we can agree on the approach before you spend time on it.

## Building

You need macOS 15 or later and Xcode 16 or later.

```bash
swift test              # core tests: clip format, parsing, search, review schedule
./scripts/run.sh        # Debug build in build/Clipback.app, then runs it
./scripts/install.sh    # Release build, installed as /Applications/Clipback.app
```

`scripts/build.sh` signs with your "Developer ID Application" certificate if you have one, or else your first "Apple Development" certificate, so macOS keeps Accessibility and Screen Recording allowed across rebuilds. Set `CLIPBACK_SIGN_ID` to pick another. Without a certificate it signs ad hoc, and you'll have to allow them again after each build.

## Checking UI changes

```bash
./scripts/snapshots.sh
```

This renders every screen of the review window, plus the capture panel, to `build/snapshots/`. It does that in dark and light, and with a set of made-up clips covering each kind of source. Look at the PNGs before opening a pull request that changes the UI.

Developer runs like this one never change your own settings or clips. They save into a scratch copy of the settings, and the made-up clips live in a temporary folder.

## Code style

- Swift 6 language mode. UI and app state are `@MainActor`.
- AppKit owns windows and panels; SwiftUI fills them. Every window and panel sets `sharingType = .none` so it stays out of screen shares.
- The markdown files in the clips folder are the source of truth. Don't add anything that only lives in a database.
- Logic that doesn't need AppKit goes in `ClipbackCore`, with tests.
- Clipback makes no network requests. Please keep it that way.
