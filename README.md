# VimE — vim everywhere

> **Work in progress.** This is a personal project, not a finished product. Things break, features are
> half-done, and behaviour changes between builds. There is no signed release yet; you build it
> yourself. See [Status](#status) for what is and isn't tested.

Vimium C-style keyboard control for every macOS app: native apps, Chrome and other Chromium browsers,
and Electron apps. Press a key, every button, link and tab gets a short label, type the label to
click it. Scroll with `hjkl`. No browser extension, no mouse.

![Hint labels over Hacker News in Chrome](docs/hints.png)

## Keys

| Key | Does |
| --- | --- |
| `⌥F` | Show hint labels on everything clickable, in any app, even while typing |
| `f` | Same, in apps you've switched **On** (outside text fields) |
| `j` `k` | Scroll down / up (hold to keep going) |
| `h` `l` | Scroll left / right |
| `d` `u` | Half page down / up |
| `gg` `G` | Top / bottom |
| `?` | Cheat sheet |
| `⌃⌥⌘V` | Turn VimE on or off everywhere |
| `⌃⌥⌘⇧V` | Switch the app you're in: On → ⌥F only → Off |

While hints are showing: type a label to click it. Hold `⇧` on the last letter to right-click, or
`⌘` to ⌘-click (opens links in a new tab). `⌫` undoes a letter, `Esc` cancels.

Plain keys never fire while you type in a text field. Hints cover the focused window and the menu
bar (including open menus), and skip anything scrolled out of view, clipped, disabled, or in an
auto-hidden menu bar.

## Per-app rules

Each app is one of:

- **On**: plain keys (`f`, `hjkl`, `gg`…) outside text fields, plus `⌥F`.
- **⌥F only**: every plain key goes to the app; `⌥F` still shows hints.
- **Off**: VimE ignores the app entirely.

Plain keys are opt-in: apps you haven't set get **⌥F only**, so games, editors and anything else with
its own single-key shortcuts keep working. Turn an app On from the menu bar icon, with `⌃⌥⌘⇧V`, or in
Settings → Apps. "Apps you haven't set" in Settings changes that default. Terminals and Vim GUIs are
⌥F only out of the box.

<img src="docs/settings.png" alt="VimE Settings" width="420">

## Status

Works, tested by hand on macOS 26 (Apple silicon):

- Hints in native apps (Finder, System Settings…) and Chrome, including the web page.
- Scrolling, cheat sheet, per-app rules, menu bar switch, setup flow.
- 48 unit tests for the core logic (`make test`).

Built but not yet tried by hand: the `⌃⌥⌘V` / `⌃⌥⌘⇧V` shortcuts and their on-screen message, and the
opt-in default.

Not tested yet: VS Code, Discord, Notion, Obsidian, Safari, multiple displays, full-screen apps.

Known issues:

- In Chrome, links hidden with `opacity: 0`, `clip-path`, `transform: scale(0)`, or covered by another
  element still get hints. Chrome reports them to Accessibility clients exactly like visible links.
- No Developer ID signing or notarization, so other Macs need right-click → Open the first time.
- `f` and `V` shortcuts use key positions on a US layout.

Ideas: a mode indicator (Normal / Insert / Hint) with a choice of where it sits, a sticky Insert mode
on `i`, detecting games and turning VimE off in them.

## Install

Requires macOS 14+, Xcode, and XcodeGen (`brew install xcodegen`).

```sh
git clone https://github.com/Dricmoy/VimE.git && cd VimE
make signing  # once: a local code-signing identity, so Accessibility permission survives rebuilds
make install  # Release build into /Applications, then launches it
```

On first launch the setup window walks through granting Accessibility access. That permission is
all VimE needs; nothing leaves your Mac.

Other targets:

```sh
make test     # unit tests for VimECore
make run      # build and launch from the build folder
make dmg      # build.noindex/VimE.dmg, drag-to-Applications installer for other Macs
make icon     # redraw VimE/AppIcon.icns from scripts/make-icon.swift
```

Without `make signing`, builds are ad-hoc signed and macOS forgets the Accessibility permission on
every rebuild. The .dmg is signed with the same local identity, not an Apple Developer ID, so on
another Mac the first open needs right-click → Open (or System Settings → Privacy & Security →
Open Anyway).

## How it works

A menu bar app with three parts:

1. A session-wide `CGEventTap` sees every key-down and decides, per key, whether VimE acts on it
   or lets it through (`VimECore/KeyRouter.swift`).
2. On `f` / `⌥F`, it walks the frontmost app's Accessibility tree off the main thread and keeps the
   elements a person could click (`VimECore/HintRules.swift`, `VimE/Accessibility.swift`).
3. Labels are drawn in a transparent, click-through panel that never takes focus
   (`VimE/Overlay.swift`). Typing a label presses the element through Accessibility, or clicks
   its center when it has no press action.

Notes:

- Chromium browsers (Chrome, Brave, Edge, Arc) only expose web pages to Accessibility clients that
  set `AXEnhancedUserInterface`, which VimE does when one comes to the front. Some window managers
  animate that browser's windows more slowly while it's set. Electron apps get the lighter
  `AXManualAccessibility`.
- Scrolling sends scroll-wheel events at the center of the window's main scroll area, so it works
  wherever the mouse is.

## Debugging

- `/usr/bin/log stream --level debug --predicate 'subsystem == "com.dric.VimE"'` shows each key VimE
  acts on and how long hint lookups take.
- Debug builds can list the hints VimE would show in an app without pressing anything:

  ```sh
  make build
  open -n -g -W build.noindex/Build/Products/Debug/VimE.app --args --dump-hints <pid> /tmp/hints.txt
  ```

  Add `--attrs` for every Accessibility attribute of each target.

## Layout

- `VimECore/`: pure logic, unit tested. Key routing and modes, hint labels and sessions, which
  elements get hints (`HintRules`), menu bar visibility, scrolling math, per-app rules, geometry.
- `VimE/`: macOS glue. Event tap, Accessibility tree walk, overlay panels, cheat sheet, toast,
  menu bar, setup and Settings.
- `VimECoreTests/`: XCTest suite for `VimECore`.
- `scripts/`: signing, .dmg and icon scripts used by the Makefile.

## License

MIT, see [LICENSE](LICENSE). This is a one-person project; please open an issue before a large PR.
