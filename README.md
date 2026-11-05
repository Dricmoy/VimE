# VimE — vim everywhere

> **Work in progress.** This is a personal project, not a finished product. Things break, features are
> half-done, and the behaviour changes between builds. Install at your own risk. See [Notes](#notes)
> below for what is and isn't tested.

Vimium C-style keyboard control for every macOS app: native apps, Chrome and other browsers, and
Electron apps (VS Code, Discord, Notion, Obsidian…).

**License:** MIT — see [LICENSE](LICENSE). Contributions are welcome but this is a one-person project;
> please open an issue first to avoid duplicate work.

## Keys

Outside text fields (plain keys):

| Key | Does |
| --- | --- |
| `f` | Show hint labels on everything clickable |
| `j` `k` | Scroll down / up (hold to keep going) |
| `h` `l` | Scroll left / right |
| `d` `u` | Half page down / up |
| `gg` `G` | Top / bottom |
| `?` | Cheat sheet |

`⌥F` shows hints anywhere, even while typing in a text field.

While hints are showing: type a label to click it. Hold `⇧` on the last letter to right-click,
or `⌘` to ⌘-click (opens links in a new tab). `⌫` undoes a letter, `Esc` cancels.

Plain keys never fire while you type in a text field. Hints cover the focused window and the menu
bar, including open menus, and skip anything scrolled out of view or disabled.

## Per-app rules

Each app is **On** (plain keys and ⌥F), **⌥F only** (plain keys go to the app), or **Off**.
Terminals and Vim GUIs default to ⌥F only. Switch the app you're in from the menu bar icon, or
manage the list in Settings → Apps.

## Build

Requires Xcode and XcodeGen (`brew install xcodegen`).

```sh
make signing  # once: creates a local code-signing identity (own keychain, no password prompts)
make test     # unit tests for VimECore
make run      # build and launch from the build folder
make install  # build Release into /Applications
make dmg      # build.noindex/VimE.dmg, drag-to-Applications installer for other Macs
make icon     # redraw VimE/AppIcon.icns from scripts/make-icon.swift
```

On first launch the setup window walks through granting Accessibility.
The local signing identity keeps that permission across rebuilds; without it builds are
ad-hoc signed and macOS forgets the permission each time.

The .dmg is signed with the local identity, not an Apple Developer ID, so on another Mac the first
open needs right-click → Open (or System Settings → Privacy & Security → Open Anyway).

## Notes

- Chromium browsers (Chrome, Brave, Edge, Arc) only expose web pages to Accessibility clients that
  set `AXEnhancedUserInterface`, which VimE does when one comes to the front. Some window managers
  animate that browser's windows more slowly while it's set.
- Scrolling sends scroll-wheel events at the center of the window's main scroll area, so it works
  wherever the mouse is.
- `/usr/bin/log stream --level debug --predicate 'subsystem == "com.dric.VimE"'` shows each key VimE
  acts on and how long hint lookups take.

## Layout

- `VimECore/` — pure logic, unit tested: key routing and modes, hint labels and sessions, which
  elements get hints (`HintRules`), scrolling math, per-app rules, geometry.
- `VimE/` — macOS glue: event tap, Accessibility tree walk, overlay panels, cheat sheet, menu bar,
  setup and Settings.
