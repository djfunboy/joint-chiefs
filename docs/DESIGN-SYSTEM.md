# Joint Chiefs — Design System

**Version:** 1.2
**Last Updated:** 2026-04-26
**Source of truth:** [Agentdeck design system](https://ui-engine-gallery.netlify.app/agentdeck/design-system)
**Companion:** [`../../Joint Chiefs Website/docs/DESIGN-SYSTEM.md`](../../Joint%20Chiefs%20Website/docs/DESIGN-SYSTEM.md) — same tokens, CSS implementation

This document defines the visual language for the Joint Chiefs macOS app (setup app, and any future UI surfaces) and codifies how Agentdeck's design system maps to SwiftUI primitives.

## Personality

1. **Monospace as identity.** System monospace (SF Mono / Menlo) for all buttons, pills, status, tabs, code, and technical content. Proportional sans (system default) for *human-authored prose only* — model names, persona descriptions, agent names, modal titles and subtitles, dialog field labels. Everything else is mono.
2. **Warm, not neutral.** All greys lean brown-charcoal. Never cool greys.
3. **Green means "ready."** `#00c758` for success, merge-ready, validated states. `#fb2c36` only for errors and diff removals.

## Context

The Joint Chiefs setup app (`jointchiefs-setup`) runs as a native macOS window with the **warm-dark** app palette. The Keys, Roles & Weights, Install, and MCP Config views all live in this context.

## SwiftUI Token Implementation

Tokens live in `Sources/JointChiefsSetup/DesignSystem/AgentdeckTokens.swift`. The full surface of these tokens is re-exported as `Color`, `Font`, and `CGFloat` extensions so that views read as `.agentBgDeep`, `.agentTextPrimary`, etc.

### Surfaces

| Token | SwiftUI | Value |
|---|---|---|
| Surface deep | `Color.agentBgDeep` | `#141110` |
| Surface panel | `Color.agentBgPanel` | `#1a1614` |
| Surface row | `Color.agentBgRow` | `#211e1c` |
| Chat user bubble | `Color.agentBgChatUser` | `#241916` |
| Hover | `Color.agentBgHover` | `#2a2624` |
| Active | `Color.agentBgActive` | `#332e2b` |
| Code | `Color.agentBgCode` | `#0e0b0a` |
| Uncommitted tint | `Color.agentBgUncommitted` | `#3a2e2a` (warm pink-brown) |
| Ready tint | `Color.agentBgReady` | `#0e2b18` (dark green) |

### Text

| Token | SwiftUI | Value |
|---|---|---|
| Primary | `Color.agentTextPrimary` | `#f3f2f1` |
| Body | `Color.agentTextBody` | `#a5a09c` |
| Muted | `Color.agentTextMuted` | `#795f5d` |
| Warm-tan accent | `Color.agentTextAccent` | `#a4847f` |

### Borders

| Token | SwiftUI | Value |
|---|---|---|
| Default | `Color.agentBorder` | `#2c2826` |
| Muted | `Color.agentBorderMuted` | `#3a3533` |

### Brand & Status

Joint Chiefs blue (`#0285ff`) is slotted into the `info` role. We use it for the primary CTA and focus rings in marketing/website contexts. Inside the setup app, the brand blue is reserved for the *primary decider action* button (e.g., "Install," "Save config"). The `status.success` green takes over for "Test passed" / "Key validated."

| Token | SwiftUI | Value |
|---|---|---|
| Brand blue (primary) | `Color.agentBrandBlue` | `#0285ff` |
| Brand blue hover | `Color.agentBrandBlueHover` | `#0a74dd` |
| Success / merge | `Color.agentSuccess` | `#00c758` |
| Error / diff-del | `Color.agentError` | `#fb2c36` |
| Info | `Color.agentInfo` | `#3080ff` |
| Warning / working | `Color.agentWarning` | `#e0a060` |

### Status dots

| State | Color | Motion |
|---|---|---|
| Idle | `Color.agentTextBody` (`#a5a09c`) | Solid |
| Working | `Color.agentWarning` (`#e0a060`) | Opacity pulse, 1.2s infinite |
| Ready to merge | `Color.agentSuccess` (`#00c758`) | Solid |
| Error | `Color.agentError` (`#fb2c36`) | Solid |
| Merge conflict | `Color.agentWarning` (`#e0a060`) | Solid |

Implement the pulse with `withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true))` on `opacity`.

## Typography

### Fonts

- **Mono:** `Font.system(.body, design: .monospaced)` — this resolves to SF Mono on macOS 15+.
- **Sans:** `Font.system(.body)` — default system sans for prose in dialogs and human-authored names.

### Type scale

The app uses the compact scale from Agentdeck:

| Name | SwiftUI helper | Size / LH | Weight | Use |
|---|---|---|---|---|
| `.agentXS` | `Font.agentXS` | 11 / 14 | 400 | diffCount, subtitle |
| `.agentSmall` | `Font.agentSmall` | 12 / 16 | 400 | tabLabel, code, pill |
| `.agentBody` | `Font.agentBody` | 13 / 18 | 500 | titleBar, rowTitle, chatBody |
| `.agentLg` | `Font.agentLg` | 14 / 20 | 500 | section intros |
| `.agentPanelHeader` | `Font.agentPanelHeader` | 12 / 16 | 600 | Panel headers — UPPERCASE with 0.05em tracking |
| `.agentCaption` | `Font.agentCaption` | 12 / 16 | 600 | eyebrow/caption labels (uppercase, 0.05em) |

SwiftUI doesn't expose `letter-spacing` on `Font` directly — use `.tracking(0.05 * fontSize)` on the `Text` view for panel headers and captions.

### Voice by surface

| Surface | Font |
|---|---|
| Panel header / caption | `.agentPanelHeader` (mono, uppercase) |
| Button labels | `.agentSmall` (mono) |
| Input / textarea | `.agentBody` (mono) |
| Dialog title | System sans semibold, `.title3` (17pt) — the rare sans moment |
| Dialog subtitle | System sans regular, `.callout` (13pt), `agentTextBody` color |
| Dialog field label | System sans, `.agentBody` (13pt) |
| Human name (provider display name, persona) | System sans, `.agentBody` |
| Technical identifier (bundle id, command path) | `.agentSmall` (mono) |

## Spacing (4px grid)

Use `CGFloat` helpers from `Spacing.swift`:

```swift
enum AgentSpacing {
    static let xxs: CGFloat = 2
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 20
    static let xl2: CGFloat = 24
    static let xl3: CGFloat = 32
    static let xl4: CGFloat = 48
    static let xl5: CGFloat = 64
    static let xl6: CGFloat = 96
}
```

**App layout dimensions:**
- Toolbar height: 44pt
- Sidebar width: 232pt
- Right panel width: ~360pt
- Workspace row height: 52pt
- Compact file-diff row: 28pt

## Radii

```swift
enum AgentRadius {
    static let xs:   CGFloat = 2
    static let sm:   CGFloat = 4
    static let md:   CGFloat = 6   // default buttons
    static let lg:   CGFloat = 8   // cards
    static let xl:   CGFloat = 10  // app window shell
    static let xl2:  CGFloat = 12
    static let pill: CGFloat = 9999
}
```

## Shadows

```swift
enum AgentShadow {
    static let card   = (color: Color.black.opacity(0.04), radius: CGFloat(2),  x: CGFloat(0), y: CGFloat(1))
    static let popover = (color: Color.black.opacity(0.08), radius: CGFloat(24), x: CGFloat(0), y: CGFloat(8))
    static let window = (color: Color.black.opacity(0.45), radius: CGFloat(48), x: CGFloat(0), y: CGFloat(24))
    static let focus  = (color: Color.agentSuccess.opacity(0.35), radius: CGFloat(2), x: CGFloat(0), y: CGFloat(0))
}
```

Apply with:
```swift
.shadow(color: AgentShadow.card.color, radius: AgentShadow.card.radius, x: AgentShadow.card.x, y: AgentShadow.card.y)
```

## Components (SwiftUI Implementation)

### Buttons

All button variants conform to `ButtonStyle` and live in `AgentdeckButtonStyle.swift`.

| Style | Background | Foreground | Radius | Padding | Use |
|---|---|---|---|---|---|
| `AgentPrimaryButtonStyle` | `agentBrandBlue` | `#fff` | 6 | 12/16 | Primary CTA (Install, Save) |
| `AgentSecondaryButtonStyle` | `.clear` + 1px `agentBorderMuted` | `agentTextPrimary` | 6 | 12/16 | Secondary action |
| `AgentGhostButtonStyle` | `.clear` | `agentTextPrimary` | 6 | 12/16 | Low-emphasis action; hover fills `agentBgHover` |
| `AgentMergeButtonStyle` | `agentSuccess` | `#fff` | 4 | 5/12 | Merge / Apply destructive-looking success |
| `AgentDangerButtonStyle` | `agentError.opacity(0.12)` | `agentError` | 4 | 5/12 | Danger action (Delete key, Reset) |
| `AgentToolbarButtonStyle` | `.clear` | `agentTextBody` | 4 | 4/8 | Toolbar icons; hover fg flips to `agentTextPrimary` |

All buttons use `Font.agentSmall` and monospace except where explicitly stated.

### Inputs (TextField / SecureField)

- Background: `agentBgPanel`
- Border: 1px `agentBorder`, rounded 6pt
- Padding: 10pt vertical, 12pt horizontal
- Focus: swap border to **dashed** `agentTextAccent.opacity(0.8)` 1pt — matches Agentdeck's warm-tan dashed focus
- Font: `Font.agentBody` (mono 13pt)
- Placeholder: system default (the spec calls for `agentTextMuted`, but SwiftUI doesn't expose placeholder color on plain `TextField` without a custom overlay — tracked in `KNOWN-ISSUES.md`).

Implemented as `AgentInputStyle` in `AgentdeckComponents.swift`. The caller owns `@FocusState` and passes `isFocused` through:

```swift
@FocusState private var isFocused: Bool

TextField("Paste API key", text: $draft)
    .focused($isFocused)
    .agentInputStyle(focused: isFocused)
```

### Pills / Badges

| Pill | Background | Foreground | Size |
|---|---|---|---|
| Success | `agentSuccess.opacity(0.2)` | `agentSuccess` | mono 12pt / 600, 4pt radius, 2×8 padding |
| Info | `agentInfo.opacity(0.2)` | `agentInfo` | same |
| Warning | `agentWarning.opacity(0.2)` | `agentWarning` | same |
| Error | `agentError.opacity(0.12)` | `agentError` | same |
| Accent (NEW badge) | `agentTextAccent.opacity(0.25)` | `agentTextAccent` | same |
| Neutral | `agentBgPanel` | `agentTextBody` | mono 12pt / 400 |

Implemented as `AgentPill` in `AgentdeckComponents.swift`:

```swift
AgentPill(text: "saved", kind: .success, icon: "lock.fill")
```

### Chips (Chat input style)

Used for model picker, speed, reasoning effort, mode, etc.

- **Idle:** 1px `agentBorderMuted` border, `.clear` background, `agentTextPrimary` fg, mono 12pt/500
- **Active:** 1px `agentTextAccent` border, `agentBgUncommitted` (`#3a2e2a`) background
- 4pt radius, 6/10 padding

Implemented as `AgentChip` in `AgentdeckComponents.swift`:

```swift
AgentChip(
    label: "Claude",
    isActive: model.strategy.moderator == .claude,
    action: { model.setModerator(.claude) }
)
```

### Panel surface

Replaces native `GroupBox` in warm-dark contexts. `agentBgPanel` fill, 1pt `agentBorder` outline, 8pt radius. The tinted variant takes a color for workflow tints (`agentBgUncommitted` for dirty, `agentBgReady` for success).

Implemented as View modifiers in `AgentdeckComponents.swift`:

```swift
VStack { ... }.agentPanel()

VStack { ... }.agentPanel(tint: .agentBgReady)
```

### Section header

Uppercase mono 12pt/600 with 0.05em tracking, `agentTextAccent` warm-tan color. Used for panel eyebrow labels.

Implemented as `AgentSectionHeader` in `AgentdeckComponents.swift`:

```swift
AgentSectionHeader(text: "Moderator")
```

### Status Dots

```swift
struct AgentStatusDot: View {
    enum State { case idle, working, ready, error, conflict }
    let state: State
    // 8pt circle, color per state table above
    // `working` and `conflict` use the `agentWarning` color
    // `working` adds opacity pulse animation
}
```

### Code Block

- Background: `agentBgCode`
- Border: 1px `agentBorder`, rounded 6pt
- Padding: 12pt
- Font: `Font.agentSmall` (mono 12pt / 18lh)
- Line numbers: `agentBorderMuted` color
- Add row tint: `agentSuccess.opacity(0.08)`
- Remove row tint: `agentError.opacity(0.08)`

### Workspace Row

```
HStack(alignment: .top, spacing: 8) {
    AgentStatusDot(state: .idle)            // 8pt, margin top 6pt
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.agentBody).foregroundStyle(.agentTextPrimary)
        Text(subtitle).font(.agentXS).foregroundStyle(.agentTextMuted)
    }
    Spacer()
    // optional diff counts
    Text("+12 -3").font(.agentXS).foregroundStyle(.agentSuccess)
}
.padding(.horizontal, 12)
.padding(.vertical, 8)
.frame(minHeight: 52)
.overlay(alignment: .leading) {
    Rectangle().fill(isActive ? .agentTextBody : .clear).frame(width: 2)
}
.background(isActive ? .agentBgRow : .clear)
```

### Window Shell

- Corner radius 10pt
- Background `agentBgDeep`
- 1px border `agentBorder`
- Shadow `AgentShadow.window`
- macOS traffic lights top-left (system default)

### Tabs

- Tab bar height 40pt, bottom border 1px `agentBorder`, background `agentBgDeep`
- Tab: height 40pt, horizontal padding 14pt
- Idle: `agentTextMuted`, no bottom border
- Active: `agentTextPrimary`, 2pt bottom border `agentTextPrimary`
- Font: `Font.agentSmall` (mono 12pt / 500)

### Chat Bubbles

**User**
```swift
VStack { ... }
    .padding(.horizontal, 12).padding(.vertical, 10)
    .background(Color.agentBgChatUser)
    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.agentBorderMuted, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .frame(maxWidth: 640)
```

**Assistant** — same as user but no border and `agentBgPanel` background.

**@file mention** — inline span: `agentTextAccent` color, `agentTextAccent.opacity(0.15)` background, 3pt radius.

## Application to Setup App Views

Map the Agentdeck components onto existing setup app views:

| View | Agentdeck pattern |
|---|---|
| `UsageView` (How to Use) | Prose with system sans (title/subtitle), mono body, code-block panels for AI prompt + CLI examples with ghost Copy buttons, single primary button at bottom |
| `KeysView` | Inputs with dashed warm-tan focus, per-provider row (mono name + Save/Test/Delete buttons + success/testing/error pill), curated top-5 model picker as `AgentChip` group |
| `RolesWeightsView` | Panel headers (uppercase mono 12pt), Picker with chip-style variants, sliders with mono value labels |
| `MCPConfigView` | Code block with the standard snippet, ghost "Copy" button top-right in the block, "Configured AI tools" panel with per-tool status pills |
| `DisclosureView` (Privacy) | Prose with system sans (title/subtitle), mono body, bullet list, no primary button (terminal screen of the wizard) |

## What NOT to do

- Don't use `.padding(.horizontal, 20)` style ad-hoc numbers — always `AgentSpacing.md` etc.
- Don't mix proportional sans with mono on the same row outside the documented prose surfaces.
- Don't use `.tint(.blue)` — always explicit `Color.agentBrandBlue` or `agentSuccess`.
- Don't apply native `.controlSize(.large)` to buttons — we override padding and radius via the `ButtonStyle`.
- Don't apply `.background(Color.gray)` anywhere — warm surfaces only.
- Don't add custom fonts beyond SF Mono — no font files ship with the app.
- Don't create new color tokens without adding them here first.

## Companion docs

- `ARCHITECTURE.md` — system design (references design system for any new surface)
- `PRD.md` — product requirements (F6 setup app refers here for visual specs)
- `DATA-MODEL.md` — type definitions
- `KNOWN-ISSUES.md` — active issues
- `../../Joint Chiefs Website/docs/DESIGN-SYSTEM.md` — CSS-side of the same tokens
