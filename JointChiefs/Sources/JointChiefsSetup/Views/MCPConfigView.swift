import AppKit
import SwiftUI

struct MCPConfigView: View {

    @Environment(SetupModel.self) private var model
    @State private var copied = false

    var body: some View {
        SetupPage(
            title: "MCP Config Snippet",
            subtitle: "Paste this into your AI client's MCP configuration. No keys live in this snippet — Joint Chiefs resolves them from the Keychain at request time."
        ) {
            VStack(alignment: .leading, spacing: AgentSpacing.lg) {
                configurationPanel
                verificationPanel
                completionPanel
            }
        } footer: {
            Button("Close Setup") {
                NSApp.keyWindow?.performClose(nil)
            }
            .buttonStyle(.agentPrimary)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Closes the Joint Chiefs Setup window and quits the app")
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

    // MARK: - Completion

    private var completionPanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.sm) {
            HStack(spacing: AgentSpacing.sm) {
                AgentPill(text: "all set", kind: .success, icon: "checkmark.seal.fill")
                Spacer()
            }
            Text("You can run reviews from any terminal with `jointchiefs review <file>`, or from your AI client via the `joint_chiefs_review` tool. Close this window when you're ready — Joint Chiefs Setup is a one-shot installer and won't keep running in the background.")
                .font(.agentSmall)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .agentPanel(tint: Color.agentBgReady)
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
