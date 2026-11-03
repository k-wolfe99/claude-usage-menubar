// "Check for Updates": one request to GitHub's public releases API, only when clicked.
// It never downloads or installs anything; a newer version opens its release page.
import Foundation
import UsageCore

enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case failed(String)
}

struct UpdateChecker {
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// "owner/repo" from Info.plist (`UpdateRepository`), so a fork only changes one line.
    static var repository: String? {
        guard let repo = Bundle.main.infoDictionary?["UpdateRepository"] as? String,
              repo.range(of: #"^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
        else { return nil }
        return repo
    }

    /// Calls `completion` on the main queue.
    func check(completion: @escaping (UpdateStatus) -> Void) {
        let finish: (UpdateStatus) -> Void = { status in DispatchQueue.main.async { completion(status) } }
        guard let repo = Self.repository,
              let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return finish(.failed("No update source is configured for this build."))
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("claude-usage-menubar", forHTTPHeaderField: "User-Agent")

        URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
            if let error { return finish(.failed("Couldn't reach GitHub: \(error.localizedDescription)")) }
            switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200:
                guard let data, let release = parseLatestRelease(data) else {
                    return finish(.failed("Couldn't read the latest release from GitHub."))
                }
                finish(isNewerVersion(release.version, than: Self.currentVersion) ? .available(release) : .upToDate)
            case 404:
                finish(.failed("No published release found. The repository may be private."))
            case let code:
                finish(.failed("GitHub returned HTTP \(code)."))
            }
        }.resume()
    }
}
