import Foundation

/// What applying a draft did to the file the backend owns. The Settings page reports this,
/// and `replacedUserConfig` is the one the user has to be told about: their hand-written
/// config was moved aside, and they need the path to get it back.
enum BarApplyOutcome: Equatable, Sendable {
    case created
    case updated
    case replacedUserConfig(backup: URL)
}

/// How a `BarDraft` becomes a bar on screen.
///
/// Everything above this protocol — the model, the catalog, the Settings page, the docs —
/// is independent of the renderer. `SketchybarBackend` generates a config and reloads
/// sketchybar; a native renderer would be a second conformance and nothing above would
/// move. See "The backend boundary" in the design spec for the evidence that would justify
/// writing one.
protocol BarBackend: Sendable {
    /// Whether this backend can render at all — for sketchybar, whether it is installed.
    /// A page bound to an unavailable backend still edits and saves; it just says nothing
    /// will render yet.
    var isAvailable: Bool { get }

    func apply(_ draft: BarDraft) throws -> BarApplyOutcome

    /// Move the bar on screen from `previous` to `next` WITHOUT touching any file.
    ///
    /// This is the preview. Rather than the page rendering a mock of the bar, the running
    /// bar is edited in place as the user drags, so fidelity comes free from the renderer
    /// that is already drawing — there is no second implementation of padding and font
    /// metrics to drift out of sync.
    ///
    /// The caller supplies both sides instead of the backend remembering the last one, so a
    /// backend stays stateless and `Sendable`. `previous` must be what is currently ON
    /// SCREEN, not what is on disk: emitting a diff from the wrong baseline would re-add
    /// items that already exist.
    func applyLive(from previous: BarDraft, to next: BarDraft) throws

    /// Throw away everything `applyLive` did and put back what is on disk.
    ///
    /// Live editing never writes, so the file is still the last saved state and re-reading
    /// it *is* the restore. Called on Revert, on Cancel, and when the window closes with
    /// unsaved edits.
    func discardLiveChanges() throws
}

/// The backend a page falls back to when no renderer is wired in. It never claims to be
/// available, so the page still edits and saves and says plainly that nothing will render.
///
/// Its live methods do nothing rather than throw: there is no bar on screen to move or to
/// put back, so there is no failure to report either.
struct UnavailableBarBackend: BarBackend {
    var isAvailable: Bool { false }

    func apply(_ draft: BarDraft) throws -> BarApplyOutcome {
        throw BarSettingsError("No bar backend is available.")
    }

    func applyLive(from previous: BarDraft, to next: BarDraft) throws {}

    func discardLiveChanges() throws {}
}
