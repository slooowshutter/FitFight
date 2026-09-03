import SwiftUI

struct NewFightView: View {
    @EnvironmentObject private var layouts: NewFightLayoutStore
    @EnvironmentObject private var draft: NewFightDraft
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    var body: some View {
        NewFightLayoutBody(layout: activeLayout)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                if AppVersion.exploresNewFightLayouts, !staticRender {
                    NewFightLayoutSwitcher()
                        .padding(.horizontal, theme.space.screenPadding)
                        .padding(.bottom, 8)
                        .background(theme.bg)
                }
            }
            .onChange(of: layouts.layout) { _, _ in
                draft.resetFlowState()
            }
    }

    private var activeLayout: NewFightLayout {
        AppVersion.exploresNewFightLayouts ? layouts.layout : .current
    }
}
