import AppKit

/// How long a single Accessibility request to another app may block before it's abandoned.
/// See the call site in `MacApp` for why this exists.
let axMessagingTimeoutSeconds: Float = 1.5

/// Brings `nsApp` to the front.
///
/// `activate(options: .activateIgnoringOtherApps)` is the macOS 13 spelling. macOS 14 deprecated it
/// and, more importantly, made it unreliable: the window server increasingly ignores unilateral
/// "ignore other apps" activation, which is the root of the "focus command did nothing" reports.
/// The replacement models activation as a *transfer* — the app currently holding focus (us, since a
/// hotkey or a CLI call got us here) yields it to the target — and the window server honours that.
///
/// Falls back to the old call when the new one declines, so behaviour on macOS 13 is unchanged.
func nativeActivate(_ nsApp: NSRunningApplication) {
    if #available(macOS 14, *) {
        if nsApp.activate(from: .current) { return }
    }
    nsApp.activate(options: .activateIgnoringOtherApps)
}
