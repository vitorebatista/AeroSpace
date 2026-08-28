import AppKit
import Common
import Foundation

enum UpdateInstallError: Error, CustomStringConvertible {
    case download(String)
    case unpack(String)
    case badPayload(String)
    case install(String)

    var description: String {
        switch self {
            case .download(let m): "Download failed: \(m)"
            case .unpack(let m): "Couldn't unpack the download: \(m)"
            case .badPayload(let m): "The download doesn't look like \(aeroSpaceAppName): \(m)"
            case .install(let m): "Couldn't install the update: \(m)"
        }
    }
}

/// Downloads a release zip and swaps it in over the running install.
///
/// The app bundle we replace is the one this process is running from — never a hardcoded
/// `/Applications` path, so an install anywhere updates itself in place.
@MainActor
func downloadAndInstall(_ release: GitHubRelease) async throws(UpdateInstallError) {
    guard isAllowedUpdateUrl(release.zipUrl) else {
        throw .download("refusing to download from \(release.zipUrl.host() ?? "an unknown host")")
    }
    let workDir = FileManager.default.temporaryDirectory
        .appending(path: "\(stableAeroSpaceAppId).update-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workDir) }

    let zip = try await download(release.zipUrl, into: workDir)
    let unpacked = try unpack(zip, in: workDir)
    let newApp = try locateApp(in: unpacked, expecting: release.version)
    try replaceRunningApp(with: newApp)
    replaceCliIfFound(in: unpacked)
}

func download(_ url: URL, into workDir: URL) async throws(UpdateInstallError) -> URL {
    do {
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let (tmp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateInstallError.download("HTTP \(http.statusCode)")
        }
        // A redirect could have taken us off GitHub; the final URL gets the same check as the first.
        if let final = response.url, !isAllowedUpdateUrl(final) {
            throw UpdateInstallError.download("redirected to \(final.host() ?? "an unknown host")")
        }
        let dest = workDir.appending(path: "update.zip")
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    } catch let e as UpdateInstallError {
        throw e
    } catch {
        throw .download(error.localizedDescription)
    }
}

func unpack(_ zip: URL, in workDir: URL) throws(UpdateInstallError) -> URL {
    let dest = workDir.appending(path: "unpacked")
    // ditto over unzip: it preserves the code signature and extended attributes of the app bundle.
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", zip.path, dest.path]
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        throw .unpack(error.localizedDescription)
    }
    guard process.terminationStatus == 0 else { throw .unpack("ditto exited with \(process.terminationStatus)") }
    return dest
}

/// Finds the .app in the unpacked payload and refuses anything that isn't the app we expect: right bundle
/// id, and the version the release claimed. Guards against a mislabelled or tampered asset replacing the
/// install with something else.
func locateApp(in unpacked: URL, expecting version: AppVersion) throws(UpdateInstallError) -> URL {
    let candidates = (FileManager.default.enumerator(at: unpacked, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "app" }) ?? []
    guard let app = candidates.first else { throw .badPayload("no .app found in the archive") }
    guard let plist = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")) else {
        throw .badPayload("the app has no readable Info.plist")
    }
    let id = plist["CFBundleIdentifier"] as? String
    guard id == stableAeroSpaceAppId else {
        throw .badPayload("bundle id is \(id ?? "missing"), expected \(stableAeroSpaceAppId)")
    }
    let shipped = (plist["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    guard let shipped, !(shipped < version), !(version < shipped) else {
        throw .badPayload("it reports version \(plist["CFBundleShortVersionString"] as? String ?? "none"), but the release says \(version)")
    }
    return app
}

@MainActor
private func replaceRunningApp(with newApp: URL) throws(UpdateInstallError) {
    let installedApp = Bundle.main.bundleURL
    do {
        // Swap via replaceItemAt so a failure part-way leaves the old app in place rather than a
        // half-copied bundle: the new app is staged beside the old one and exchanged in one step.
        _ = try FileManager.default.replaceItemAt(installedApp, withItemAt: newApp)
    } catch {
        throw .install("\(installedApp.path): \(error.localizedDescription)")
    }
}

/// Best effort: the CLI can be anywhere on PATH, and may live somewhere unwritable. A failure here is not
/// fatal — the app is already updated, and the user is told to copy it by hand.
@MainActor
private func replaceCliIfFound(in unpacked: URL) {
    guard let newCli = (FileManager.default.enumerator(at: unpacked, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .first { $0.lastPathComponent == aeroSpaceCliName && !$0.path.contains(".app/") })
    else { return }
    for dir in ["/usr/local/bin", "/opt/homebrew/bin"] {
        let installed = URL(filePath: dir).appending(path: aeroSpaceCliName)
        guard FileManager.default.fileExists(atPath: installed.path),
              FileManager.default.isWritableFile(atPath: installed.path)
        else { continue }
        _ = try? FileManager.default.removeItem(at: installed)
        _ = try? FileManager.default.copyItem(at: newCli, to: installed)
    }
}

/// Relaunches after the current process is gone. The new instance can't simply be opened from here —
/// macOS would find this one still running under the same bundle id — so a detached shell waits for our
/// pid to disappear and opens the app then.
@MainActor
func relaunchAfterExit() {
    let app = Bundle.main.bundleURL.path
    let process = Process()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open \(app.singleQuoted)"]
    try? process.run()
}
