import SwiftUI

// MARK: - Agentdeck Design System — Color Tokens
//
// Source of truth: docs/DESIGN-SYSTEM.md
// Original reference: https://ui-engine-gallery.netlify.app/agentdeck/design-system
//
// Every color the app uses lives here. Views read these via `.agentBgDeep`,
// `.agentTextPrimary`, etc. Never hardcode a hex value inside a view — add a
// token here first if the design system needs one it doesn't have.

extension Color {

    // MARK: - Surfaces
    static let agentBgDeep        = Color(red: 20/255.0,  green: 17/255.0,  blue: 16/255.0)    // #141110
    static let agentBgPanel       = Color(red: 26/255.0,  green: 22/255.0,  blue: 20/255.0)    // #1a1614
    static let agentBgRow         = Color(red: 33/255.0,  green: 30/255.0,  blue: 28/255.0)    // #211e1c
    static let agentBgChatUser    = Color(red: 36/255.0,  green: 25/255.0,  blue: 22/255.0)    // #241916
    static let agentBgHover       = Color(red: 42/255.0,  green: 38/255.0,  blue: 36/255.0)    // #2a2624
    static let agentBgActive      = Color(red: 51/255.0,  green: 46/255.0,  blue: 43/255.0)    // #332e2b
    static let agentBgCode        = Color(red: 14/255.0,  green: 11/255.0,  blue: 10/255.0)    // #0e0b0a
    static let agentBgUncommitted = Color(red: 58/255.0,  green: 46/255.0,  blue: 42/255.0)    // #3a2e2a — warm pink-brown workflow tint
    static let agentBgReady       = Color(red: 14/255.0,  green: 43/255.0,  blue: 24/255.0)    // #0e2b18 — dark green workflow tint

    // MARK: - Text
    static let agentTextPrimary = Color(red: 243/255.0, green: 242/255.0, blue: 241/255.0)     // #f3f2f1
    static let agentTextBody    = Color(red: 165/255.0, green: 160/255.0, blue: 156/255.0)     // #a5a09c
    static let agentTextMuted   = Color(red: 121/255.0, green: 95/255.0,  blue: 93/255.0)      // #795f5d
    static let agentTextAccent  = Color(red: 164/255.0, green: 132/255.0, blue: 127/255.0)     // #a4847f — warm-tan accent

    // MARK: - Borders
    static let agentBorder       = Color(red: 44/255.0, green: 40/255.0, blue: 38/255.0)       // #2c2826
    static let agentBorderMuted  = Color(red: 58/255.0, green: 53/255.0, blue: 51/255.0)       // #3a3533

    // MARK: - Brand (Joint Chiefs blue — info role)
    static let agentBrandBlue       = Color(red: 2/255.0,   green: 133/255.0, blue: 255/255.0) // #0285ff
    static let agentBrandBlueHover  = Color(red: 10/255.0,  green: 116/255.0, blue: 221/255.0) // #0a74dd

    // MARK: - Status
    static let agentSuccess = Color(red: 0/255.0,   green: 199/255.0, blue: 88/255.0)          // #00c758
    static let agentError   = Color(red: 251/255.0, green: 44/255.0,  blue: 54/255.0)          // #fb2c36
    static let agentInfo    = Color(red: 48/255.0,  green: 128/255.0, blue: 255/255.0)         // #3080ff
    static let agentWarning = Color(red: 224/255.0, green: 160/255.0, blue: 96/255.0)          // #e0a060
}

// MARK: - Spacing (4px grid)

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

// MARK: - Radii

enum AgentRadius {
    static let xs:   CGFloat = 2
    static let sm:   CGFloat = 4
    static let md:   CGFloat = 6    // default buttons
    static let lg:   CGFloat = 8    // cards
    static let xl:   CGFloat = 10   // app window shell
    static let xl2:  CGFloat = 12
    static let pill: CGFloat = 9999
}

// MARK: - Layout dimensions

enum AgentLayout {
    static let toolbarHeight:     CGFloat = 44
    static let sidebarWidth:      CGFloat = 232
    static let rightPanelWidth:   CGFloat = 360
    static let workspaceRowMin:   CGFloat = 52
    static let fileDiffRowHeight: CGFloat = 28
}

// MARK: - Shadows

enum AgentShadow {

    struct Spec {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    static let card    = Spec(color: .black.opacity(0.40), radius: 2,  x: 0, y: 1)
    static let popover = Spec(color: .black.opacity(0.55), radius: 24, x: 0, y: 8)
    static let window  = Spec(color: .black.opacity(0.45), radius: 48, x: 0, y: 24)
    static let focus   = Spec(color: .agentSuccess.opacity(0.35), radius: 2, x: 0, y: 0)
}

extension View {

    /// Apply one of the canonical Agentdeck shadow specs.
    func agentShadow(_ spec: AgentShadow.Spec) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: spec.x, y: spec.y)
    }
}
