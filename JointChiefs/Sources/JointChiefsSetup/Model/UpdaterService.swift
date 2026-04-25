import Foundation
import Sparkle

/// Observable wrapper around `SPUStandardUpdaterController`. Matches the rest of
/// the setup app's @Observable pattern so views can bind to `canCheckForUpdates`
/// and call `checkForUpdates()` without touching Sparkle's Combine / KVO surface
/// directly.
///
/// SUFeedURL + SUPublicEDKey are declared in Info.plist; Sparkle reads them at
/// bundle-load time. This wrapper intentionally holds no configuration of its
/// own — updater config belongs in the bundle, not in code.
///
/// Sparkle requires its framework + XPC services (`Downloader.xpc`,
/// `Installer.xpc`) to live inside the bundle's `Contents/Frameworks/`.
/// Running via `swift run` produces a raw executable with no bundle
/// structure — in that case we skip init entirely so the dev workflow
/// doesn't get interrupted by Sparkle's "updater failed to start" modal.
@Observable
@MainActor
final class UpdaterService {

    /// True when Sparkle is ready to run a new check (not already checking, not
    /// installing). Always `false` when running outside an app bundle.
    var canCheckForUpdates: Bool = false

    /// True between a user-triggered `checkForUpdates()` call and Sparkle
    /// reporting back (via the `canCheckForUpdates` KVO transition to `true`).
    /// Drives the inline spinner in the sidebar footer so a slow network check
    /// doesn't look like a dead button.
    var isChecking: Bool = false

    /// The version string of an update Sparkle's background check has
    /// discovered but the user hasn't installed yet. `nil` when nothing's
    /// pending. Drives the "update available" badge in the sidebar footer.
    /// Cleared on every `checkForUpdates()` call so a dismissed install modal
    /// doesn't leave the badge stuck — Sparkle re-fires `didFindValidUpdate`
    /// on the next discovery if the update is still pending.
    var availableUpdateVersion: String? = nil

    /// The currently running app version (CFBundleShortVersionString), or
    /// `"dev"` when running outside a bundle. Shown in the sidebar footer.
    let currentVersion: String

    private let controller: SPUStandardUpdaterController?
    private let delegate: UpdaterDelegate?
    private var observation: NSKeyValueObservation?

    init() {
        self.currentVersion = Self.readBundleVersion()
        guard Self.isRunningFromAppBundle else {
            self.controller = nil
            self.delegate = nil
            return
        }
        let delegate = UpdaterDelegate()
        let c = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        self.controller = c
        self.delegate = delegate
        self.canCheckForUpdates = c.updater.canCheckForUpdates
        // Capture the update version whenever Sparkle discovers one — via
        // scheduled background check OR the user's manual `checkForUpdates`
        // call. The sidebar footer then renders the "update available" badge
        // until the install modal is acted on. Resets to nil aren't wired —
        // the modal is the resolution path, and the next check refreshes state.
        delegate.onUpdateFound = { [weak self] version in
            Task { @MainActor [weak self] in
                self?.availableUpdateVersion = version
            }
        }
        self.observation = c.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.canCheckForUpdates = updater.canCheckForUpdates
                if updater.canCheckForUpdates, self.isChecking {
                    self.isChecking = false
                }
            }
        }
    }

    /// User-triggered update check. Presents Sparkle's standard UI on any
    /// outcome — found, not found, error. No-op in dev (no controller).
    /// Clears any stale "update available" state so a dismissed install modal
    /// doesn't leave the footer stuck on the previous version.
    func checkForUpdates() {
        guard let controller else { return }
        availableUpdateVersion = nil
        isChecking = true
        controller.checkForUpdates(nil)
    }

    /// Dev builds run under `swift run` — the executable sits directly in
    /// `.build/<config>/` with no surrounding `.app`. Release builds live at
    /// `Joint Chiefs.app/Contents/MacOS/jointchiefs-setup`, and
    /// `Bundle.main.bundlePath` points at the `.app`.
    private static var isRunningFromAppBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    private static func readBundleVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
}

/// Bridges Sparkle's Objective-C delegate callback into our @Observable model.
/// Held strongly by `UpdaterService` so the controller's weak delegate
/// reference stays alive for the lifetime of the app.
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var onUpdateFound: ((String) -> Void)?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onUpdateFound?(item.displayVersionString)
    }
}
