import JointChiefsCore
import SwiftUI

struct RolesWeightsView: View {

    @Environment(SetupModel.self) private var model
    @State private var saveError: String?

    var body: some View {
        SetupPage(
            title: "Roles & Weights",
            subtitle: "Pick who moderates the debate, who breaks ties, and how each provider's vote counts in the final consensus."
        ) {
            VStack(alignment: .leading, spacing: AgentSpacing.xl) {
                moderatorSection
                tiebreakerSection
                consensusSection
                weightsSection
                debateShapeSection
            }
            .padding(.top, AgentSpacing.xs)
        } footer: {
            Button("Save Strategy") {
                do {
                    try model.saveStrategy()
                    saveError = nil
                } catch {
                    saveError = error.localizedDescription
                }
            }
            .buttonStyle(.agentSecondary)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!model.strategyIsDirty)

            Button("Next: MCP Config") {
                model.currentSection = .mcp
            }
            .buttonStyle(.agentPrimary)
            .keyboardShortcut(.defaultAction)
        } leading: {
            if model.strategyIsDirty {
                AgentPill(text: "unsaved changes", kind: .warning, icon: "circle.fill")
            }
            if let saveError {
                Text(saveError)
                    .font(.agentXS)
                    .foregroundStyle(Color.agentError)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    // MARK: - Moderator

    private var moderatorSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.sm) {
            AgentSectionHeader(text: "Moderator")
            Text("Synthesizes findings between debate rounds and (in `Moderator Decides` mode) writes the final consensus.")
                .font(.agentSmall)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AgentSpacing.xs) {
                ForEach(ModeratorSelection.allCases, id: \.self) { selection in
                    AgentChip(
                        label: label(for: selection),
                        isActive: model.strategy.moderator == selection,
                        action: { model.setModerator(selection) }
                    )
                }
            }
        }
        .agentPanel()
    }

    // MARK: - Tiebreaker

    private var tiebreakerSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.sm) {
            AgentSectionHeader(text: "Tiebreaker")
            Text("When the moderator can't decide alone, the tiebreaker reads the full debate transcript and writes the final synthesis.")
                .font(.agentSmall)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AgentSpacing.xs),
                    GridItem(.flexible(), spacing: AgentSpacing.xs),
                    GridItem(.flexible(), spacing: AgentSpacing.xs)
                ],
                alignment: .leading,
                spacing: AgentSpacing.xs
            ) {
                AgentChip(
                    label: "Same as moderator",
                    isActive: isTiebreakerActive(.sameAsModerator),
                    action: { model.setTiebreaker(.sameAsModerator) }
                )
                ForEach(ModeratorSelection.allCases, id: \.self) { selection in
                    AgentChip(
                        label: label(for: selection),
                        isActive: isTiebreakerActive(.specific(selection)),
                        action: { model.setTiebreaker(.specific(selection)) }
                    )
                }
            }
        }
        .agentPanel()
    }

    private enum TiebreakerOption: Hashable {
        case sameAsModerator
        case specific(ModeratorSelection)
    }

    private func isTiebreakerActive(_ option: TiebreakerOption) -> Bool {
        switch (model.strategy.tiebreaker, option) {
        case (.sameAsModerator, .sameAsModerator):
            return true
        case (.specific(let current), .specific(let candidate)):
            return current == candidate
        default:
            return false
        }
    }

    // MARK: - Consensus Mode

    private var consensusSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.sm) {
            AgentSectionHeader(text: "Consensus Mode")
            Text("How findings are aggregated across the panel.")
                .font(.agentSmall)
                .foregroundStyle(Color.agentTextBody)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AgentSpacing.xs),
                    GridItem(.flexible(), spacing: AgentSpacing.xs)
                ],
                alignment: .leading,
                spacing: AgentSpacing.xs
            ) {
                consensusChip("Moderator decides", .moderatorDecides)
                consensusChip("Strict majority",   .strictMajority)
                consensusChip("Best of all",       .bestOfAll)
                consensusChip("Voting threshold",  .votingThreshold)
            }

            if model.strategy.consensus == .votingThreshold {
                HStack(spacing: AgentSpacing.md) {
                    Text("Threshold: \(Int(model.strategy.thresholdPercent * 100))%")
                        .font(.agentBody.monospacedDigit())
                        .foregroundStyle(Color.agentTextPrimary)
                        .frame(width: 140, alignment: .leading)
                        .accessibilityHidden(true)
                    Slider(
                        value: Binding(
                            get: { model.strategy.thresholdPercent },
                            set: { model.setThresholdPercent($0) }
                        ),
                        in: 0.1...1.0,
                        step: 0.05
                    )
                    .tint(Color.agentBrandBlue)
                    .accessibilityLabel("Voting threshold percent")
                    .accessibilityValue("\(Int(model.strategy.thresholdPercent * 100)) percent")
                }
                .padding(.top, AgentSpacing.xs)
            }
        }
        .agentPanel()
    }

    private func consensusChip(_ label: String, _ value: ConsensusMode) -> some View {
        AgentChip(
            label: label,
            isActive: model.strategy.consensus == value,
            action: { model.setConsensus(value) }
        )
    }

    // MARK: - Weights

    private var weightsSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.md) {
            AgentSectionHeader(text: "Provider Weights")
            Text("1.0 = default vote. Set to 0 to exclude a provider entirely. Higher weights count as multiple votes when Voting Threshold mode is active.")
                .font(.agentSmall)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: AgentSpacing.sm) {
                ForEach(ProviderType.allCases, id: \.self) { provider in
                    WeightSlider(provider: provider)
                        .environment(model)
                }
            }
        }
        .agentPanel()
    }

    // MARK: - Rounds & Timeout

    private var debateShapeSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.md) {
            AgentSectionHeader(text: "Debate Shape")

            HStack(spacing: AgentSpacing.md) {
                Text("Max rounds: \(model.strategy.maxRounds)")
                    .font(.agentBody.monospacedDigit())
                    .foregroundStyle(Color.agentTextPrimary)
                    .frame(width: 140, alignment: .leading)
                    .accessibilityHidden(true)
                Slider(
                    value: Binding(
                        get: { Double(model.strategy.maxRounds) },
                        set: { model.setMaxRounds(Int($0)) }
                    ),
                    in: 0...10,
                    step: 1
                )
                .tint(Color.agentBrandBlue)
                .accessibilityLabel("Max debate rounds")
                .accessibilityValue("\(model.strategy.maxRounds)")
            }

            Text("More rounds means a more thorough review, but it takes longer and costs more. 1–2 is quick, 3–5 is typical, 6+ is deep-dive territory. Joint Chiefs stops early when the models agree.")
                .font(.agentXS)
                .foregroundStyle(Color.agentTextMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AgentSpacing.md) {
                Text("Timeout: \(model.strategy.timeoutSeconds)s")
                    .font(.agentBody.monospacedDigit())
                    .foregroundStyle(Color.agentTextPrimary)
                    .frame(width: 140, alignment: .leading)
                    .accessibilityHidden(true)
                Slider(
                    value: Binding(
                        get: { Double(model.strategy.timeoutSeconds) },
                        set: { model.setTimeoutSeconds(Int($0)) }
                    ),
                    in: 30...300,
                    step: 10
                )
                .tint(Color.agentBrandBlue)
                .accessibilityLabel("Per-provider timeout in seconds")
                .accessibilityValue("\(model.strategy.timeoutSeconds) seconds")
            }

            Text("How long to wait for any single model before giving up on it. 120s works for most reviews. Bump higher if you see timeouts on big files.")
                .font(.agentXS)
                .foregroundStyle(Color.agentTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .agentPanel()
    }

    // MARK: - Labels

    private func label(for selection: ModeratorSelection) -> String {
        switch selection {
        case .claude: "Claude"
        case .openai: "OpenAI"
        case .gemini: "Gemini"
        case .grok: "Grok"
        case .none: "None (code)"
        }
    }
}

private struct WeightSlider: View {

    let provider: ProviderType
    @Environment(SetupModel.self) private var model

    var body: some View {
        HStack(spacing: AgentSpacing.md) {
            Text(label)
                .font(.agentBody)
                .foregroundStyle(Color.agentTextPrimary)
                .frame(width: 140, alignment: .leading)
                .accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { model.strategy.weight(for: provider) },
                    set: { model.setWeight($0, for: provider) }
                ),
                in: 0.0...3.0,
                step: 0.1
            )
            .tint(Color.agentBrandBlue)
            .accessibilityLabel("\(label) vote weight")
            .accessibilityValue(accessibilityWeightValue)
            Text(weightLabel)
                .font(.agentSmall.monospacedDigit())
                .foregroundStyle(isExcluded ? Color.agentError : Color.agentTextBody)
                .frame(width: 80, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityWeightValue: String {
        let value = model.strategy.weight(for: provider)
        return isExcluded
            ? "excluded (weight zero)"
            : String(format: "%.1f times default", value)
    }

    private var label: String {
        switch provider {
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        case .grok: "Grok"
        case .anthropic: "Anthropic"
        case .ollama: "Ollama"
        case .openAICompatible: "LM Studio"
        }
    }

    private var isExcluded: Bool {
        model.strategy.isExcluded(provider)
    }

    private var weightLabel: String {
        let value = model.strategy.weight(for: provider)
        return isExcluded ? "excluded" : String(format: "%.1f×", value)
    }
}
