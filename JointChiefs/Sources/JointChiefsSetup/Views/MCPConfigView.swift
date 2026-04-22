import AppKit
import SwiftUI

struct MCPConfigView: View {

    @Environment(SetupModel.self) private var model
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.lg) {
            Text("MCP Config Snippet")
                .font(.agentDialogTitle)
                .foregroundStyle(Color.agentTextPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("Paste this into your AI client's MCP configuration. No keys live in this snippet — Joint Chiefs resolves them from the Keychain at request time.")
                .font(.agentDialogSubtitle)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)

            configurationPanel
            verificationPanel

            HStack {
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .buttonStyle(.agentPrimary)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, AgentSpacing.md)
        }
    }

    // MARK: - Configuration panel

    private var configurationPanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.sm) {
            AgentSectionHeader(text: "MCP client configuration")

            codeBlock

            HStack(spacing: AgentSpacing.sm) {
                Text("Destination binary:")
                    .font(.agentXS)
                    .foregroundStyle(Color.agentTextMuted)
                Text(mcpBinaryPath)
                    .font(.agentXS)
                    .foregroundStyle(Color.agentTextBody)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
        }
        .agentPanel()
    }

    private var codeBlock: some View {
        ScrollView {
            Text(snippet)
                .font(.agentSmall)
                .foregroundStyle(Color.agentTextPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AgentSpacing.md)
        }
        .frame(maxHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: AgentRadius.md)
                .fill(Color.agentBgCode)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AgentRadius.md)
                .strokeBorder(Color.agentBorder, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button(copied ? "Copied" : "Copy") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(snippet, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copied = false
                }
            }
            .buttonStyle(.agentGhost)
            .padding(AgentSpacing.xs)
            .accessibilityLabel(copied ? "MCP configuration copied" : "Copy MCP configuration")
            .accessibilityHint("Copies the JSON snippet to the clipboard")
        }
    }

    // MARK: - Verification panel

    private var verificationPanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.xs) {
            AgentSectionHeader(text: "Verification")
            Text("Once wired up, ask your AI: *\"Run a Joint Chiefs review on this file.\"* — the model should invoke `joint_chiefs_review` and stream the consensus back.")
                .font(.agentSmall)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .agentPanel()
    }

    private var mcpBinaryPath: String {
        model.installDestination.appendingPathComponent("jointchiefs-mcp").path
    }

    private var snippet: String {
        """
        {
          "mcpServers": {
            "joint-chiefs": {
              "command": "\(mcpBinaryPath)"
            }
          }
        }
        """
    }
}
