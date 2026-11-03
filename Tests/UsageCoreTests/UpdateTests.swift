import Foundation
import Testing
@testable import UsageCore

@Suite struct UpdateTests {
    @Test(arguments: [
        ("0.2.0", "0.1.0", true), ("0.1.0", "0.1.0", false), ("0.1.0", "0.2.0", false),
        ("v0.1.1", "0.1.0", true), ("0.10.0", "0.9.9", true), ("1.0", "0.9.9", true),
        ("0.1", "0.1.0", false), ("0.1.0.1", "0.1.0", true), ("garbage", "0.1.0", false),
    ])
    func newerVersionDetection(candidate: String, current: String, newer: Bool) {
        #expect(isNewerVersion(candidate, than: current) == newer)
    }

    @Test func readsLatestReleaseFromGitHubResponse() {
        let json = #"""
        {"tag_name":"v0.2.0","name":"v0.2.0","draft":false,"prerelease":false,
         "html_url":"https://github.com/owner/repo/releases/tag/v0.2.0",
         "assets":[{"name":"ClaudeUsageMenubar-0.2.0.dmg",
                    "browser_download_url":"https://github.com/owner/repo/releases/download/v0.2.0/ClaudeUsageMenubar-0.2.0.dmg"}]}
        """#
        let release = parseLatestRelease(Data(json.utf8))
        #expect(release == ReleaseInfo(version: "0.2.0",
                                       pageURL: URL(string: "https://github.com/owner/repo/releases/tag/v0.2.0")!))
    }

    @Test func rejectsDraftsPrereleasesAndNonGitHubLinks() {
        let draft = #"{"tag_name":"v9.0.0","draft":true,"prerelease":false,"html_url":"https://github.com/o/r/releases/tag/v9.0.0"}"#
        let pre = #"{"tag_name":"v9.0.0","draft":false,"prerelease":true,"html_url":"https://github.com/o/r/releases/tag/v9.0.0"}"#
        let offsite = #"{"tag_name":"v9.0.0","draft":false,"prerelease":false,"html_url":"https://evil.example/download"}"#
        let insecure = #"{"tag_name":"v9.0.0","draft":false,"prerelease":false,"html_url":"http://github.com/o/r/releases/tag/v9.0.0"}"#
        for json in [draft, pre, offsite, insecure] {
            #expect(parseLatestRelease(Data(json.utf8)) == nil)
        }
    }

    @Test func notFoundResponseYieldsNothing() {
        // What GitHub returns for a private or missing repository.
        #expect(parseLatestRelease(Data(#"{"message":"Not Found","status":"404"}"#.utf8)) == nil)
    }
}
