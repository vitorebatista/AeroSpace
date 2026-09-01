import Common
import Foundation
import OrderedCollections
import SwiftUI

enum BarSettingsMode: Equatable {
    /// The file parsed; the form is available.
    case form
    /// The file did not parse, so there is no draft to bind a form to. Saving is refused —
    /// writing a default draft over a file we could not read would destroy it.
    case unreadable(message: String)
}

enum BarSettingsStatus: Equatable {
    case error(String)
    case saved(String)
}

/// The backend a page falls back to when no renderer is wired in. It never claims to be
/// available, so the page still edits and saves and says plainly that nothing will render.
struct UnavailableBarBackend: BarBackend {
    var isAvailable: Bool { false }

    func apply(_ draft: BarDraft) throws -> BarApplyOutcome {
        throw BarSettingsError("No bar backend is available.")
    }
}

struct BarSettingsError: Error, LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// `~/.config/aerospace/bar.toml`, loaded as a `BarDraft`, edited by the Sketchybar
/// destination, and written back through the same seams `SettingsModel` uses: an injected
/// atomic writer and an injected reader, so a save is testable without touching a disk, and
/// an injected `BarBackend`, so it is testable without a sketchybar.
@MainActor
public final class BarSettingsModel: ObservableObject {
    // `public` for the same reason `SettingsModel.shared` is: the settings scene lives in a
    // separate SPM target and holds this as a `@StateObject`.
    //
    // This is the one place a real renderer is wired in: pass it as `backend:` here and the
    // page, the status readout and Save all follow, because nothing above the protocol knows
    // sketchybar exists.
    public static let shared = BarSettingsModel()

    @Published var draft = BarDraft()
    @Published private(set) var mode: BarSettingsMode = .form
    @Published var isDirty = false
    /// `true` while `save()` is in flight. The save suspends across the backend's apply with
    /// the window still interactive, so the page freezes its bindings for the duration.
    @Published private(set) var isSaving = false
    @Published var status: BarSettingsStatus?
    /// The user's own `sketchybarrc` was moved aside and this path is the only way back to
    /// it, so it outlives the status line and every later edit. Cleared only by
    /// `dismissTakeoverNotice()`.
    @Published private(set) var takeoverBackupUrl: URL?
    /// `true` when `bar.toml` does not exist yet, so saving creates it.
    @Published private(set) var willCreateConfig = false
    /// Bumped on every `load()`, so a view holding its own memory of the document — which
    /// rows are expanded — can tell a Revert from its own edits. Same signal, and the same
    /// reason, as `SettingsModel.loadGeneration`.
    @Published private(set) var loadGeneration = 0

    let configUrl: URL
    private let backend: any BarBackend
    private let fileManager: FileManager
    private let textReader: (URL) -> String?
    private let atomicWriter: (Data, URL, Int?) throws -> Void
    private let directoryCreator: (URL) throws -> Void
    private var document = BarTomlDocument("")
    /// `draft` as `load()` read it. `apply` compares against it so a region the user never
    /// went near is left byte-for-byte alone.
    private var loadedDraft = BarDraft()

    init(
        configUrl: URL = BarSettingsModel.defaultConfigUrl,
        backend: any BarBackend = UnavailableBarBackend(),
        fileManager: FileManager = .default,
        textReader: @escaping (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) },
        atomicWriter: ((Data, URL, Int?) throws -> Void)? = nil,
        directoryCreator: ((URL) throws -> Void)? = nil,
    ) {
        self.configUrl = configUrl
        self.backend = backend
        self.fileManager = fileManager
        self.textReader = textReader
        self.atomicWriter = atomicWriter ?? {
            try SettingsModel.writeCandidateAtomically($0, to: $1, permissions: $2, fileManager: fileManager)
        }
        self.directoryCreator = directoryCreator ?? {
            try fileManager.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }

    /// The bar description is a config file, not an app preference: like `~/.aerospace.toml`
    /// it travels between machines and is meaningful on any of them. `XDG_CONFIG_HOME` is
    /// honoured for the same reason the main config lookup honours it.
    static var defaultConfigUrl: URL {
        let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/")
        return xdgConfigHome.appending(path: "aerospace").appending(path: "bar.toml")
    }

    var isBackendAvailable: Bool { backend.isAvailable }

    /// Writes land on the resolved path: `replaceItemAt` swaps a fresh file over the target,
    /// which would detach a `bar.toml` symlinked into a dotfiles repo instead of writing
    /// through it. Same reason as `SettingsModel.writeUrl`.
    private var writeUrl: URL { configUrl.resolvingSymlinksInPath() }

    func markEdited() {
        guard !isSaving else { return }
        isDirty = true
        status = nil
    }

    func dismissTakeoverNotice() { takeoverBackupUrl = nil }

    func load() {
        status = nil
        isDirty = false
        loadGeneration += 1

        let text = textReader(configUrl)
        willCreateConfig = text == nil
        document = BarTomlDocument(text ?? "")
        switch document.draft() {
            case .success(let loaded):
                draft = loaded
                loadedDraft = loaded
                mode = .form
            case .failure(let error):
                // Keep the last good draft rather than showing defaults that were never in
                // the file: the page refuses to save in this mode, and defaults on screen
                // would read as "this is what you have".
                mode = .unreadable(message: error.description)
        }
    }

    func revert() { load() }

    /// Writes `bar.toml`, then hands the draft to the backend, which generates the renderer's
    /// own config and reloads it.
    ///
    /// A backend failure is reported but does not roll the file back: what is on disk is
    /// correct and the user can reload by hand. A write failure stops before the backend, so
    /// the bar is never reloaded from a draft that was not saved.
    func save() async {
        guard !isSaving, mode == .form else { return }
        isSaving = true
        defer { isSaving = false }
        status = nil

        var working = document
        // A file that does not exist yet has no region to preserve, and a surgical apply
        // would write only the keys the user happened to touch — leaving a bar.toml with no
        // [bar] table at all, silently running on defaults nobody chose.
        working.apply(draft, original: willCreateConfig ? Self.fullEmissionBaseline : loadedDraft)
        let text = working.render()

        do {
            try directoryCreator(writeUrl.deletingLastPathComponent())
        } catch {
            status = .error("Can't create \(writeUrl.deletingLastPathComponent().path): \(error.localizedDescription)")
            return
        }
        do {
            try atomicWriter(Data(text.utf8), writeUrl, permissionsOfExistingFile())
        } catch {
            status = .error("Can't write \(configUrl.path): \(error.localizedDescription)")
            return
        }

        load() // re-read from disk so the form and the document match the file exactly
        status = await applyToBackend(reloadOnly: false)
    }

    /// Regenerates the renderer's config from the last saved `bar.toml` and reloads it. The
    /// manual counterpart to Save, for a bar that was stopped, restarted, or reconfigured by
    /// something else.
    func reloadBar() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        status = await applyToBackend(reloadOnly: true)
    }

    private func applyToBackend(reloadOnly: Bool) async -> BarSettingsStatus {
        let saved = reloadOnly ? "" : "Saved \(configUrl.lastPathComponent). "
        guard backend.isAvailable else {
            return .saved(saved + "sketchybar isn't installed, so nothing renders yet.")
        }
        let backend = self.backend
        let draft = loadedDraft
        do {
            // `apply` generates a file and runs sketchybar, so it is kept off the MainActor:
            // the window stays live while it runs, which is what `isSaving` guards.
            let outcome = try await Task.detached { try backend.apply(draft) }.value
            if case .replacedUserConfig(let backup) = outcome { takeoverBackupUrl = backup }
            return .saved(saved + Self.message(for: outcome))
        } catch {
            return .error(saved + "sketchybar could not be updated: \(error.localizedDescription)")
        }
    }

    private static func message(for outcome: BarApplyOutcome) -> String {
        switch outcome {
            case .created: "sketchybar's config was created and reloaded."
            case .updated: "sketchybar reloaded."
            case .replacedUserConfig: "Your own sketchybar config was moved aside and sketchybar reloaded."
        }
    }

    private func permissionsOfExistingFile() -> Int? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: writeUrl.path) else { return nil }
        return (attributes[.posixPermissions] as? NSNumber)?.intValue
    }

    /// The baseline that makes every modelled key differ, and so be emitted. Written out
    /// rather than derived because the key lists belong to `BarTomlDocument`; `Int.min` and
    /// the empty string are values no real bar has.
    private static var fullEmissionBaseline: BarDraft {
        var baseline = BarDraft()
        baseline.version = .min
        baseline.geometry = BarGeometry(
            height: .min,
            margin: .min,
            yOffset: .min,
            cornerRadius: .min,
            borderWidth: .min,
            paddingLeft: .min,
            paddingRight: .min,
        )
        baseline.colors = BarColors(
            background: "",
            border: "",
            label: "",
            icon: "",
            accent: "",
            popupBackground: "",
            popupBorder: "",
        )
        return baseline
    }
}

/// A `[item.settings]` key the catalog does not declare, as the page lists it.
struct BarUnrecognisedSetting: Equatable, Identifiable, Sendable {
    let key: String
    let value: BarSettingValue

    var id: String { key }
}

// MARK: - Ordered item edits

/// The list edits the Items section performs. They live here, apart from the view, because
/// each one is a translation between a cluster's visible order and the single document-order
/// array that actually holds it — the part worth testing.
extension BarDraft {
    /// Positions in `items` of one cluster's entries, in document order. That order is the
    /// order they are drawn in, so it is also the order the list shows.
    func positions(in cluster: BarCluster) -> [Int] {
        items.indices.filter { items[$0].cluster == cluster }
    }

    /// Reorders one cluster, leaving every other cluster's entry exactly where it was in the
    /// document. Offsets are into the cluster's own list, as SwiftUI's `onMove` reports them.
    mutating func move(in cluster: BarCluster, fromOffsets: IndexSet, toOffset: Int) {
        let positions = positions(in: cluster)
        var moved = positions.map { items[$0] }
        moved.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (position, item) in zip(positions, moved) { items[position] = item }
    }

    /// Appends an instance of a catalog entry to the end of a cluster, seeded with the
    /// catalog's defaults so the file states what is in effect instead of leaving it implied.
    mutating func add(_ catalogItem: BarCatalogItem, to cluster: BarCluster) {
        let item = BarItem(
            id: catalogItem.id,
            cluster: cluster,
            settings: OrderedDictionary(uniqueKeysWithValues: catalogItem.settings.map { ($0.key, $0.defaultValue) }),
        )
        items.insert(item, at: positions(in: cluster).last.map { $0 + 1 } ?? items.count)
    }

    mutating func remove(in cluster: BarCluster, atOffsets offsets: IndexSet) {
        let positions = positions(in: cluster)
        for position in offsets.compactMap({ positions.getOrNil(atIndex: $0) }).sorted(by: >) {
            items.remove(at: position)
        }
    }

    /// The value an item's settings row shows: what the file holds, or the catalog's default
    /// when the file is silent about the key.
    func settingValue(at index: Int, _ key: BarSettingKey) -> BarSettingValue {
        items.getOrNil(atIndex: index)?.settings[key.key] ?? key.defaultValue
    }

    mutating func setSettingValue(at index: Int, _ key: String, _ value: BarSettingValue) {
        guard items.indices.contains(index) else { return }
        items[index].settings[key] = value
    }

    /// `[item.settings]` keys the catalog does not declare. They are preserved on save — they
    /// round-trip through `BarItem.settings` — and the page reports them rather than pretending
    /// they are not there.
    func unrecognisedSettings(at index: Int) -> [BarUnrecognisedSetting] {
        guard let item = items.getOrNil(atIndex: index) else { return [] }
        let known = Set(BarCatalog.item(id: item.id)?.settings.map(\.key) ?? [])
        return item.settings.filter { !known.contains($0.key) }.map { BarUnrecognisedSetting(key: $0.key, value: $0.value) }
    }
}
