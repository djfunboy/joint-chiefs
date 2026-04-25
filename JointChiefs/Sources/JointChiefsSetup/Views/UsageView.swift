import AppKit
import SwiftUI

/// First screen of the setup wizard. Orients the user to what Joint Chiefs
/// actually is — a panel of LLMs that debate a code review and produce one
/// consensus summary — and shows exactly how to invoke it from a terminal
/// or any AI client with MCP configured. Setup screens (Keys / Roles / MCP
/// Config) follow; Data Handling closes the flow for the users who want the
/// full threat model before they ship a review.
struct UsageView: View {

    @Environment(SetupModel.self) private var model
    @State private var copiedAiSnippet = false
    @State private var copiedCliSnippet = false

    var body: some View {
        SetupPage(
            title: "How to Use",
            subtitle: "Joint Chiefs gets multiple LLMs debating your code, project, or files to surface the insights and direction you need to make the right call."
        ) {
            VStack(alignment: .leading, spacing: AgentSpacing.lg) {
                introPanel
                invocationPanel
                threePartPanel
                examplesPanel
            }
        } footer: {
            Button("Next — Add API Keys") {
                model.currentSection = .keys
            }
            .buttonStyle(.agentPrimary)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Moves to the API Keys step of the setup wizard")
        }
    }

    // MARK: - Intro — what the app actually is

    private var introPanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.sm) {
                AgentSectionHeader(text: "What it does")
                Spacer()
                openSourceLink
            }

            VStack(alignment: .leading, spacing: AgentSpacing.sm) {
                Text("Joint Chiefs pulls multiple AI models into a review of your code, project, or files — OpenAI, Gemini, Grok, Claude, and optionally a local model via Ollama. You pick which ones participate. They each weigh in, see each other's feedback, and either push back or revise. The moderator pulls out what matters: the insights and direction you need to decide what to do next.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentTextBody)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Multiple models beat one. Each has different blind spots and different priors. The positions that survive the debate are the ones worth trusting — sharper architecture calls, real issues surfaced, better judgment on what to fix first.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentTextBody)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Run it from your AI coding assistant or the terminal. Nothing leaves your machine except the code you explicitly ask it to review.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentTextBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .agentPanel()
    }

    /// Small trust signal — Joint Chiefs is MIT-licensed and the source is
    /// public. Link sits in the intro panel header so it's visible at the
    /// first screen without taking space from body copy.
    @ViewBuilder
    private var openSourceLink: some View {
        if let url = URL(string: "https://github.com/djfunboy/joint-chiefs") {
            Link(destination: url) {
                HStack(spacing: AgentSpacing.xxs) {
                    Text("Open source")
                        .font(.agentXS)
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Color.agentTextAccent)
                .padding(.vertical, AgentSpacing.xxs)
                .padding(.horizontal, AgentSpacing.xs)
                .overlay(
                    RoundedRectangle(cornerRadius: AgentRadius.xs)
                        .strokeBorder(Color.agentBorderMuted, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View Joint Chiefs source on GitHub")
        }
    }

    // MARK: - Three-part prompt

    private var threePartPanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.md) {
            AgentSectionHeader(text: "Three things to tell Joint Chiefs")

            dimensionRow(
                label: "WHAT",
                body: "A file, a function, or pasted code. Tighter is better — keep it focused."
            )
            dimensionRow(
                label: "GOAL",
                body: "What should it look for? Bugs, security, performance, readability — pick one. Without this, every review comes back generic."
            )
            dimensionRow(
                label: "CONTEXT",
                body: "Who's using it and at what scale. A quirk that's fine for a side project might be a real problem on a public app. The more context you give, the sharper the review."
            )
        }
        .agentPanel()
    }

    private func dimensionRow(label: String, body: String) -> some View {
        HStack(alignment: .top, spacing: AgentSpacing.md) {
            Text(label)
                .font(.agentPanelHeader)
                .agentUppercaseCaption()
                .foregroundStyle(Color.agentTextAccent)
                .frame(width: 72, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Text(body)
                .font(.agentSmall)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Examples

    private var examplesPanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.md) {
            AgentSectionHeader(text: "Weak vs strong prompts")

            exampleRow(
                kind: .weak,
                code: "Have Joint Chiefs review this code."
            )
            exampleRow(
                kind: .strong,
                code: "Have Joint Chiefs review my checkout flow. Look for bugs and edge cases — specifically anything that'd break if a user refreshes mid-purchase. It's for a small side project with a few hundred users."
            )
        }
        .agentPanel()
    }

    private enum ExampleKind {
        case weak, strong

        var label: String {
            switch self {
            case .weak:   "WEAK"
            case .strong: "STRONG"
            }
        }
        var pillKind: AgentPill.Kind {
            switch self {
            case .weak:   .warning
            case .strong: .success
            }
        }
        var icon: String {
            switch self {
            case .weak:   "minus.circle.fill"
            case .strong: "checkmark.circle.fill"
            }
        }
    }

    private func exampleRow(kind: ExampleKind, code: String) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.xs) {
            AgentPill(text: kind.label, kind: kind.pillKind, icon: kind.icon)
            codeFrame(code: code)
        }
    }

    // MARK: - Invocation

    private var invocationPanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.md) {
            AgentSectionHeader(text: "Two ways to call it — pick whichever fits")

            VStack(alignment: .leading, spacing: AgentSpacing.xs) {
                HStack {
                    Text("From your AI coding assistant")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentTextPrimary)
                    Spacer()
                    Button(copiedAiSnippet ? "Copied" : "Copy") {
                        copyToPasteboard(aiSnippet)
                        copiedAiSnippet = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedAiSnippet = false }
                    }
                    .buttonStyle(.agentGhost)
                    .accessibilityLabel(copiedAiSnippet ? "Copied" : "Copy snippet")
                }
                Text("Say **\"Joint Chiefs\"** in your prompt. That tells your AI to call the Joint Chiefs MCP, which runs the multi-model review and hands the consensus back to you.")
                    .font(.agentSmall)
                    .foregroundStyle(Color.agentTextBody)
                    .fixedSize(horizontal: false, vertical: true)
                codeFrame(code: aiSnippet)
            }

            orDivider

            VStack(alignment: .leading, spacing: AgentSpacing.xs) {
                HStack {
                    Text("From your terminal")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentTextPrimary)
                    Spacer()
                    Button(copiedCliSnippet ? "Copied" : "Copy") {
                        copyToPasteboard(cliSnippet)
                        copiedCliSnippet = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedCliSnippet = false }
                    }
                    .buttonStyle(.agentGhost)
                    .accessibilityLabel(copiedCliSnippet ? "Copied" : "Copy snippet")
                }
                Text("If you're comfortable in a terminal, you can call it directly. The `--goal` and `--context` flags are optional — add them when you want to focus the review.")
                    .font(.agentSmall)
                    .foregroundStyle(Color.agentTextBody)
                    .fixedSize(horizontal: false, vertical: true)
                codeFrame(code: cliSnippet)
            }
        }
        .agentPanel()
    }

    private var orDivider: some View {
        HStack(spacing: AgentSpacing.sm) {
            Rectangle()
                .fill(Color.agentBorder)
                .frame(height: 1)
            Text("OR")
                .font(.agentPanelHeader)
                .agentUppercaseCaption()
                .foregroundStyle(Color.agentTextAccent)
            Rectangle()
                .fill(Color.agentBorder)
                .frame(height: 1)
        }
        .padding(.vertical, AgentSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("or")
    }

    // MARK: - Code frame

    @ViewBuilder
    private func codeFrame(code: String) -> some View {
        ScrollView {
            Text(code)
                .font(.agentSmall)
                .foregroundStyle(Color.agentTextPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AgentSpacing.md)
        }
        .frame(maxHeight: 180)
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

    // MARK: - Snippet content

    private var aiSnippet: String {
        "Have Joint Chiefs review my login page. Check for bugs and common security mistakes — it's for a small side project I'm about to share with friends."
    }

    private var cliSnippet: String {
        """
        jointchiefs review src/login.ts \\
            --goal "bugs and basic security" \\
            --context "Side project, small user base"
        """
    }
}
