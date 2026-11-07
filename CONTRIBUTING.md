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

## Scripts

Everything in `scripts/`, run from the repo root:

| Script | What it does |
|---|---|
| `install.sh` | Builds Clipback and installs it in Applications. Use this for the copy you run every day. |
| `run.sh` | Builds a test copy in `build/` and runs it, quitting any running Clipback first. Run `install.sh` again when you're done. |
| `build.sh` | Builds the app without running it. The other scripts call it. `CONFIG=Release` makes an optimised build. |
| `snapshots.sh` | Saves a picture of every screen to `build/snapshots/`, so you can check UI changes. Your own clips and settings aren't changed. |
| `readme-images.sh` | Makes the screenshots in the README from made-up clips. Pass `dark` for dark mode. |
| `release.sh` | Makes a signed, notarized DMG in `dist/`. Needs a Developer ID certificate and Apple notary credentials; see the comments at the top. |
| `make-icon.swift` | Draws the app icon. Run it with `swift scripts/make-icon.swift`. |

## Code style

- Swift 6 language mode. UI and app state are `@MainActor`.
- AppKit owns windows and panels; SwiftUI fills them. Every window and panel sets `sharingType = .none` so it stays out of screen shares.
- The markdown files in the clips folder are the source of truth. Don't add anything that only lives in a database.
- Logic that doesn't need AppKit goes in `ClipbackCore`, with tests.
- Clipback makes no network requests. Please keep it that way.
