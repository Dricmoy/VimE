#!/bin/bash
# Prints the Homebrew cask for a release: scripts/write-cask.sh <version> <sha256 of VimE-<version>.zip>
set -euo pipefail
VERSION="$1"
SHA="$2"
cat <<RUBY
cask "vime" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/Dricmoy/VimE/releases/download/v#{version}/VimE-#{version}.zip"
  name "VimE"
  desc "Keyboard hints and Vim-style scrolling for every app"
  homepage "https://github.com/Dricmoy/VimE"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "VimE.app"

  zap trash: [
    "~/Library/HTTPStorages/com.dric.VimE",
    "~/Library/Preferences/com.dric.VimE.plist",
  ]

  caveats <<~EOS
    VimE isn't notarized by Apple yet, so macOS blocks the first launch of each new version.
    Open VimE once, then allow it in System Settings → Privacy & Security → Open Anyway.

    After an upgrade, quit VimE from its menu bar icon and open it again.
  EOS
end
RUBY
