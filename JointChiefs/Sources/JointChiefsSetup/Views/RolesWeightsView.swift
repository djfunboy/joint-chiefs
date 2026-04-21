import JointChiefsCore
import SwiftUI

struct RolesWeightsView: View {

    @Environment(SetupModel.self) private var model
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.lg) {
            Text("Roles & Weights")
                .font(.agentDialogTitle)
                .foregroundStyle(Color.agentTextPrimary)

            Text("Pick who moderates the debate, who breaks ties, and how each provider's vote counts in the final consensus.")
                .font(.agentDialogSubtitle)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: AgentSpacing.xl) {
                moderatorSection
                tiebreakerSection
                consensusSection
                weightsSection
                debateShapeSection
            }
            .padding(.top, AgentSpacing.sm)

            HStack(spacing: AgentSpacing.sm) {
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
                Spacer()
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

                Button("Next: Install") {
                    model.currentSection = .install
                }
                .buttonStyle(.agentPrimary)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, AgentSpacing.md)
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

            Picker("Tiebreaker", selection: tiebreakerBinding) {
                Text("Same as moderator").tag(TiebreakerOption.sameAsModerator)
                ForEach(ModeratorSelection.allCases, id: \.self) { selection in
                    Text(label(for: selection)).tag(TiebreakerOption.specific(selection))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .font(.agentBody)
            .tint(Color.agentTextAccent)
        }
        .agentPanel()
    }

    private enum TiebreakerOption: Hashable {
        case sameAsModerator
        case specific(ModeratorSelection)
    }

    private var tiebreakerBinding: Binding<TiebreakerOption> {
        Binding(
            get: {
                switch model.strategy.tiebreaker {
                case .sameAsModerator: .sameAsModerator
                case .specific(let selection): .specific(selection)
                }
            },
            set: { option in
                switch option {
                case .sameAsModerator:
                    model.setTiebreaker(.sameAsModerator)
                case .specific(let selection):
                    model.setTiebreaker(.specific(selection))
                }
            }
        )
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
                    Slider(
                        value: Binding(
                            get: { model.strategy.thresholdPercent },
                            set: { model.setThresholdPercent($0) }
                        ),
                        in: 0.1...1.0,
                        step: 0.05
                    )
                    .tint(Color.agentBrandBlue)
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
                Slider(
                    value: Binding(
                        get: { Double(model.strategy.maxRounds) },
                        set: { model.setMaxRounds(Int($0)) }
                    ),
                    in: 0...10,
                    step: 1
                )
                .tint(Color.agentBrandBlue)
            }

            HStack(spacing: AgentSpacing.md) {
                Text("Timeout: \(model.strategy.timeoutSeconds)s")
                    .font(.agentBody.monospacedDigit())
                    .foregroundStyle(Color.agentTextPrimary)
                    .frame(width: 140, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { Double(model.strategy.timeoutSeconds) },
                        set: { model.setTimeoutSeconds(Int($0)) }
                    ),
                    in: 30...300,
                    step: 10
                )
                .tint(Color.agentBrandBlue)
            }
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
            Slider(
                value: Binding(
                    get: { model.strategy.weight(for: provider) },
                    set: { model.setWeight($0, for: provider) }
                ),
                in: 0.0...3.0,
                step: 0.1
            )
            .tint(Color.agentBrandBlue)
            Text(weightLabel)
                .font(.agentSmall.monospacedDigit())
                .foregroundStyle(isExcluded ? Color.agentError : Color.agentTextBody)
                .frame(width: 80, alignment: .trailing)
        }
    }

    private var label: String {
        switch provider {
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        case .grok: "Grok"
        case .anthropic: "Anthropic"
        case .ollama: "Ollama"
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
