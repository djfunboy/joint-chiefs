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

    private let controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    init() {
        guard Self.isRunningFromAppBundle else {
            self.controller = nil
            return
        }
        let c = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = c
        self.canCheckForUpdates = c.updater.canCheckForUpdates
        self.observation = c.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    /// User-triggered update check. Presents Sparkle's standard UI on any
    /// outcome — found, not found, error. No-op in dev (no controller).
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Dev builds run under `swift run` — the executable sits directly in
    /// `.build/<config>/` with no surrounding `.app`. Release builds live at
    /// `Joint Chiefs.app/Contents/MacOS/jointchiefs-setup`, and
    /// `Bundle.main.bundlePath` points at the `.app`.
    private static var isRunningFromAppBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }
}
