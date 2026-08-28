import Common
import Foundation

/// AeroSpace-edge versions are `1.MINOR[.PATCH]`. Compared component-wise, numerically — so 1.10 sorts
/// *after* 1.9, which a string comparison would get backwards.
struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    /// Returns nil for anything that isn't a plain dotted-number version. Debug builds report
    /// `0.0.0-SNAPSHOT`, and "is there an update for a snapshot?" has no meaningful answer.
    init?(_ raw: String) {
        let trimmed = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        if parts.isEmpty { return nil }
        var parsed: [Int] = []
        for part in parts {
            guard let n = Int(part), n >= 0 else { return nil }
            parsed.append(n)
        }
        components = parsed
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        // 1.11 and 1.11.0 are the same version; pad the shorter one rather than letting length decide.
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0 ..< count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    var description: String { components.map(String.init).joined(separator: ".") }
}

struct GitHubRelease: Sendable {
    let tag: String
    let version: AppVersion
    let notes: String
    let zipUrl: URL
}

enum UpdateCheckResult {
    case upToDate(current: AppVersion)
    case updateAvailable(GitHubRelease)
    /// Debug/snapshot builds, or a version string we can't parse.
    case notApplicable(reason: String)
    case failed(reason: String)
}

let updateReleasesApiUrl = URL(string: "https://api.github.com/repos/vitorebatista/AeroSpace-edge/releases?per_page=20").orDie()

/// Only these hosts may serve an update. The app replaces its own bundle with whatever it downloads, so
/// the download URL is a trust boundary, not a formality — a redirect or a doctored API response pointing
/// anywhere else is rejected rather than followed.
let allowedUpdateHosts: [String] = ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"]

func isAllowedUpdateUrl(_ url: URL) -> Bool {
    guard url.scheme == "https", let host = url.host()?.lowercased() else { return false }
    return allowedUpdateHosts.contains(host)
}

/// Picks the newest release from a GitHub `/releases` payload.
///
/// Note this cannot use `/releases/latest`: every AeroSpace-edge release is published as a prerelease, and
/// that endpoint skips prereleases entirely — it would report "no updates" forever. So the full list is
/// fetched and the highest *version* wins (not the most recently created, which drafts and out-of-order
/// publishing can get wrong).
func newestRelease(inReleasesJson data: Data) -> GitHubRelease? {
    guard let raw = try? JSONSerialization.jsonObject(with: data), let items = raw as? [[String: Any]] else { return nil }
    return items.compactMap(parseRelease).max { $0.version < $1.version }
}

private func parseRelease(_ item: [String: Any]) -> GitHubRelease? {
    if item["draft"] as? Bool == true { return nil }
    guard let tag = item["tag_name"] as? String, let version = AppVersion(tag) else { return nil }
    let assets = item["assets"] as? [[String: Any]] ?? []
    let zip = assets.lazy.compactMap { asset -> URL? in
        guard let name = asset["name"] as? String, name.hasSuffix(".zip"),
              let urlString = asset["browser_download_url"] as? String,
              let url = URL(string: urlString), isAllowedUpdateUrl(url)
        else { return nil }
        return url
    }.first
    guard let zip else { return nil } // a release with no usable asset isn't something we can install
    return GitHubRelease(tag: tag, version: version, notes: item["body"] as? String ?? "", zipUrl: zip)
}

func checkForUpdate(currentVersion: String = aeroSpaceAppVersion) async -> UpdateCheckResult {
    guard let current = AppVersion(currentVersion) else {
        return .notApplicable(reason: "This is a development build (\(currentVersion)), not a released version.")
    }
    var request = URLRequest(url: updateReleasesApiUrl)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 20
    let data: Data
    do {
        let (body, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            return .failed(reason: "GitHub returned HTTP \(http.statusCode).")
        }
        data = body
    } catch {
        return .failed(reason: error.localizedDescription)
    }
    guard let newest = newestRelease(inReleasesJson: data) else {
        return .failed(reason: "Couldn't read the release list from GitHub.")
    }
    return current < newest.version ? .updateAvailable(newest) : .upToDate(current: current)
}
