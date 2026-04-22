import SwiftUI

struct DisclosureView: View {

    @Environment(SetupModel.self) private var model

    var body: some View {
        SetupPage(
            title: "Before you start",
            subtitle: "Joint Chiefs sends code you explicitly submit to the LLM providers you configure. Nothing is sent until you run a review."
        ) {
            VStack(alignment: .leading, spacing: AgentSpacing.lg) {
                disclosureRow(
                    title: "What's sent off-device",
                    body: "When you run `jointchiefs review`, the code file (or stdin content) is sent to each configured provider. The moderator also sees anonymized summaries of other providers' findings across debate rounds."
                )

                disclosureRow(
                    title: "What stays on-device",
                    body: "API keys live in the macOS Keychain, reachable only via the signed `jointchiefs-keygetter` binary. Review transcripts are written to ~/Library/Application Support/Joint Chiefs/ as plain JSON — no cloud sync, no telemetry."
                )

                disclosureRow(
                    title: "Who Joint Chiefs doesn't talk to",
                    body: "No analytics. No crash reporters. No first-party server. The only network calls are to the LLM APIs whose keys you've added."
                )
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
}
