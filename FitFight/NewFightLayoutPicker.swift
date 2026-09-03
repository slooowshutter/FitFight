import SwiftUI

struct NewFightLayoutPicker: View {
    @EnvironmentObject private var layouts: NewFightLayoutStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner()
            HStack {
                Text("New fight layouts")
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer()
                Button("Close") { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.vertical, 12)

            Text("Ten ways to start the same Steps fight. Pick one; the New tab uses it. Layout 1 is what testers have now.")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(NewFightLayout.allCases) { layout in
                        layoutRow(layout)
                    }
                }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 12)
            }

            FFScreenCTA(title: "Open New tab") {
                dismiss()
                model.tab = .newFight
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, 22)
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private func layoutRow(_ layout: NewFightLayout) -> some View {
        let on = layouts.layout == layout
        return Button {
            layouts.layout = layout
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(layout.number)")
                    .font(.ff(13, 800))
                    .foregroundStyle(on ? theme.mossOn : theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(on ? theme.mossFill : theme.control, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(layout.title)
                            .ffType(.rowTitle)
                            .foregroundStyle(theme.text)
                        Spacer()
                        if on {
                            FFPill("on New", style: .softMoss)
                        }
                    }
                    Text(layout.blurb)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(
                on ? theme.mossWash : theme.card,
                in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
            )
            .ffBorder(on ? theme.mossEdge : theme.hairline, radius: theme.radius.card)
        }
        .buttonStyle(.plain)
    }
}
