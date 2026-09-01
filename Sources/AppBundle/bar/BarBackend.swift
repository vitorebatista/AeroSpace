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
}
