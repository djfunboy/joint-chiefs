import JointChiefsCore
import SwiftUI

struct KeysView: View {

    @Environment(SetupModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.lg) {
            Text("API Keys")
                .font(.agentDialogTitle)
                .foregroundStyle(Color.agentTextPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("Paste each provider's API key. Keys are written to the macOS Keychain through the signed keygetter binary — nothing is stored in plain files.")
                .font(.agentDialogSubtitle)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: AgentSpacing.md) {
                ForEach(ProviderType.allCases, id: \.self) { provider in
                    if provider == .ollama {
                        OllamaCard().environment(model)
                    } else {
                        KeyRow(provider: provider)
                            .environment(model)
                    }
                }
            }
            .padding(.top, AgentSpacing.sm)

            HStack {
                Spacer()
                Button("Next: Roles & Weights") {
                    model.currentSection = .rolesWeights
                }
                .buttonStyle(.agentPrimary)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, AgentSpacing.md)
        }
    }
}

// MARK: - Ollama card

private struct OllamaCard: View {

    @Environment(SetupModel.self) private var model
    @FocusState private var focusedField: Field?

    private enum Field { case endpoint, modelName }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ollama (local models)")
                    .font(.agentHumanName)
                    .foregroundStyle(Color.agentTextPrimary)
                Spacer()
                statusBadge
            }

            Text("Run local models like llama3, mistral, qwen2.5-coder, or deepseek-coder — no API key, nothing leaves your machine. Ollama must be installed and running separately.")
                .font(.agentSmall)
                .foregroundStyle(Color.agentTextBody)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Include Ollama in the debate", isOn: Binding(
                get: { model.strategy.ollama.enabled },
                set: { model.setOllamaEnabled($0) }
            ))
            .font(.agentBody)
            .foregroundStyle(Color.agentTextPrimary)
            .tint(Color.agentBrandBlue)

            if model.strategy.ollama.enabled {
                Rectangle()
                    .fill(Color.agentBorder)
                    .frame(height: 1)
                    .accessibilityHidden(true)

                labeledField("Endpoint") {
                    TextField(
                        "",
                        text: Binding(
                            get: { model.strategy.ollama.endpoint },
                            set: { model.setOllamaEndpoint($0) }
                        ),
                        prompt: Text("http://localhost:11434").foregroundStyle(Color.agentTextMuted)
                    )
                    .focused($focusedField, equals: .endpoint)
                    .agentInputStyle(focused: focusedField == .endpoint)
                }

                HStack(spacing: AgentSpacing.sm) {
                    labeledField("Model") {
                        TextField(
                            "",
                            text: Binding(
                                get: { model.strategy.ollama.model },
                                set: { model.setOllamaModel($0) }
                            ),
                            prompt: Text("llama3").foregroundStyle(Color.agentTextMuted)
                        )
                        .focused($focusedField, equals: .modelName)
                        .agentInputStyle(focused: focusedField == .modelName)
                    }
                    Button("Test") {
                        Task { await model.testOllamaConnection() }
                    }
                    .buttonStyle(.agentSecondary(size: .small))
                }

                Text("Tip: run `ollama pull \(model.strategy.ollama.model)` in a terminal before testing, and make sure `ollama serve` is running (or the menu-bar app is launched).")
                    .font(.agentXS)
                    .foregroundStyle(Color.agentTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .agentPanel()
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.sm) {
            Text(title)
                .font(.agentBody)
                .foregroundStyle(Color.agentTextBody)
                .frame(width: 72, alignment: .leading)
            content()
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch model.ollamaStatus {
        case .unknown:
            if model.strategy.ollama.enabled {
                AgentPill(text: "untested", kind: .neutral)
            } else {
                AgentPill(text: "disabled", kind: .neutral)
            }
        case .testing:
            HStack(spacing: AgentSpacing.xs) {
                ProgressView().controlSize(.small)
                AgentPill(text: "testing…", kind: .warning)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ollama connection: testing")
        case .ok(let m):
            AgentPill(text: "\(m) reachable", kind: .success, icon: "checkmark.circle.fill")
                .accessibilityLabel("Ollama: \(m) reachable")
        case .failed(let message):
            AgentPill(text: message, kind: .error, icon: "exclamationmark.triangle.fill")
                .accessibilityLabel("Ollama error: \(message)")
        }
    }
}

// MARK: - Per-provider key row

private struct KeyRow: View {

    let provider: ProviderType

    @Environment(SetupModel.self) private var model
    @State private var localDraft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.sm) {
            HStack(spacing: AgentSpacing.sm) {
                Text(providerDisplayName)
                    .font(.agentHumanName)
                    .foregroundStyle(Color.agentTextPrimary)
                statusBadge
                Spacer()
                if case .saved = model.keyStatuses[provider] {
                    Button("Delete") {
                        Task { await model.deleteKey(for: provider) }
                    }
                    .buttonStyle(.agentDanger)
                }
            }

            HStack(spacing: AgentSpacing.sm) {
                SecureField(
                    "",
                    text: $localDraft,
                    prompt: Text("Paste API key").foregroundStyle(Color.agentTextMuted)
                )
                .focused($isFocused)
                .agentInputStyle(focused: isFocused)

                Button("Save") {
                    let toSave = localDraft
                    Task {
                        await model.saveKey(toSave, for: provider)
                        localDraft = ""
                    }
                }
                .buttonStyle(.agentPrimary(size: .small))
                .disabled(localDraft.isEmpty)

                Button("Test") {
                    Task { await model.testKey(for: provider) }
                }
                .buttonStyle(.agentSecondary(size: .small))
                .disabled(!canTest)
            }

            if let hint = hintText {
                Text(hint)
                    .font(.agentXS)
                    .foregroundStyle(Color.agentTextMuted)
            }
        }
        .agentPanel()
    }

    private var providerDisplayName: String {
        switch provider {
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        case .grok: "xAI Grok"
        case .anthropic: "Anthropic Claude"
        case .ollama: "Ollama"
        }
    }

    private var hintText: String? {
        switch provider {
        case .openAI: "Starts with sk-…"
        case .gemini: "From Google AI Studio"
        case .grok: "From console.x.ai"
        case .anthropic: "Starts with sk-ant-… — also used as the default moderator"
        case .ollama: nil
        }
    }

    private var canTest: Bool {
        switch model.keyStatuses[provider] {
        case .saved, .ok, .failed: true
        default: false
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch model.keyStatuses[provider] {
        case .unconfigured, .none:
            AgentPill(text: "not set", kind: .neutral)
                .accessibilityLabel("\(providerDisplayName) key: not set")
        case .saved:
            AgentPill(text: "saved", kind: .success, icon: "lock.fill")
                .accessibilityLabel("\(providerDisplayName) key: saved in Keychain")
        case .testing:
            HStack(spacing: AgentSpacing.xs) {
                ProgressView().controlSize(.small)
                AgentPill(text: "testing…", kind: .warning)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(providerDisplayName) key: testing")
        case .ok(let model):
            AgentPill(text: "\(model) OK", kind: .success, icon: "checkmark.circle.fill")
                .accessibilityLabel("\(providerDisplayName) key tested OK on \(model)")
        case .failed(let message):
            AgentPill(text: message, kind: .error, icon: "exclamationmark.triangle.fill")
                .accessibilityLabel("\(providerDisplayName) key error: \(message)")
        }
    }
}
