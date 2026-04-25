import SwiftUI

// MARK: - Agentdeck Design System — Reusable Components
//
// Source of truth: docs/DESIGN-SYSTEM.md
//
// Components here are the Swift implementations of patterns the design system
// already spec'd: the warm-tan dashed input focus, the tinted status pills,
// and the warm-charcoal panel surface. Views should never re-implement these
// from raw primitives — add a new component here if the design system needs
// one it doesn't have.

// MARK: - Input style

/// Apply the canonical Agentdeck input chrome to a TextField / SecureField:
/// `agentBgPanel` background, 1pt `agentBorder` → dashed `agentTextAccent`
/// when focused, 6pt radius, 10×12 padding, mono body font.
///
/// The caller owns focus via `@FocusState` and passes `isFocused` in — wiring
/// `@FocusState` inside a `ViewModifier` would divorce focus from the field.
///
/// Placeholder styling: SwiftUI uses `.secondary` for `TextField("label", ...)`
/// placeholders by default, which reads as gray against the warm-dark surface.
/// Use the `prompt:` parameter with a styled `Text` to match the design system:
///
///     TextField(
///         "", text: $value,
///         prompt: Text("your-model").foregroundStyle(Color.agentTextMuted)
///     )
///     .agentInputStyle(focused: isFocused)
struct AgentInputStyle: ViewModifier {

    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .font(.agentBody)
            .foregroundStyle(Color.agentTextPrimary)
            .tint(Color.agentTextAccent)
            .textFieldStyle(.plain)
            .padding(.vertical, 10)
            .padding(.horizontal, AgentSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AgentRadius.md)
                    .fill(Color.agentBgPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AgentRadius.md)
                    .strokeBorder(
                        isFocused ? Color.agentTextAccent.opacity(0.8) : Color.agentBorder,
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: isFocused ? [3, 2] : []
                        )
                    )
            )
    }
}

extension View {

    /// Apply `AgentInputStyle` with the caller's focus state.
    func agentInputStyle(focused: Bool) -> some View {
        modifier(AgentInputStyle(isFocused: focused))
    }
}

// MARK: - Panel surface

extension View {

    /// Wrap content in the standard Agentdeck panel: `agentBgPanel` fill, 1pt
    /// `agentBorder` outline, 8pt radius. Replaces native `GroupBox` in
    /// warm-dark surfaces.
    func agentPanel(padding: CGFloat = AgentSpacing.md) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: AgentRadius.lg)
                    .fill(Color.agentBgPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AgentRadius.lg)
                    .strokeBorder(Color.agentBorder, lineWidth: 1)
            )
    }

    /// Panel variant that overrides background + border with workflow tints.
    /// Use `agentBgUncommitted` for dirty state, `agentBgReady` for ready
    /// state. Border color is inferred from the tint.
    func agentPanel(tint: Color, padding: CGFloat = AgentSpacing.md) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: AgentRadius.lg)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AgentRadius.lg)
                    .strokeBorder(Color.agentBorder, lineWidth: 1)
            )
    }
}

// MARK: - Chip

/// Agentdeck chip — used for model/mode pickers that replace native
/// segmented controls. Idle: 1px `agentBorderMuted` border, clear fill.
/// Active: 1px `agentTextAccent` border, `agentBgUncommitted` fill (warm
/// pink-brown). 4pt radius, 6/10 padding, mono 12pt / 500.
struct AgentChip: View {

    let label: String
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.agentSmall.weight(.medium))
                .foregroundStyle(Color.agentTextPrimary)
                .padding(.vertical, AgentSpacing.xs + 2)     // 6
                .padding(.horizontal, AgentSpacing.sm + 2)   // 10
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: AgentRadius.sm)
                        .fill(isActive ? Color.agentBgUncommitted : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AgentRadius.sm)
                        .strokeBorder(
                            isActive ? Color.agentTextAccent : Color.agentBorderMuted,
                            lineWidth: 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: AgentRadius.sm))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section header

/// Agentdeck panel/section eyebrow label — mono 12pt / 600, uppercase,
/// 0.05em tracking, `agentTextAccent` warm-tan color. VoiceOver reads this
/// with the `.isHeader` trait so users can skip between sections using the
/// rotor.
struct AgentSectionHeader: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.agentPanelHeader)
            .foregroundStyle(Color.agentTextAccent)
            .agentUppercaseCaption()
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Status pill

/// Agentdeck tinted pill. Used for `saved`, `validated`, `testing`, `error`,
/// and other short status labels. Renders mono 12pt / 600, 4pt radius,
/// 2×8 padding with a tinted background per the design system.
struct AgentPill: View {

    enum Kind {
        case success
        case info
        case warning
        case error
        case neutral
        case accent
    }

    let text: String
    var kind: Kind = .neutral
    var icon: String? = nil
    /// Compact variant shrinks the type to `agentXS` (11pt) and the icon to
    /// 9pt, matching the surrounding scale when the pill sits next to small
    /// labels (e.g. the sidebar update-status footer).
    var compact: Bool = false

    var body: some View {
        HStack(spacing: AgentSpacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
            }
            Text(text)
                .font((compact ? Font.agentXS : Font.agentSmall).weight(.semibold))
        }
        .foregroundStyle(foreground)
        .padding(.vertical, AgentSpacing.xxs)
        .padding(.horizontal, AgentSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AgentRadius.sm)
                .fill(background)
        )
        .lineLimit(1)
    }

    private var foreground: Color {
        switch kind {
        case .success: Color.agentSuccess
        case .info:    Color.agentInfo
        case .warning: Color.agentWarning
        case .error:   Color.agentError
        case .neutral: Color.agentTextBody
        case .accent:  Color.agentTextAccent
        }
    }

    private var background: Color {
        switch kind {
        case .success: Color.agentSuccess.opacity(0.20)
        case .info:    Color.agentInfo.opacity(0.20)
        case .warning: Color.agentWarning.opacity(0.20)
        case .error:   Color.agentError.opacity(0.12)
        case .neutral: Color.agentBgPanel
        case .accent:  Color.agentTextAccent.opacity(0.25)
        }
    }
}
