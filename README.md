# Claude Usage Menubar

A small macOS menu bar app that shows your Claude plan usage: the 5-hour session limit and the 7-day weekly limit, with reset countdowns.

- **Menu bar:** a gauge and the percentage of whichever limit is closest to running out, coloured green (under 50%), yellow (under 75%), orange (under 90%) or red. If the menu bar has no room for the percentage, it shows the coloured gauge alone.
- **Click it** for a card with a colour-coded bar per limit, reset times, when the numbers last updated, a Refresh button, Open at Login and Quit. Click the gauge again, click elsewhere, or press Esc to close it.

**You never paste a session cookie.** Unlike apps that ask you to copy your claude.ai `Cookie` header out of the browser's developer tools, this app gets its numbers from Claude Code itself, which already passes them to its status line command.

## Two ways to use it

### Without any credential (default)

Install it and add the status line. The app then reads only a local file written by Claude Code's status line. It never reads the Keychain, and makes no network requests unless you click Refresh or Check for Updates. As long as you never click Refresh, it holds no credential of any kind.

Limitations of this mode:

- **Updates only when Claude Code responds.** Numbers change after each Claude Code response, not on a timer.
- **Usage elsewhere shows up late.** Usage on claude.ai, the Claude desktop and mobile apps, or Claude in other apps (e.g. Microsoft 365) counts against the same limits, but appears here only after your next Claude Code response.
- **Only the 5-hour and 7-day limits.** That's what Claude Code's status line reports. No per-model weekly limits (unless Claude Code starts reporting them, in which case they appear as extra rows automatically), no extra-usage credits, no service status.
- **After a window resets** with no newer data, the app shows 0% and says it is waiting for new data.
- **Requires a subscription that reports plan limits** (Pro, Max, Team). Configurations billed by API key don't receive `rate_limits`, so there is nothing to show.

### With Refresh (optional, on click)

The ↻ button in the card fetches current usage directly from Anthropic, including usage from claude.ai and the Claude apps. **It runs only when you click it.** Nothing happens in the background.

When you click it, the app:

1. Reads Claude Code's OAuth login from the Keychain item Claude Code created (`Claude Code-credentials`, or `Claude Code-credentials-<8 hex>` when `CLAUDE_CONFIG_DIR` is set). The exporter records which item belongs to the Claude Code configuration you're tracking, so the same account is used. macOS asks your permission the first time; choose **Always Allow** to skip the prompt in future. Because the app is signed ad hoc, macOS asks again after you install a new build.
2. Sends one HTTPS request to `https://api.anthropic.com/api/oauth/usage`, the endpoint behind Claude Code's `/usage` command.
3. Merges the result into the same state file.

The token is used for that one request only. It is never written to disk, never logged, never sent anywhere else, and never renewed. If it has expired, the app asks you to use Claude Code once (which renews it) instead.

Caveats:

- The endpoint is undocumented and may change without notice.
- Using Claude Code's login from another app may not be sanctioned by Anthropic's terms. If that matters to you, don't click Refresh: everything else works without it.
- To revoke access later, open **Keychain Access**, find the `Claude Code-credentials` item, and remove `ClaudeUsageMenubar` under **Access Control**.

## How it works

```
Claude Code ──(status line JSON on stdin)──▶ claude-usage-export ──▶ usage.json ──▶ menu bar app
```

1. Claude Code runs a [status line](https://code.claude.com/docs/en/statusline) command after each response and pipes it a JSON document. For claude.ai subscription plans that document includes `rate_limits.five_hour` and `rate_limits.seven_day`, each with `used_percentage` and `resets_at`.
2. `claude-usage-export` is that command. It reads `rate_limits`, merges it into `~/Library/Application Support/claude-usage-menubar/usage.json`, and prints nothing.
3. The menu bar app watches that file.

Several Claude Code sessions can share the file, and an idle session can re-run its status line with old numbers. The merge keeps stale data from winning:

- Within the same window, usage only rises, so the higher percentage is kept.
- A later window replaces an earlier one. A reading from an earlier window is ignored.
- Readings whose window has already reset are ignored.

Writes are atomic and serialized with a file lock.

## Requirements

- macOS 14 or later
- Swift 6 toolchain: Xcode, or just the Command Line Tools (`xcode-select --install`)
- Claude Code signed in with a claude.ai subscription that reports plan limits (Pro, Max, Team)

## Install

### From the disk image

1. Download `ClaudeUsageMenubar-<version>.dmg` from [Releases](https://github.com/k-wolfe99/claude-usage-menubar/releases), open it, and drag **ClaudeUsageMenubar** to **Applications**. It's a universal app (Apple silicon and Intel).
2. Open it. The app is signed ad hoc, not with an Apple Developer ID, so the first time macOS says it can't verify the developer. Go to **System Settings → Privacy & Security**, scroll to the message about ClaudeUsageMenubar, and click **Open Anyway**. You only need to do this once per version. If you'd rather not, build it yourself (below); locally built apps aren't quarantined.

### From source

```sh
git clone https://github.com/k-wolfe99/claude-usage-menubar.git
cd claude-usage-menubar
make test      # optional
make install   # builds, signs ad hoc, copies to ~/Applications, launches
```

### Connect it to Claude Code

Add the status line to Claude Code's `settings.json` (`~/.claude/settings.json`, or `$CLAUDE_CONFIG_DIR/settings.json` if you set that variable). Use the path where the app is installed: `/Applications/...` from the disk image, `~/Applications/...` from source.

```json
"statusLine": {
  "type": "command",
  "command": "/Applications/ClaudeUsageMenubar.app/Contents/Helpers/claude-usage-export"
}
```

The numbers appear after your next message in Claude Code. Use **Open at Login** in the card to start the app automatically.

If you can't see the gauge, macOS has probably hidden it for lack of space (common beside the notch). Remove or ⌘-drag away another menu bar item, then relaunch the app.

### Show usage in Claude Code too

Add `--print` to the command to also display `5h 23% · 7d 41%` as Claude Code's status line.

### Already have a status line?

Feed the same JSON to both. For example, in your existing status line script:

```sh
input=$(cat)
printf '%s' "$input" | ~/Applications/ClaudeUsageMenubar.app/Contents/Helpers/claude-usage-export
# ...the rest of your script, reading from "$input"
```

### Several Claude Code configurations

If you run more than one Claude Code configuration (for example separate `CLAUDE_CONFIG_DIR`s for different accounts), add the status line only to the configuration whose account you want to track. Each configuration reads its own `settings.json`. A configuration billed by API key never receives `rate_limits`, so even if it ran the exporter, nothing would be written.

## Updates

The card shows the installed version and a **Check for Updates** link. Clicking it sends one request to GitHub's public API for this repository's latest release (no login, nothing sent about you). If a newer version exists, **Download** opens its release page; install it the same way as the first time. The app never downloads or installs anything by itself, and never checks unless you click.

The repository it checks is the `UpdateRepository` key in `Resources/Info.plist`, so a fork only needs to change that line.

## State file

```json
{
  "updated_at": 1793692857.18,
  "windows": {
    "five_hour": { "used_percentage": 2,  "resets_at": 1793706000, "observed_at": 1793692857.18 },
    "seven_day": { "used_percentage": 16, "resets_at": 1793854800, "observed_at": 1793692857.18 }
  },
  "credential_service": "Claude Code-credentials"
}
```

`credential_service` is the *name* of the Keychain item Refresh may read, never its contents. The app accepts only Claude Code's own item names.

Times are Unix epoch seconds. Set `CLAUDE_USAGE_MENUBAR_STATE` to use a different path (both programs honour it; the app only sees it when launched from a shell).

## Uninstall

```sh
make uninstall
```

Then remove the `statusLine` entry from Claude Code's `settings.json`, and turn off **Open at Login** first if you enabled it.

## Development

```
Sources/UsageCore/            parsing, merge rules, formatting, state file (unit tested)
Sources/claude-usage-export/  status line command
Sources/ClaudeUsageMenubar/   AppKit status item + SwiftUI card; Refresh.swift is the only network/Keychain code
Tests/UsageCoreTests/         Swift Testing suite
fixtures/                     sample status line input and usage API response (anonymized)
```

`make test` runs the suite. `make dmg` builds the universal app and the disk image in `build/`.

### Releasing

```sh
make release V=0.2.0 NOTES=~/notes-0.2.0.md DRY=1   # rehearse: builds the DMG, changes nothing
make release V=0.2.0 NOTES=~/notes-0.2.0.md         # publish
```

`scripts/release.sh` checks you're on a clean `main` in sync with `origin`, that the version is newer and its tag doesn't exist, then bumps `Info.plist`, runs the tests, builds the DMG, commits, tags, pushes, and creates the GitHub release with the DMG and its SHA-256 appended to your notes. Keep the notes file outside the repository. With only the Command Line Tools installed, it passes the Swift Testing macro plugin path that `swiftc` doesn't find on its own.

## License

MIT
