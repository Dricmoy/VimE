# Contributing to VimE

Thanks for helping. VimE is a small project run by one person, so a few notes save us both time.

## Reporting

- **An app where hints are missing or wrong:** use the "App doesn't work well" issue form. Most VimE bugs
  are app-specific, so the app and its version matter most.
- **Anything else:** the bug report form. Include your VimE and macOS versions.
- **Security issues:** please don't open a public issue. Use GitHub's private vulnerability reporting
  (Security tab → Report a vulnerability).

## Building

Requires macOS 14+, Xcode and XcodeGen (`brew install xcodegen`).

```sh
make signing   # once: a local signing identity, so macOS keeps the Accessibility permission across builds
make test      # unit tests for VimECore
make run       # build and launch the Debug build (its own bundle ID, so it needs its own Accessibility grant)
```

The README's Debugging section has tools for listing the hints VimE would show in an app without pressing
anything.

## Changes

- **Open an issue before a large change**, so we can agree on the approach before you spend time on it.
  Small fixes can go straight to a pull request.
- **Logic goes in `VimECore`** with unit tests; `VimE/` is the macOS glue (Accessibility, the event tap,
  windows). CI runs `make test` and a release build on every pull request.
- **Match the existing style:** small, focused changes, comments that explain why, and plain wording in
  anything a user sees.
- **Add a line under Unreleased in `CHANGELOG.md`** for anything a user would notice.
- **Test by hand in the apps your change touches**, and say which ones in the pull request.

By contributing you agree that your work is released under the [MIT License](LICENSE).

## Releasing (maintainer)

1. Make sure `CHANGELOG.md` has the release's notes under Unreleased.
2. `make release V=1.2.3` updates the changelog and version, commits, tags `v1.2.3` and pushes.
3. GitHub Actions (`.github/workflows/release.yml`) tests, builds and signs VimE with the release identity,
   publishes the GitHub release with a .zip and a .dmg, and updates the cask in
   [Dricmoy/homebrew-tap](https://github.com/Dricmoy/homebrew-tap).

Releases are signed with a self-signed "VimE Release Signing" certificate (`scripts/make-release-cert.sh`),
stored as repository secrets. Every release must use the same certificate, or users lose the Accessibility
permission when they update.
