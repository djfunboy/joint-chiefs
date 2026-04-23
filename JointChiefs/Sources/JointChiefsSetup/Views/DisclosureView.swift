import SwiftUI

struct DisclosureView: View {

    @Environment(SetupModel.self) private var model

    var body: some View {
        SetupPage(
            title: "Privacy",
            subtitle: "Joint Chiefs is MIT-licensed and open source. It sends code you explicitly submit to the LLM providers you configure — nothing is sent until you run a review."
        ) {
            VStack(alignment: .leading, spacing: AgentSpacing.lg) {
                disclosureRow(
                    title: "What's sent off-device",
                    body: "When you run a review, the code file (or pasted content) is sent to each configured provider. The moderator also sees anonymized summaries of other providers' findings across debate rounds."
                )

                disclosureRow(
                    title: "What stays on-device",
                    body: "API keys live in the macOS Keychain, reachable only via the signed Joint Chiefs key-reader binary. Review transcripts are written to ~/Library/Application Support/Joint Chiefs/ as plain JSON — no cloud sync, no telemetry."
                )

                disclosureRow(
                    title: "Who Joint Chiefs doesn't talk to",
                    body: "No analytics. No crash reporters. No first-party server. The only network calls are to the LLM APIs whose keys you've added."
                )

                openSourcePanel
            }
        } footer: {
            Button("Continue") {
                model.currentSection = .keys
            }
            .buttonStyle(.agentPrimary)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func disclosureRow(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.xs) {
            Text(title)
                .font(.agentPanelHeader)
                .foregroundStyle(Color.agentTextAccent)
                .agentUppercaseCaption()
                .accessibilityAddTraits(.isHeader)
            Text(body)
                .font(.agentBody)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Trust signal — the app is MIT-licensed and the entire source is public.
    /// Put the GitHub link within easy reach so users can verify claims about
    /// what does and doesn't leave their machine.
    private var openSourcePanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.xs) {
            Text("Open source")
                .font(.agentPanelHeader)
                .foregroundStyle(Color.agentTextAccent)
                .agentUppercaseCaption()
                .accessibilityAddTraits(.isHeader)
            Text("MIT-licensed. Full source on GitHub — every binary here builds from public code. No hidden calls, no black boxes.")
                .font(.agentBody)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: "https://github.com/djfunboy/joint-chiefs") {
                Link(destination: url) {
                    HStack(spacing: AgentSpacing.xxs) {
                        Text("github.com/djfunboy/joint-chiefs")
                            .font(.agentSmall)
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.agentTextAccent)
                    .padding(.vertical, AgentSpacing.xxs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Joint Chiefs repository on GitHub")
            }
        }
    }
}
