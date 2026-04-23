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
@Observable
@MainActor
final class UpdaterService {

    /// True when Sparkle is ready to run a new check (not already checking, not
    /// installing). Bind to this from the menu item to disable the button while
    /// a check is in flight.
    var canCheckForUpdates: Bool = false

    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.canCheckForUpdates = controller.updater.canCheckForUpdates
        self.observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    /// User-triggered update check. Presents Sparkle's standard UI on any
    /// outcome — found, not found, error.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
