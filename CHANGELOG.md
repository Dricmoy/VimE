# Changelog

What changed in each VimE release. New entries go under **Unreleased**; `make release V=x.y.z` turns that section into the release and its GitHub release notes.

## [Unreleased]

First release.

- **Hints everywhere:** `⌥F` labels every button, link, tab and menu in the frontmost app, including web pages in Chrome and other Chromium browsers. Type a label to click; hold `⇧` to right-click or `⌘` to ⌘-click.
- **Vim keys** in apps you switch On: `f` for hints, `hjkl` smooth scrolling, `d`/`u`, `gg`/`G`, `?` cheat sheet. `Esc` leaves a web or Electron text field, and `i` is an Insert mode for apps where VimE can't tell you're typing.
- **Per-app rules:** On, ⌥F only or Off, from the menu bar, `⌃⌥⌘⇧V` or Settings. Terminals, virtual machines, remote desktops and games start Off.
- **Appearance:** dark, light or classic yellow hints in three sizes, laid out so they never overlap, and an optional `-- INSERT --` indicator.
- **Settings export and import** for using VimE on several Macs.
- **Update notice:** VimE checks GitHub once a day and tells you when a new version is out. It never downloads anything itself; update with Homebrew or from the releases page.
