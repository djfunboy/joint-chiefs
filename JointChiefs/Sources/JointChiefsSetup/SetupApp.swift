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
    @State private var updater = UpdaterService()

    var body: some Scene {
        Window("Joint Chiefs Setup", id: "setup") {
            RootView()
                .environment(model)
                .environment(updater)
                .frame(minWidth: 880, minHeight: 720)
                // Agentdeck is a warm-charcoal dark-only palette. If the user's
                // system is set to light, the native chrome (menu popovers,
                // toggles, sliders, checkboxes) would fight our dark panels
                // and some text would render unreadable. Forcing dark keeps
                // the whole window consistent regardless of system setting.
                .preferredColorScheme(.dark)
        }
        // Open wide enough to fit the Roles & Weights section without scroll
        // or sidebar truncation. `.contentMinSize` respects the declared
        // minimums without forcing the window to size to content (which
        // interacts badly with `Spacer()`-driven layouts).
        .defaultSize(width: 980, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
                .keyboardShortcut("u", modifiers: [.command])
            }
        }
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
