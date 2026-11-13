DERIVED := build.noindex
APP := $(DERIVED)/Build/Products/Debug/VimE.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/VimE.app
DMG := $(DERIVED)/VimE.dmg
# Release builds: VERSION defaults to project.yml's, BUILD (the bundle version) to 1; CI passes both.
VERSION ?= $(shell sed -n -E 's/^ *MARKETING_VERSION: "(.*)"/\1/p' project.yml)
BUILD ?= 1
XB := xcodebuild -project VimE.xcodeproj -scheme VimE -derivedDataPath $(DERIVED) -quiet

.PHONY: gen build test run install update setup check-tools dmg package release icon signing clean
gen: check-tools
	xcodegen generate --quiet
build: gen
	$(XB) -configuration Debug build
	scripts/sign.sh $(APP)
# build-for-testing rebuilds the app too, so re-sign it or macOS forgets the Accessibility permission.
test: gen
	$(XB) -configuration Debug build-for-testing
	scripts/sign.sh $(APP)
	xcrun xctest $(DERIVED)/Build/Products/Debug/VimECoreTests.xctest
run: build
	-pkill -x VimE
	open $(APP)
# Release build copied to /Applications so VimE shows up in Spotlight and Launchpad.
install: gen
	$(XB) -configuration Release build
	scripts/sign.sh $(RELEASE_APP)
	-pkill -x VimE
	rm -rf /Applications/VimE.app
	ditto $(RELEASE_APP) /Applications/VimE.app
	open /Applications/VimE.app
# Pulls the latest code and reinstalls. Your settings and Accessibility permission are kept.
update:
	git pull --ff-only
	$(MAKE) install
# First time on a Mac: signing identity, then install.
setup: check-tools signing install
check-tools:
	@xcodebuild -version >/dev/null 2>&1 || { echo "Xcode is needed: install it from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"; exit 1; }
	@command -v xcodegen >/dev/null || { echo "XcodeGen is needed: brew install xcodegen"; exit 1; }
# Drag-to-Applications disk image of the Release build, for other Macs.
dmg: gen
	$(XB) -configuration Release build
	scripts/sign.sh $(RELEASE_APP)
	scripts/make-dmg.sh $(RELEASE_APP) $(DMG)
# What a release ships: VimE-<version>.zip (for Homebrew) and VimE-<version>.dmg, in build.noindex.
package: gen
	$(XB) -configuration Release MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD) build
	scripts/sign.sh $(RELEASE_APP)
	rm -f $(DERIVED)/VimE-$(VERSION).zip
	ditto -c -k --keepParent $(RELEASE_APP) $(DERIVED)/VimE-$(VERSION).zip
	scripts/make-dmg.sh $(RELEASE_APP) $(DERIVED)/VimE-$(VERSION).dmg
# Maintainer: make release V=1.2.3 tags and pushes; GitHub Actions builds and publishes it.
release:
	scripts/release.sh $(V)
# Redraws VimE/AppIcon.icns from scripts/make-icon.swift.
icon:
	scripts/make-icon.sh
# One-time: creates the local code-signing identity used by build and install.
signing:
	scripts/setup-signing.sh
clean:
	rm -rf $(DERIVED) VimE.xcodeproj
