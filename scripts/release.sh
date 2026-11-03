#!/bin/bash
# Publish a new version: bump, test, build the DMG, commit, tag, push, create the GitHub release.
# Usage: scripts/release.sh VERSION NOTES_FILE [--dry-run]
#   --dry-run  does everything up to and including the DMG build, then restores Info.plist
#              and stops: nothing is committed, tagged, pushed or published.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "release: $*" >&2; exit 1; }
version=${1:-}; notes=${2:-}; mode=${3:-}
[[ -n $version && -n $notes ]] || fail "usage: scripts/release.sh VERSION NOTES_FILE [--dry-run]"
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 1.2.3, got '$version'"
[[ -f $notes ]] || fail "notes file not found: $notes"

plist=Resources/Info.plist
pb() { /usr/libexec/PlistBuddy -c "$1" "$plist"; }
current=$(pb "Print CFBundleShortVersionString")
newest=$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -1)
[[ $version != "$current" && $newest == "$version" ]] || fail "$version is not newer than the current $current"

[[ $(git rev-parse --abbrev-ref HEAD) == main ]] || fail "not on main"
[[ -z $(git status --porcelain) ]] || fail "working tree not clean (keep the notes file outside the repo)"
git fetch -q origin
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || fail "main is not in sync with origin/main"
! git rev-parse -q --verify "refs/tags/v$version" >/dev/null || fail "tag v$version already exists"
[[ $mode == --dry-run ]] || gh auth status >/dev/null 2>&1 || fail "gh is not logged in"

restore() { git checkout -q -- "$plist"; }
trap 'restore' ERR

build=$(( $(pb "Print CFBundleVersion") + 1 ))
pb "Set :CFBundleShortVersionString $version"
pb "Set :CFBundleVersion $build"
echo "==> v$version (build $build): running tests"
make test
echo "==> building DMG"
make dmg
dmg=build/ClaudeUsageMenubar-$version.dmg
[[ -f $dmg ]] || fail "expected $dmg"
sha=$(shasum -a 256 "$dmg" | cut -d' ' -f1)

if [[ $mode == --dry-run ]]; then
    restore
    trap - ERR
    echo "==> dry run OK: $dmg ($sha). Info.plist restored; nothing committed or published."
    exit 0
fi
trap - ERR

git commit -q -m "Release v$version" -- "$plist"
git tag -a "v$version" -m "v$version"
git push -q origin main "v$version"

body=$(mktemp)
{ cat "$notes"; printf '\n\nSHA-256: `%s`\n' "$sha"; } > "$body"
gh release create "v$version" "$dmg" --title "v$version" --notes-file "$body" --verify-tag
rm -f "$body"
echo "==> released v$version"
