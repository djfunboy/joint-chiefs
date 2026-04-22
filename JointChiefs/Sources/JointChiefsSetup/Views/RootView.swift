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
