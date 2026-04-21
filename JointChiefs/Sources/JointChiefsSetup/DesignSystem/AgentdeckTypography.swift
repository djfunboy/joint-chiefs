import SwiftUI

// MARK: - Agentdeck Design System — Typography
//
// Source of truth: docs/DESIGN-SYSTEM.md
//
// The app is "monospace as identity." Every button, pill, tab, code, and
// technical label uses the system monospaced font. Proportional sans (the
// system default) is reserved for human-authored prose only — model names,
// persona descriptions, agent names, modal titles/subtitles/field labels.

extension Font {

    // MARK: - Mono scale (primary)
    //
    // SwiftUI picks SF Mono on macOS 15+ via `.monospaced` design. Sizes match
    // the Agentdeck compact scale.

    /// 11pt / 14lh — diff counts, row subtitles
    static let agentXS = Font.system(size: 11, weight: .regular, design: .monospaced)

    /// 12pt / 16lh — tab labels, code, pills
    static let agentSmall = Font.system(size: 12, weight: .regular, design: .monospaced)

    /// 12pt / 16lh / 600 — panel headers. Apply `.tracking(0.6)` and
    /// `.textCase(.uppercase)` at the Text site for the full effect.
    static let agentPanelHeader = Font.system(size: 12, weight: .semibold, design: .monospaced)

    /// 13pt / 18lh / 500 — title bar, row title, chat body
    static let agentBody = Font.system(size: 13, weight: .medium, design: .monospaced)

    /// 14pt / 20lh / 500 — section intros, emphasized body
    static let agentLg = Font.system(size: 14, weight: .medium, design: .monospaced)

    /// 12pt / 16lh / 600 / uppercase — section eyebrows/captions.
    /// Apply `.tracking(0.6)` + `.textCase(.uppercase)` at the Text site.
    static let agentCaption = Font.system(size: 12, weight: .semibold, design: .monospaced)

    /// 10pt UPPER — inline "NEW" / version badges. Apply `.tracking(0.6)` +
    /// `.textCase(.uppercase)`.
    static let agentBadge = Font.system(size: 10, weight: .semibold, design: .monospaced)

    // MARK: - Sans scale (prose-only moments)

    /// Dialog title — system sans, 17pt semibold
    static let agentDialogTitle = Font.system(size: 17, weight: .semibold)

    /// Dialog subtitle — system sans, 13pt regular
    static let agentDialogSubtitle = Font.system(size: 13, weight: .regular)

    /// Field label in a dialog — system sans, 13pt medium
    static let agentFieldLabel = Font.system(size: 13, weight: .medium)

    /// Human name row (model display name, persona) — system sans, 13pt regular
    static let agentHumanName = Font.system(size: 13, weight: .regular)
}

// MARK: - Tracking helpers
//
// SwiftUI `Font` doesn't carry `letter-spacing` directly; apply tracking to
// `Text` views that need the Agentdeck 0.05em uppercase treatment.

extension View {

    /// Apply the canonical uppercase-caption treatment: 0.05em tracking + upper case.
    /// Approximation: 0.05em × 12pt = 0.6pt of tracking. Safe to apply to any
    /// `View`; the tracking has no effect on non-text content.
    func agentUppercaseCaption() -> some View {
        self.tracking(0.6).textCase(.uppercase)
    }
}
