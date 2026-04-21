import AppKit
import JointChiefsCore
import SwiftUI

/// One-shot setup app for Joint Chiefs. Opens a single window where users add API
/// keys (written to the Keychain via the keygetter), assign moderator/tiebreaker
/// roles and per-provider voting weights, pick an install location for the CLI +
/// MCP binaries, and copy an MCP config snippet for their AI client.
///
/// Distribution target: wrapped in `Joint Chiefs.app` with the other executables
/// in `Contents/Resources/`. Running directly from `swift run jointchiefs-setup`
/// works for development — the activation-policy bump below makes the window
/// surface as a regular foreground app even without a bundle.
@main
struct SetupApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = SetupModel()

    var body: some Scene {
        Window("Joint Chiefs Setup", id: "setup") {
            RootView()
                .environment(model)
                .frame(minWidth: 880, minHeight: 720)
        }
        // Open wide enough to fit the Roles & Weights section without scroll
        // or sidebar truncation. `.contentMinSize` respects the declared
        // minimums without forcing the window to size to content (which
        // interacts badly with `Spacer()`-driven layouts).
        .defaultSize(width: 980, height: 780)
        .windowResizability(.contentMinSize)
    }
}

/// AppKit delegate that promotes the SPM-built binary to a regular foreground
/// application and activates the window — necessary because SPM executables
/// don't carry an Info.plist that declares `LSUIElement` / activation policy.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
