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
                troubleshootingFooter
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

    // MARK: - Troubleshooting

    private var troubleshootingFooter: some View {
        HStack {
            Spacer()
            Link(destination: URL(string: "https://jointchiefs.ai/setup-guide.md")!) {
                Text("Didn't work? See setup guide →")
                    .font(.agentXS)
                    .foregroundStyle(Color.agentTextAccent)
                    .underline()
            }
            .accessibilityLabel("Open troubleshooting page")
            Spacer()
        }
        .padding(.top, AgentSpacing.xs)
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
        Please wire up the Joint Chiefs MCP server so I can use it from this session, then run a quick test to confirm it's actually working. Don't stop at "I added the entry" — go all the way to a working tool call.

        The command path is:

        \(mcpBinaryPath)

        Do this:

        1. Find your own MCP config file. The JSON path depends on which AI assistant you are — figure out your own path; don't ask me.
        2. Add a new entry under "mcpServers" named "joint-chiefs" pointing at that command. No API keys go in here — Joint Chiefs reads them from the macOS Keychain at request time.
        3. Show me the exact entry you wrote so I can verify it landed.
        4. Tell me whether anything (you, the host app, etc.) needs to restart for the new server to load. If it does, walk me through the restart.
        5. After the restart, confirm you can see the `joint_chiefs_review` tool in your tool list. Then call it on a tiny snippet (5–10 lines of any code is fine) and show me the consensus output as proof it's wired end-to-end.

        End the conversation by either confirming "Joint Chiefs is wired up and working" with the test output, or telling me the specific blocker you hit. Do not leave me guessing whether it worked.

        If you get stuck at any step — config file you can't locate, server not appearing after restart, the test tool call returning an error — fetch https://jointchiefs.ai/setup-guide.md and follow the troubleshooting steps there before giving up.
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
