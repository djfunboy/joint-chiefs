import JointChiefsCore
import SwiftUI

/// Manual sidebar + detail layout. Replaced the earlier `NavigationSplitView`
/// because on macOS 26 its internal List was rendering rows off-screen
/// (confirmed in the a11y tree at y=-666) — a bug we can't work around
/// without ditching the container entirely.
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

            ScrollView {
                Group {
                    switch model.currentSection {
                    case .disclosure: DisclosureView()
                    case .keys: KeysView()
                    case .rolesWeights: RolesWeightsView()
                    case .install: InstallView()
                    case .mcp: MCPConfigView()
                    }
                }
                .padding(AgentSpacing.xl2)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color.agentBgDeep)
        }
        .background(Color.agentBgDeep)
        .task {
            // Probe the Keychain after the window is visible. Keeps the first
            // paint fast even when the keygetter triggers a macOS access prompt.
            await model.refreshKeyStatuses()
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
                    RoundedRectangle(cornerRadius: AgentRadius.md)
                        .fill(isSelected ? Color.agentBgUncommitted : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: AgentRadius.md)
                                .stroke(isSelected ? Color.agentTextAccent : Color.clear, lineWidth: 1)
                        )
                )
                .foregroundStyle(isSelected ? Color.agentTextAccent : Color.agentTextBody)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AgentSpacing.xs)
    }
}
