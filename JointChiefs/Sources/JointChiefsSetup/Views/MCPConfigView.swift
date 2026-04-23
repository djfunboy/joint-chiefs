import AppKit
import SwiftUI

struct MCPConfigView: View {

    @Environment(SetupModel.self) private var model
    @State private var copiedPrompt = false
    @State private var copiedJSON = false

    var body: some View {
        SetupPage(
            title: "Connect to Your AI Assistant",
            subtitle: "Two ways to wire up Joint Chiefs. The easy path: paste a prompt — your AI handles the config file for you."
        ) {
            VStack(alignment: .leading, spacing: AgentSpacing.lg) {
                cliStatusPanel
                aiPromptPanel
                jsonConfigPanel
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
                Text("Installing Joint Chiefs CLI to \(model.installDestination.path)…")
                    .font(.agentSmall)
                    .foregroundStyle(Color.agentTextBody)
                Spacer(minLength: 0)
            }
            .agentPanel()

        case .installed(let dir):
            HStack(spacing: AgentSpacing.sm) {
                AgentPill(text: "Ready to connect", kind: .success, icon: "checkmark.seal.fill")
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
                    AgentPill(text: "Install failed", kind: .warning, icon: "exclamationmark.triangle.fill")
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

    // MARK: - AI prompt (primary path)

    private var aiPromptPanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.sm) {
            HStack {
                AgentSectionHeader(text: "Easy: ask your AI to wire it up")
                Spacer()
                Button(copiedPrompt ? "Copied" : "Copy") {
                    copyToPasteboard(aiPrompt)
                    copiedPrompt = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedPrompt = false }
                }
                .buttonStyle(.agentGhost)
                .accessibilityLabel(copiedPrompt ? "Copied" : "Copy prompt")
            }

            Text("Paste this into your AI coding assistant. It'll find your MCP config file, add Joint Chiefs, and tell you if you need to restart.")
                .font(.agentSmall)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)

            codeFrame(text: aiPrompt)
        }
        .agentPanel()
    }

    // MARK: - JSON config (fallback path)

    private var jsonConfigPanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.sm) {
            HStack {
                AgentSectionHeader(text: "Or: edit the config yourself")
                Spacer()
                Button(copiedJSON ? "Copied" : "Copy") {
                    copyToPasteboard(jsonSnippet)
                    copiedJSON = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedJSON = false }
                }
                .buttonStyle(.agentGhost)
                .accessibilityLabel(copiedJSON ? "Copied" : "Copy JSON config")
            }

            Text("If you'd rather edit the config file directly, here's the JSON block to add under `mcpServers`. No API keys in here — Joint Chiefs pulls them from the Keychain at request time.")
                .font(.agentSmall)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)

            codeFrame(text: jsonSnippet)
        }
        .agentPanel()
    }

    // MARK: - Verification

    private var verificationPanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.xs) {
            AgentSectionHeader(text: "How to check it worked")
            Text("Restart your AI coding assistant, then say: \"Have Joint Chiefs review this file.\" If the consensus comes back, you're wired up.")
                .font(.agentSmall)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .agentPanel()
    }

    // MARK: - Shared code frame

    private func codeFrame(text: String) -> some View {
        ScrollView {
            Text(text)
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
    }

    private func copyToPasteboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    // MARK: - Content

    private var mcpBinaryPath: String {
        model.installDestination.appendingPathComponent("jointchiefs-mcp").path
    }

    /// Natural-language prompt a user can paste into any AI coding assistant.
    /// Leans on the assistant's ability to find config files and edit JSON —
    /// which is exactly the kind of work these tools are good at. Avoids
    /// naming specific clients (per the "any MCP client" rule) and skips
    /// listing config-file paths since they differ per client.
    private var aiPrompt: String {
        """
        Please add the Joint Chiefs MCP server to your config. The command is:

        \(mcpBinaryPath)

        Find your MCP config file (it's a JSON file on my machine — the location depends on which client you are), add a new entry under "mcpServers" named "joint-chiefs" with that command, then tell me if I need to restart anything for it to take effect.
        """
    }

    private var jsonSnippet: String {
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
