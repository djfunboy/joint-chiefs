import JointChiefsCore
import SwiftUI

/// Sidebar + detail layout. Each detail view owns its own SetupPage scaffold,
/// which includes a scrollable body and a sticky footer, so the primary CTA
/// never falls below the fold regardless of window size.
///
/// Replaces the earlier NavigationSplitView — on macOS 26 its internal List
/// was rendering rows off-screen (confirmed in the a11y tree at y=-666).
struct RootView: View {

    @Environment(SetupModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: AgentLayout.sidebarWidth)
                .background(Color.agentBgPanel)

            Rectangle()
                .fill(Color.agentBorder)
                .frame(width: 1)
                .accessibilityHidden(true)

            Group {
                switch model.currentSection {
                case .disclosure: DisclosureView()
                case .keys: KeysView()
                case .rolesWeights: RolesWeightsView()
                case .mcp: MCPConfigView()
                case .usage: UsageView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.agentBgDeep)
        .task {
            // Probe the Keychain and copy CLI binaries into $PATH in parallel —
            // both are independent and we don't want either blocking the first
            // paint. Keychain probe may trigger a macOS access prompt; CLI
            // install is filesystem-only and quick.
            async let keys: () = model.refreshKeyStatuses()
            async let cli: () = model.installCLIIfNeeded()
            _ = await (keys, cli)
        }
    }
}

private struct Sidebar: View {

    @Environment(SetupModel.self) private var model
    @Environment(UpdaterService.self) private var updater

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.xxs) {
            Text("JOINT CHIEFS")
                .font(.agentPanelHeader)
                .agentUppercaseCaption()
                .foregroundStyle(Color.agentTextPrimary)
                .padding(.horizontal, AgentSpacing.md)
                .padding(.top, AgentSpacing.lg)
                .padding(.bottom, AgentSpacing.sm)

            ForEach(SetupModel.Section.allCases) { section in
                SidebarRow(section: section)
                    .environment(model)
            }

            Spacer(minLength: 0)

            UpdateStatusFooter()
                .environment(updater)
        }
    }
}

/// Pinned to the bottom of the sidebar. Shows the running app version and
/// either a "Check for updates" action or an "Update available → install"
/// action when Sparkle's scheduled check has discovered a newer release.
/// Tapping either path calls `updater.checkForUpdates()`, which presents
/// Sparkle's standard UI — "No new version available" or the install prompt.
private struct UpdateStatusFooter: View {

    @Environment(UpdaterService.self) private var updater

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.xs) {
            Rectangle()
                .fill(Color.agentBorder)
                .frame(height: 1)
                .accessibilityHidden(true)
                .padding(.horizontal, AgentSpacing.md)

            if let pendingVersion = updater.availableUpdateVersion {
                // Update discovered by a background check — highlight it.
                // `.info` (blue), not `.success` (green): per the design
                // system, green is reserved for validated/ready states.
                // An "update available" notification is informational.
                Button {
                    updater.checkForUpdates()
                } label: {
                    HStack(spacing: AgentSpacing.xs) {
                        AgentPill(text: "update available", kind: .info, icon: "arrow.up.circle.fill", compact: true)
                        Text("v\(pendingVersion)")
                            .font(.agentXS)
                            .foregroundStyle(Color.agentTextBody)
                        Spacer()
                    }
                    .padding(.horizontal, AgentSpacing.md)
                    .padding(.vertical, AgentSpacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Update available to version \(pendingVersion). Click to install.")
            } else {
                Button {
                    updater.checkForUpdates()
                } label: {
                    HStack(spacing: AgentSpacing.xs) {
                        if updater.isChecking {
                            ProgressView()
                                .controlSize(.mini)
                                .accessibilityHidden(true)
                            Text("Checking…")
                                .font(.agentXS)
                                .foregroundStyle(Color.agentTextBody)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.agentXS)
                                .foregroundStyle(Color.agentTextBody)
                            Text("Check for updates")
                                .font(.agentXS)
                                .foregroundStyle(Color.agentTextBody)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, AgentSpacing.md)
                    .padding(.vertical, AgentSpacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!updater.canCheckForUpdates || updater.isChecking)
                .accessibilityLabel(updater.isChecking ? "Checking for updates" : "Check for updates")
            }

            Text("v\(updater.currentVersion)")
                .font(.agentXS)
                .foregroundStyle(Color.agentTextMuted)
                .padding(.horizontal, AgentSpacing.md)
                .padding(.bottom, AgentSpacing.sm)
                .accessibilityLabel("Current version \(updater.currentVersion)")
        }
    }
}

private struct SidebarRow: View {

    let section: SetupModel.Section
    @Environment(SetupModel.self) private var model

    private var isSelected: Bool {
        model.currentSection == section
    }

    var body: some View {
        Button {
            model.currentSection = section
        } label: {
            Label(section.rawValue, systemImage: section.systemImage)
                .font(.agentBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AgentSpacing.md)
                .padding(.vertical, AgentSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AgentRadius.sm)
                        .fill(isSelected ? Color.agentBgRow : Color.clear)
                )
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(isSelected ? Color.agentTextPrimary : Color.clear)
                        .frame(width: 2)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(isSelected ? Color.agentTextPrimary : Color.agentTextBody)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AgentSpacing.xs)
    }
}
