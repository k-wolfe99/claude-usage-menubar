// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageMenubar",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: parse status line input, merge into the state file, format for display.
        .target(name: "UsageCore"),
        // Status line command: reads Claude Code's JSON on stdin, updates the state file, prints nothing.
        .executableTarget(name: "claude-usage-export", dependencies: ["UsageCore"]),
        // Menu bar app: watches the state file. No network, no Keychain.
        .executableTarget(name: "ClaudeUsageMenubar", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ],
    swiftLanguageModes: [.v5]
)
