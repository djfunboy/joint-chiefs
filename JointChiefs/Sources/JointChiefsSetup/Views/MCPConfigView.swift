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
                cliStatusPanel
                configurationPanel
                verificationPanel
            }
        } footer: {
            Button("Next: How to Use") {
                model.currentSection = .usage
            }
            .buttonStyle(.agentPrimary)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - CLI install status

    @ViewBuilder
    private var cliStatusPanel: some View {
        switch model.cliInstallStatus {
        case .unknown, .installing:
            HStack(spacing: AgentSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("Installing `jointchiefs` CLI to \(model.installDestination.path)…")
                    .font(.agentSmall)
                    .foregroundStyle(Color.agentTextBody)
                Spacer(minLength: 0)
            }
            .agentPanel()

        case .installed(let dir):
            HStack(spacing: AgentSpacing.sm) {
                AgentPill(text: "CLI installed", kind: .success, icon: "checkmark.seal.fill")
                Text(dir.path)
                    .font(.agentXS)
                    .foregroundStyle(Color.agentTextMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .agentPanel(tint: Color.agentBgReady)

        case .failed(let reason):
            VStack(alignment: .leading, spacing: AgentSpacing.xs) {
                HStack(spacing: AgentSpacing.sm) {
                    AgentPill(text: "CLI install failed", kind: .warning, icon: "exclamationmark.triangle.fill")
                    Spacer()
                    Button("Choose location…") { chooseDestinationAndRetry() }
                        .buttonStyle(.agentSecondary(size: .small))
                }
                Text(reason)
                    .font(.agentXS)
                    .foregroundStyle(Color.agentTextBody)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Or install via Homebrew: `brew install --cask joint-chiefs` (auto-symlinks the CLI to /opt/homebrew/bin).")
                    .font(.agentXS)
                    .foregroundStyle(Color.agentTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .agentPanel()
        }
    }

    private func chooseDestinationAndRetry() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.installDestination
        panel.prompt = "Install Here"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await model.reinstallCLI(to: url) }
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
