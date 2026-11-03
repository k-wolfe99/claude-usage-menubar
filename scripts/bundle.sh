#!/bin/bash
# Assemble and ad-hoc sign ClaudeUsageMenubar.app.
# Usage: scripts/bundle.sh OUT_APP BIN_DIR [BIN_DIR...]
# With several BIN_DIRs (one per architecture), the binaries are merged into a universal app.
set -euo pipefail

out=$1; shift
bin_dirs=("$@")

rm -rf "$out"
mkdir -p "$out/Contents/MacOS" "$out/Contents/Helpers"
cp Resources/Info.plist "$out/Contents/Info.plist"

merge() { # merge NAME DEST
    local inputs=()
    for dir in "${bin_dirs[@]}"; do inputs+=("$dir/$1"); done
    lipo -create "${inputs[@]}" -output "$2"
}
merge ClaudeUsageMenubar "$out/Contents/MacOS/ClaudeUsageMenubar"
merge claude-usage-export "$out/Contents/Helpers/claude-usage-export"

# Sign the nested helper first, then the bundle (ad hoc: no developer account needed).
codesign --force --sign - "$out/Contents/Helpers/claude-usage-export"
codesign --force --sign - "$out"
echo "Built $out ($(lipo -archs "$out/Contents/MacOS/ClaudeUsageMenubar"))"
