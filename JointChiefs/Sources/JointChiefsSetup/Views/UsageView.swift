import AppKit
import SwiftUI

/// Final step of the setup wizard. Once the plumbing is done, the user
/// needs to know how to prompt Joint Chiefs well — which is a skill most
/// developers don't have on day one. This view teaches the three-part
/// prompt (what / goal / scale) and gives concrete AI-client and terminal
/// invocations they can copy.
struct UsageView: View {

    @Environment(SetupModel.self) private var model
    @State private var copiedAiSnippet = false
    @State private var copiedCliSnippet = false

    var body: some View {
        SetupPage(
            title: "How to Use",
            subtitle: "Joint Chiefs gives better reviews when you give it better prompts. Three dimensions matter every time."
        ) {
            VStack(alignment: .leading, spacing: AgentSpacing.lg) {
                successPanel
                threePartPanel
                examplesPanel
                invocationPanel
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

    // MARK: - Success affordance

    private var successPanel: some View {
        HStack(alignment: .top, spacing: AgentSpacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.agentSuccess)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AgentSpacing.xxs) {
                Text("Setup is done")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentTextPrimary)
                Text("The rest of this page is optional reading, but it's the difference between Joint Chiefs giving you boilerplate feedback and giving you review notes worth acting on.")
                    .font(.agentSmall)
                    .foregroundStyle(Color.agentTextBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .agentPanel(tint: Color.agentBgReady)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Three-part prompt

    private var threePartPanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.md) {
            AgentSectionHeader(text: "Three dimensions")

            dimensionRow(
                label: "WHAT",
                title: "The code",
                body: "A file path, a git diff, or a paste. Keep it focused — the tighter the input, the sharper the feedback."
            )
            dimensionRow(
                label: "GOAL",
                title: "The lens",
                body: "Security. Correctness. Performance. Readability. Pick one. Without a lens, every model falls back on style nits."
            )
            dimensionRow(
                label: "SCALE",
                title: "The context",
                body: "Who this code serves, at what scale, under what constraints. A null check that's fine for 100 internal users is a priority-1 defect on a 10M-user public API. Tell Joint Chiefs the scale and it prioritizes accordingly."
            )
        }
        .agentPanel()
    }

    private func dimensionRow(label: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: AgentSpacing.md) {
            Text(label)
                .font(.agentPanelHeader)
                .agentUppercaseCaption()
                .foregroundStyle(Color.agentTextAccent)
                .frame(width: 72, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: AgentSpacing.xxs) {
                Text(title)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentTextPrimary)
                Text(body)
                    .font(.agentSmall)
                    .foregroundStyle(Color.agentTextBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Examples

    private var examplesPanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.md) {
            AgentSectionHeader(text: "Weak vs strong prompts")

            exampleRow(
                kind: .weak,
                code: "Review this code."
            )
            exampleRow(
                kind: .strong,
                code: """
                Run a Joint Chiefs review on src/pricing.ts.
                Goal: correctness.
                Scale: billing math for a B2B SaaS with 500 enterprise
                customers — false charges trigger legal exposure.
                Prioritize edge cases over style.
                """
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
            AgentSectionHeader(text: "Where to run it")

            VStack(alignment: .leading, spacing: AgentSpacing.xs) {
                Text("From any AI client with MCP configured")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentTextPrimary)
                Text("Write the prompt in natural language. The AI invokes `joint_chiefs_review` for you.")
                    .font(.agentSmall)
                    .foregroundStyle(Color.agentTextBody)
                codeFrame(
                    code: aiSnippet,
                    copied: copiedAiSnippet,
                    onCopy: {
                        copyToPasteboard(aiSnippet)
                        copiedAiSnippet = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedAiSnippet = false }
                    }
                )
            }

            Rectangle()
                .fill(Color.agentBorder)
                .frame(height: 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AgentSpacing.xs) {
                Text("From your terminal")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentTextPrimary)
                Text("Use `--goal` and `--context` to encode the lens and scale. Skip them and every review comes out generic.")
                    .font(.agentSmall)
                    .foregroundStyle(Color.agentTextBody)
                codeFrame(
                    code: cliSnippet,
                    copied: copiedCliSnippet,
                    onCopy: {
                        copyToPasteboard(cliSnippet)
                        copiedCliSnippet = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedCliSnippet = false }
                    }
                )
            }
        }
        .agentPanel()
    }

    // MARK: - Code frame

    @ViewBuilder
    private func codeFrame(code: String, copied: Bool = false, onCopy: (() -> Void)? = nil) -> some View {
        ZStack(alignment: .topTrailing) {
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

            if let onCopy {
                Button(copied ? "Copied" : "Copy") { onCopy() }
                    .buttonStyle(.agentGhost)
                    .padding(AgentSpacing.xs)
                    .accessibilityLabel(copied ? "Copied" : "Copy snippet")
            }
        }
    }

    private func copyToPasteboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    // MARK: - Snippet content

    private var aiSnippet: String {
        """
        Run a Joint Chiefs review on src/auth.swift.
        Goal: security audit.
        Scale: consumer API, ~2M daily active users,
        must meet SOC 2 requirements.
        Focus on credential handling, session lifetimes,
        and OWASP Top 10 exposure.
        """
    }

    private var cliSnippet: String {
        """
        jointchiefs review src/auth.swift \\
            --goal "security audit" \\
            --context "Consumer API, 2M DAU, SOC 2 target"
        """
    }
}
