# Claude Usage Menubar

A small macOS menu bar app that shows your Claude plan usage: the 5-hour session limit and the 7-day weekly limit, with reset countdowns.

```
⏲ 5h 23% · 7d 41%
```

It holds **no credentials**. It never asks for a claude.ai cookie, never reads a token from the Keychain, and makes no network requests. The numbers come from Claude Code itself, which already passes them to its status line command.

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
- Claude Code signed in with a claude.ai subscription that reports plan limits (Pro, Max, Team). Configurations billed by API key don't receive `rate_limits`, so there is nothing to show.

## Install

```sh
git clone https://github.com/k-wolfe99/claude-usage-menubar.git
cd claude-usage-menubar
make test      # optional
make install   # builds, signs ad hoc, copies to ~/Applications, launches
```

Then add the status line to Claude Code's `settings.json` (`~/.claude/settings.json`, or `$CLAUDE_CONFIG_DIR/settings.json` if you set that variable):

```json
"statusLine": {
  "type": "command",
  "command": "~/Applications/ClaudeUsageMenubar.app/Contents/Helpers/claude-usage-export"
}
```

The numbers appear after your next message in Claude Code. Use **Open at Login** in the menu to start the app automatically.

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

## Limitations

- Usage outside Claude Code (claude.ai, the desktop and mobile apps) shows up only after your next Claude Code response, since that is when Claude Code reports fresh numbers.
- After a window resets with no newer data, the app shows 0% and says it is waiting for new data.
- `rate_limits` comes from Claude Code's documented status line input; if a plan doesn't report it, the menu shows "no data".

## State file

```json
{
  "updated_at": 1793692857.18,
  "windows": {
    "five_hour": { "used_percentage": 2,  "resets_at": 1793706000, "observed_at": 1793692857.18 },
    "seven_day": { "used_percentage": 16, "resets_at": 1793854800, "observed_at": 1793692857.18 }
  }
}
```

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
Sources/ClaudeUsageMenubar/   AppKit menu bar app
Tests/UsageCoreTests/         Swift Testing suite
fixtures/                     sample status line input (anonymized)
```

`make test` runs the suite. With only the Command Line Tools installed, it passes the Swift Testing macro plugin path that `swiftc` doesn't find on its own.

## License

MIT
