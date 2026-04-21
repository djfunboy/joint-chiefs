import SwiftUI

// MARK: - Agentdeck Button Styles
//
// Source of truth: docs/DESIGN-SYSTEM.md
//
// Every button in the setup app uses one of these styles. Never style a
// Button inline with `.background(...)` + `.foregroundStyle(...)` — always
// `.buttonStyle(AgentPrimaryButtonStyle())`.

// MARK: - Primary (Joint Chiefs blue)

/// Filled blue button. Use for the single most important action on a view —
/// "Install," "Save config," "Add key." Only one primary button per surface.
struct AgentPrimaryButtonStyle: ButtonStyle {
    var size: AgentButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentBody)
            .foregroundStyle(Color.white)
            .padding(.horizontal, size.horizontal)
            .padding(.vertical, size.vertical)
            .background(
                RoundedRectangle(cornerRadius: AgentRadius.md)
                    .fill(configuration.isPressed ? Color.agentBrandBlueHover : Color.agentBrandBlue)
            )
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Secondary (outlined)

/// Transparent with a warm-charcoal border. Use for the alternate-action slot
/// next to a primary button.
struct AgentSecondaryButtonStyle: ButtonStyle {
    var size: AgentButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentBody)
            .foregroundStyle(Color.agentTextPrimary)
            .padding(.horizontal, size.horizontal)
            .padding(.vertical, size.vertical)
            .background(
                RoundedRectangle(cornerRadius: AgentRadius.md)
                    .fill(configuration.isPressed ? Color.agentBgHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AgentRadius.md)
                    .stroke(Color.agentBorderMuted, lineWidth: 1)
            )
    }
}

// MARK: - Ghost (no chrome)

/// No background, no border. Hover fills `agentBgHover`. Use for toolbar
/// actions and "cancel"-adjacent moments.
struct AgentGhostButtonStyle: ButtonStyle {
    var size: AgentButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentBody)
            .foregroundStyle(Color.agentTextPrimary)
            .padding(.horizontal, size.horizontal)
            .padding(.vertical, size.vertical)
            .background(
                RoundedRectangle(cornerRadius: AgentRadius.md)
                    .fill(configuration.isPressed ? Color.agentBgHover : Color.clear)
            )
    }
}

// MARK: - Merge (success green, compact)

/// Filled `agentSuccess` button. Use for workflow "merge / apply / commit"
/// moments. Compact padding, 4pt radius. Not for primary CTAs.
struct AgentMergeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentSmall.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AgentRadius.sm)
                    .fill(Color.agentSuccess)
            )
            .brightness(configuration.isPressed ? -0.05 : 0)
    }
}

// MARK: - Danger (red tint)

/// Tinted-red for destructive actions (Delete key, Reset strategy). Tinted
/// background + red text — not a solid red button.
struct AgentDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentSmall.weight(.semibold))
            .foregroundStyle(Color.agentError)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AgentRadius.sm)
                    .fill(Color.agentError.opacity(configuration.isPressed ? 0.20 : 0.12))
            )
    }
}

// MARK: - Toolbar (icon button)

/// Ghost button tuned for icon-only toolbar actions. Smaller padding,
/// `agentTextBody` idle → `agentTextPrimary` on hover.
struct AgentToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentSmall)
            .foregroundStyle(Color.agentTextBody)
            .padding(.horizontal, AgentSpacing.sm)
            .padding(.vertical, AgentSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: AgentRadius.sm)
                    .fill(configuration.isPressed ? Color.agentTextPrimary.opacity(0.06) : Color.clear)
            )
    }
}

// MARK: - Size variants

enum AgentButtonSize {
    case regular
    case small

    var horizontal: CGFloat {
        switch self {
        case .regular: return AgentSpacing.lg     // 16
        case .small:   return AgentSpacing.md     // 12
        }
    }

    var vertical: CGFloat {
        switch self {
        case .regular: return AgentSpacing.md     // 12
        case .small:   return AgentSpacing.sm     // 8
        }
    }
}

// MARK: - Convenience wrappers

extension ButtonStyle where Self == AgentPrimaryButtonStyle {
    static var agentPrimary: AgentPrimaryButtonStyle { AgentPrimaryButtonStyle() }
    static func agentPrimary(size: AgentButtonSize) -> AgentPrimaryButtonStyle { .init(size: size) }
}

extension ButtonStyle where Self == AgentSecondaryButtonStyle {
    static var agentSecondary: AgentSecondaryButtonStyle { AgentSecondaryButtonStyle() }
    static func agentSecondary(size: AgentButtonSize) -> AgentSecondaryButtonStyle { .init(size: size) }
}

extension ButtonStyle where Self == AgentGhostButtonStyle {
    static var agentGhost: AgentGhostButtonStyle { AgentGhostButtonStyle() }
}

extension ButtonStyle where Self == AgentMergeButtonStyle {
    static var agentMerge: AgentMergeButtonStyle { AgentMergeButtonStyle() }
}

extension ButtonStyle where Self == AgentDangerButtonStyle {
    static var agentDanger: AgentDangerButtonStyle { AgentDangerButtonStyle() }
}

extension ButtonStyle where Self == AgentToolbarButtonStyle {
    static var agentToolbar: AgentToolbarButtonStyle { AgentToolbarButtonStyle() }
}
