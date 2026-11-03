// Claude Code status line command.
//
// Claude Code pipes its status line JSON to stdin. This reads `rate_limits` from it, merges the
// values into the shared state file, and exits. It never touches the network or any credential.
//
// By default it prints nothing, so it adds no visible status line. With `--print` it prints a
// one-line summary ("5h 2% · 7d 16%") for Claude Code to display.
import Foundation
import UsageCore

let printSummary = CommandLine.arguments.dropFirst().contains("--print")
let input = FileHandle.standardInput.readDataToEndOfFile()
let readings = parseRateLimits(input)
let store = StateStore()

// A status line must never fail loudly: any error just leaves the previous state in place.
if !readings.isEmpty {
    _ = try? store.update(with: readings)
}

if printSummary, let state = store.load() {
    print(menuBarTitle(state, now: Date()))
}
