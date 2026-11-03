APP_NAME  := ClaudeUsageMenubar
BUNDLE_ID := io.github.k-wolfe99.claude-usage-menubar
APP       := build/$(APP_NAME).app
PREFIX    ?= $(HOME)/Applications

# With only the Command Line Tools (no Xcode), swiftc doesn't find the Swift Testing macro
# plugin on its own. Point it there when that directory exists; Xcode users get nothing extra.
TESTING_PLUGIN := $(shell xcode-select -p 2>/dev/null)/usr/lib/swift/host/plugins/testing
TEST_FLAGS     := $(if $(wildcard $(TESTING_PLUGIN)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGIN))

.PHONY: all test build app install uninstall clean

all: app

test:
	swift test $(TEST_FLAGS)

build:
	swift build -c release

# Assemble the .app bundle and sign it ad hoc (local use; no paid developer account needed).
app: build
	@BIN="$$(swift build -c release --show-bin-path)"; \
	rm -rf "$(APP)"; \
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Helpers"; \
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"; \
	cp "$$BIN/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"; \
	cp "$$BIN/claude-usage-export" "$(APP)/Contents/Helpers/claude-usage-export"
	codesign --force --sign - "$(APP)/Contents/Helpers/claude-usage-export"
	codesign --force --sign - "$(APP)"
	@echo "Built $(APP)"

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
