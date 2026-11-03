APP_NAME  := ClaudeUsageMenubar
BUNDLE_ID := io.github.k-wolfe99.claude-usage-menubar
APP       := build/$(APP_NAME).app
PREFIX    ?= $(HOME)/Applications
VERSION   := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
DMG       := build/$(APP_NAME)-$(VERSION).dmg
UNIVERSAL := build/universal/$(APP_NAME).app
MIN_MACOS := 14.0

# With only the Command Line Tools (no Xcode), swiftc doesn't find the Swift Testing macro
# plugin on its own. Point it there when that directory exists; Xcode users get nothing extra.
TESTING_PLUGIN := $(shell xcode-select -p 2>/dev/null)/usr/lib/swift/host/plugins/testing
TEST_FLAGS     := $(if $(wildcard $(TESTING_PLUGIN)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGIN))

.PHONY: all test build app install uninstall clean universal dmg

all: app

test:
	swift test $(TEST_FLAGS)

build:
	swift build -c release

# Assemble the .app bundle for this Mac's architecture and sign it ad hoc.
app: build
	@scripts/bundle.sh "$(APP)" "$$(swift build -c release --show-bin-path)"

# Apple silicon + Intel in one app.
universal:
	swift build -c release --triple arm64-apple-macosx$(MIN_MACOS) --scratch-path .build/arm64
	swift build -c release --triple x86_64-apple-macosx$(MIN_MACOS) --scratch-path .build/x86_64
	@scripts/bundle.sh "$(UNIVERSAL)" \
		"$$(swift build -c release --triple arm64-apple-macosx$(MIN_MACOS) --scratch-path .build/arm64 --show-bin-path)" \
		"$$(swift build -c release --triple x86_64-apple-macosx$(MIN_MACOS) --scratch-path .build/x86_64 --show-bin-path)"

# Disk image with the universal app and a shortcut to /Applications.
dmg: universal
	rm -rf build/dmg "$(DMG)"
	mkdir -p build/dmg
	cp -R "$(UNIVERSAL)" build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "Claude Usage" -srcfolder build/dmg -fs HFS+ -format UDZO -ov "$(DMG)"
	rm -rf build/dmg
	@shasum -a 256 "$(DMG)"

install: app
	@osascript -e 'quit app id "$(BUNDLE_ID)"' >/dev/null 2>&1 || true
	mkdir -p "$(PREFIX)"
	rm -rf "$(PREFIX)/$(APP_NAME).app"
	cp -R "$(APP)" "$(PREFIX)/"
	open "$(PREFIX)/$(APP_NAME).app"
	@echo ""
	@echo "Installed. Status line command for Claude Code's settings.json:"
	@echo "  $(PREFIX)/$(APP_NAME).app/Contents/Helpers/claude-usage-export"

uninstall:
	@osascript -e 'quit app id "$(BUNDLE_ID)"' >/dev/null 2>&1 || true
	rm -rf "$(PREFIX)/$(APP_NAME).app"
	rm -rf "$(HOME)/Library/Application Support/claude-usage-menubar"
	@echo "Removed. Also delete the statusLine entry from Claude Code's settings.json."

clean:
	rm -rf build .build
