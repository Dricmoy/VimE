import AppKit
import VimECore

/// Asks GitHub once a day whether a newer VimE release is out. It only reads the latest release's
/// version and page; it never downloads or installs anything. Main thread only.
final class UpdateChecker {
    struct Release: Equatable {
        var version: String
        var page: URL
    }

    static let repo = "Dricmoy/VimE"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases")!
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// A newer release than this copy, or nil when up to date (or not checked yet).
    private(set) var available: Release?
    /// After every check: the newer release, if any, or the error.
    var onResult: (Result<Release?, Error>) -> Void = { _ in }

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            timer?.invalidate()
            timer = nil
            guard isEnabled else { return }
            // Hourly ticks, but only a tick a day after the last check asks GitHub. The first waits a
            // little, so launching at login doesn't race the network coming up.
            timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
                self?.checkIfDue()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                guard let self, self.isEnabled else { return }
                self.checkIfDue()
            }
        }
    }

    private var timer: Timer?
    private var inFlight = false
    private static let lastCheckKey = "lastUpdateCheck"

    private func checkIfDue() {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        if UpdateCheck.isDue(lastCheck: last, now: Date()) { checkNow() }
    }

    func checkNow() {
        guard !inFlight else { return }
        inFlight = true
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("VimE/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let result = Self.read(data: data, response: response, error: error)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.inFlight = false
                if case .success(let release) = result {
                    UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                    self.available = release
                }
                self.onResult(result)
            }
        }.resume()
    }

    private struct LatestRelease: Decodable {
        var tag_name: String
        var html_url: URL
    }

    private static func read(data: Data?, response: URLResponse?, error: Error?) -> Result<Release?, Error> {
        if let error { return .failure(error) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 404: no published release yet, so nothing newer.
        if status == 404 { return .success(nil) }
        guard status == 200, let data, let latest = try? JSONDecoder().decode(LatestRelease.self, from: data) else {
            return .failure(URLError(.badServerResponse))
        }
        guard let newer = UpdateCheck.newer(latestTag: latest.tag_name, current: currentVersion) else {
            return .success(nil)
        }
        return .success(Release(version: newer.description, page: latest.html_url))
    }
}
