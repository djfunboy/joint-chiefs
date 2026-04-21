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
                .frame(width: 200)
                .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

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
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
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
        VStack(alignment: .leading, spacing: 2) {
            Text("Joint Chiefs")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 10)

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

    var body: some View {
        Button {
            model.currentSection = section
        } label: {
            Label(section.rawValue, systemImage: section.systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(model.currentSection == section ? Color.accentColor.opacity(0.22) : .clear)
                )
                .foregroundStyle(model.currentSection == section ? Color.accentColor : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}
