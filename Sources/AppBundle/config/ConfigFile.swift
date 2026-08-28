import Common
import Foundation

let configDotfileName = ".aerospace-edge.toml"
let upstreamConfigDotfileName = ".aerospace.toml"

func findCustomConfigUrl() -> ConfigFile {
    let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/")
    let home = FileManager.default.homeDirectoryForCurrentUser

    if let configLocation = serverArgs.configLocation {
        return resolve([URL(filePath: configLocation)])
    }

    for tier in configCandidateTiers(home: home, xdgConfigHome: xdgConfigHome) {
        switch resolve(tier) {
            case .noCustomConfigExists: continue
            case let resolved: return resolved
        }
    }
    return .noCustomConfigExists
}

/// Config lookup, in priority order: AeroSpace-edge's own config first, an upstream AeroSpace config as a
/// fallback. That way the fork can be installed next to upstream and compared against it on the very same
/// config, while `~/.aerospace-edge.toml` stays available for fork-only options upstream would reject.
/// The tiers are resolved independently, so an own config and an upstream config are never "ambiguous"
/// with each other — the own one just wins.
func configCandidateTiers(home: URL, xdgConfigHome: URL) -> [[URL]] {
    [
        [
            home.appending(path: configDotfileName),
            xdgConfigHome.appending(path: "aerospace-edge").appending(path: "aerospace-edge.toml"),
        ],
        [
            home.appending(path: upstreamConfigDotfileName),
            xdgConfigHome.appending(path: "aerospace").appending(path: "aerospace.toml"),
        ],
    ]
}

private func resolve(_ candidates: [URL]) -> ConfigFile {
    let existingCandidates: [URL] = candidates.filter { (candidate: URL) in FileManager.default.fileExists(atPath: candidate.path) }
    return switch existingCandidates.count {
        case 0: .noCustomConfigExists
        case 1: .file(existingCandidates.first.orDie())
        default: .ambiguousConfigError(existingCandidates)
    }
}

enum ConfigFile {
    case file(URL), ambiguousConfigError(_ candidates: [URL]), noCustomConfigExists

    var urlOrNil: URL? {
        return switch self {
            case .file(let url): url
            case .ambiguousConfigError, .noCustomConfigExists: nil
        }
    }
}
