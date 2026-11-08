DERIVED := build.noindex
APP := $(DERIVED)/Build/Products/Debug/VimE.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/VimE.app
DMG := $(DERIVED)/VimE.dmg
XB := xcodebuild -project VimE.xcodeproj -scheme VimE -derivedDataPath $(DERIVED) -quiet

.PHONY: gen build test run install dmg icon signing clean
gen:
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
# Drag-to-Applications disk image of the Release build, for other Macs.
dmg: gen
	$(XB) -configuration Release build
	scripts/sign.sh $(RELEASE_APP)
	scripts/make-dmg.sh $(RELEASE_APP) $(DMG)
# Redraws VimE/AppIcon.icns from scripts/make-icon.swift.
icon:
	scripts/make-icon.sh
# One-time: creates the local code-signing identity used by build and install.
signing:
	scripts/setup-signing.sh
clean:
	rm -rf $(DERIVED) VimE.xcodeproj
