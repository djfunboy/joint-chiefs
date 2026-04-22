import SwiftUI

// MARK: - Setup Page Scaffold
//
// Every setup-app view renders inside `SetupPage` so the onboarding flow reads
// consistently across all five steps:
//
//   ┌──────────────────────────────────────┐
//   │  Title                               │  sans, .agentDialogTitle
//   │  Subtitle                            │  sans, .agentDialogSubtitle
//   │                                      │
//   │  scrollable body content             │  view-specific
//   │  ⋮                                   │
//   ├──────────────────────────────────────┤  1pt agentBorder hairline
//   │  leading             secondary  [P]  │  sticky footer
//   └──────────────────────────────────────┘
//
// The footer is outside the ScrollView so the primary CTA stays visible even
// when the body overflows. `leading` holds non-CTA content (unsaved-changes
// pill, inline error) that should also never fall below the fold.

struct SetupPage<PageBody: View, PageFooter: View, PageLeading: View>: View {

    let title: String
    let subtitle: String?
    let pageBody: PageBody
    let pageFooter: PageFooter
    let pageLeading: PageLeading

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder body: () -> PageBody,
        @ViewBuilder footer: () -> PageFooter,
        @ViewBuilder leading: () -> PageLeading = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.pageBody = body()
        self.pageFooter = footer()
        self.pageLeading = leading()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.lg) {
                    Text(title)
                        .font(.agentDialogTitle)
                        .foregroundStyle(Color.agentTextPrimary)
                        .accessibilityAddTraits(.isHeader)

                    if let subtitle {
                        Text(subtitle)
                            .font(.agentDialogSubtitle)
                            .foregroundStyle(Color.agentTextBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    pageBody
                }
                .padding(.horizontal, AgentSpacing.xl2)
                .padding(.top, AgentSpacing.xl2)
                .padding(.bottom, AgentSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color.agentBgDeep)

            footerBar
        }
    }

    private var footerBar: some View {
        HStack(spacing: AgentSpacing.sm) {
            pageLeading
            Spacer(minLength: AgentSpacing.sm)
            pageFooter
        }
        .padding(.horizontal, AgentSpacing.xl2)
        .padding(.vertical, AgentSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.agentBgPanel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.agentBorder)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }
}
