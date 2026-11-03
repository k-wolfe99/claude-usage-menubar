// Optional on-demand refresh. Runs only when the user clicks Refresh:
//   1. reads Claude Code's OAuth token from the Keychain (macOS asks the user the first time),
//   2. sends one GET to api.anthropic.com/api/oauth/usage,
//   3. merges the result into the shared state file.
// The token is held in memory for that one request. It is never stored, logged, or renewed.
import Foundation
import Security
import UsageCore

enum RefreshError: LocalizedError {
    case noLogin
    case expired
    case keychainDenied
    case keychain(OSStatus)
    case http(Int)
    case network(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .noLogin: return "No Claude Code login found. Sign in to Claude Code first."
        case .expired: return "Claude Code's login has expired. Use Claude Code once to renew it, then try again."
        case .keychainDenied: return "Keychain access was denied, so usage wasn't refreshed."
        case .keychain(let status): return "Couldn't read Claude Code's login (Keychain error \(status))."
        case .http(401), .http(403): return "Anthropic rejected the login. Use Claude Code once to renew it, then try again."
        case .http(let code): return "Anthropic's usage service returned HTTP \(code)."
        case .network(let message): return "Couldn't reach Anthropic: \(message)"
        case .noData: return "Anthropic's response contained no usage limits."
        }
    }
}

struct UsageFetcher {
    let store: StateStore
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Calls `completion` on the main queue.
    func refresh(completion: @escaping (Result<Void, RefreshError>) -> Void) {
        let finish: (Result<Void, RefreshError>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }
        // The Keychain call blocks while macOS shows its permission prompt, so keep it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let token: String
            switch readToken() {
            case .success(let t): token = t
            case .failure(let error): return finish(.failure(error))
            }

            var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("claude-usage-menubar", forHTTPHeaderField: "User-Agent")

            // Ephemeral: no cookies, cache or credentials persisted by URLSession.
            URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
                if let error { return finish(.failure(.network(error.localizedDescription))) }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200, let data else { return finish(.failure(.http(status))) }
                let readings = parseOAuthUsage(data)
                guard !readings.isEmpty else { return finish(.failure(.noData)) }
                do {
                    try store.update(with: readings)
                    finish(.success(()))
                } catch {
                    finish(.failure(.network(error.localizedDescription)))
                }
            }.resume()
        }
    }

    /// The login of the Claude Code install that wrote the state file, falling back to the
    /// install named by this process's CLAUDE_CONFIG_DIR (or Claude Code's default).
    private var service: String {
        if let recorded = store.load()?.credentialService, isValidCredentialService(recorded) {
            return recorded
        }
        return credentialService(configDir: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"])
    }

    private func readToken() -> Result<String, RefreshError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: break
        case errSecItemNotFound: return .failure(.noLogin)
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed: return .failure(.keychainDenied)
        default: return .failure(.keychain(status))
        }
        guard let data = item as? Data else { return .failure(.noLogin) }
        switch accessToken(fromKeychainData: data, now: Date()) {
        case .valid(let token): return .success(token)
        case .expired: return .failure(.expired)
        case .missing: return .failure(.noLogin)
        }
    }
}
