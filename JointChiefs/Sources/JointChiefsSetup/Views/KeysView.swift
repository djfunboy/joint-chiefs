import JointChiefsCore
import SwiftUI

struct KeysView: View {

    @Environment(SetupModel.self) private var model

    var body: some View {
        SetupPage(
            title: "API Keys",
            subtitle: "Paste the API key for every provider you want on the panel. Keys are stored in the local Apple keychain."
        ) {
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
            .padding(.top, AgentSpacing.xs)
        } footer: {
            Button("Next: Roles & Weights") {
                model.currentSection = .rolesWeights
            }
            .buttonStyle(.agentPrimary)
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Console URL map

/// Where a user gets (or manages) their API key for each provider. Rendered as
/// a ghost external-link button next to the provider name so first-time
/// setup doesn't require a web search mid-flow.
private func consoleURL(for provider: ProviderType) -> URL? {
    switch provider {
    case .openAI:    URL(string: "https://platform.openai.com/api-keys")
    case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
    case .gemini:    URL(string: "https://aistudio.google.com/apikey")
    case .grok:      URL(string: "https://console.x.ai")
    case .ollama:    URL(string: "https://ollama.com/download")
    }
}

private func consoleLabel(for provider: ProviderType) -> String {
    switch provider {
    case .openAI:    "OpenAI console"
    case .anthropic: "Anthropic console"
    case .gemini:    "Google AI Studio"
    case .grok:      "xAI console"
    case .ollama:    "ollama.com"
    }
}

// MARK: - Ollama card

private struct OllamaCard: View {

    @Environment(SetupModel.self) private var model
    @FocusState private var focusedField: Field?

    private enum Field { case endpoint, modelName }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.sm) {
                Text("Ollama (local models)")
                    .font(.agentHumanName)
                    .foregroundStyle(Color.agentTextPrimary)
                ConsoleLink(provider: .ollama)
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Ollama: enabled but untested")
            } else {
                AgentPill(text: "disabled", kind: .neutral)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Ollama: disabled")
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Ollama: \(m) reachable")
        case .failed(let message):
            AgentPill(text: message, kind: .error, icon: "exclamationmark.triangle.fill")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Ollama error: \(message)")
        }
    }
}

// MARK: - Per-provider key row

private struct KeyRow: View {

    let provider: ProviderType

    @Environment(SetupModel.self) private var model
    @State private var localDraft: String = ""
    @FocusState private var focusedField: Field?

    private enum Field { case key }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.sm) {
            // Top row: provider name + console link + status pill.
            HStack(spacing: AgentSpacing.sm) {
                Text(providerDisplayName)
                    .font(.agentHumanName)
                    .foregroundStyle(Color.agentTextPrimary)
                ConsoleLink(provider: provider)
                statusBadge
                Spacer()
            }

            // Key row — always visible. Empty SecureField for pasting when no
            // key is saved; a masked dot display when a key is already on file.
            // Right-hand action buttons change with state.
            HStack(spacing: AgentSpacing.sm) {
                if hasSavedKey {
                    maskedKeyDisplay
                } else {
                    SecureField(
                        "",
                        text: $localDraft,
                        prompt: Text("Paste API key").foregroundStyle(Color.agentTextMuted)
                    )
                    .focused($focusedField, equals: .key)
                    .agentInputStyle(focused: focusedField == .key)
                    .accessibilityLabel("\(providerDisplayName) API key")
                }

                actionButtons
            }

            // Model row — native Menu popover over the top-5 curated list.
            // Auto-saves on selection. `Menu` gives explicit control over the
            // label appearance; `Picker(.menu)` sometimes swallows taps inside
            // custom-styled panels on macOS.
            HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.sm) {
                Text("Model")
                    .font(.agentSmall)
                    .foregroundStyle(Color.agentTextBody)
                    .frame(width: 64, alignment: .leading)
                Menu {
                    ForEach(provider.availableModels, id: \.self) { modelName in
                        Button {
                            model.setProviderModel(modelName, for: provider)
                        } label: {
                            if modelName == currentModel {
                                Label(modelLabel(modelName), systemImage: "checkmark")
                            } else {
                                Text(modelLabel(modelName))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AgentSpacing.xs) {
                        Text(modelLabel(currentModel))
                            .font(.agentSmall)
                            .foregroundStyle(Color.agentTextPrimary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.agentTextBody)
                    }
                    .agentInputStyle(focused: false)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel("\(providerDisplayName) model")
                .accessibilityValue(currentModel)
            }
        }
        .agentPanel()
    }

    /// The model currently applied for this provider — the user's saved
    /// override if set, otherwise the shipped default.
    private var currentModel: String {
        model.strategy.providerModels[provider] ?? provider.defaultModel
    }

    /// Appends a "(default)" tag to the default model so users know which one
    /// ships out of the box without having to read docs.
    private func modelLabel(_ modelName: String) -> String {
        modelName == provider.defaultModel
            ? "\(modelName) (default)"
            : modelName
    }

    /// True when the Keychain has a key for this provider — regardless of
    /// whether it's been tested. Drives the masked-dots vs paste-field toggle.
    private var hasSavedKey: Bool {
        switch model.keyStatuses[provider] {
        case .saved, .ok, .testing, .failed: true
        case .unconfigured, .none: false
        }
    }

    /// Read-only styled row of bullet dots standing in for the stored key.
    /// Fixed dot count — doesn't leak actual key length, but long enough to
    /// look like a real key (OpenAI `sk-proj-` keys run ~160 chars; Anthropic
    /// `sk-ant-` keys run ~108; Gemini ~40; Grok ~84). 48 is comfortable
    /// middle ground that reads as "long hidden string" without padding past
    /// the input field's visible width.
    private var maskedKeyDisplay: some View {
        Text(String(repeating: "•", count: 48))
            .font(.agentBody)
            .foregroundStyle(Color.agentTextBody)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .agentInputStyle(focused: false)
            .accessibilityLabel("\(providerDisplayName) key stored")
            .accessibilityValue("hidden")
    }

    /// Action buttons to the right of the key field. Contents depend on state
    /// so the user never sees a disabled button for something they can't do
    /// yet (e.g. Test before Save, Delete when nothing is stored).
    @ViewBuilder
    private var actionButtons: some View {
        switch model.keyStatuses[provider] {
        case .unconfigured, .none:
            Button("Save") {
                let toSave = localDraft
                Task {
                    await model.saveKey(toSave, for: provider)
                    localDraft = ""
                }
            }
            .buttonStyle(.agentPrimary(size: .small))
            .disabled(localDraft.isEmpty)
        case .saved, .failed:
            Button("Test") {
                Task { await model.testKey(for: provider) }
            }
            .buttonStyle(.agentSecondary(size: .small))
            Button("Delete") {
                Task { await model.deleteKey(for: provider) }
            }
            .buttonStyle(.agentDanger)
        case .ok:
            Button("Delete") {
                Task { await model.deleteKey(for: provider) }
            }
            .buttonStyle(.agentDanger)
        case .testing:
            EmptyView()
        }
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

    @ViewBuilder
    private var statusBadge: some View {
        switch model.keyStatuses[provider] {
        case .unconfigured, .none:
            AgentPill(text: "not set", kind: .neutral)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(providerDisplayName) key: not set")
        case .saved:
            AgentPill(text: "saved", kind: .success, icon: "lock.fill")
                .accessibilityElement(children: .combine)
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(providerDisplayName) key tested OK on \(model)")
        case .failed(let message):
            AgentPill(text: message, kind: .error, icon: "exclamationmark.triangle.fill")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(providerDisplayName) key error: \(message)")
        }
    }
}

// MARK: - Console link

/// Small ghost external-link that opens the provider's API-key console in the
/// default browser. Appears next to the provider name so first-time setup
/// doesn't require a separate web search.
private struct ConsoleLink: View {

    let provider: ProviderType

    var body: some View {
        if let url = consoleURL(for: provider) {
            Link(destination: url) {
                HStack(spacing: AgentSpacing.xxs) {
                    Text(consoleLabel(for: provider))
                        .font(.agentXS)
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Color.agentTextAccent)
                .padding(.vertical, AgentSpacing.xxs)
                .padding(.horizontal, AgentSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: AgentRadius.xs)
                        .fill(Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(consoleLabel(for: provider)) in browser")
        }
    }
}
