import SwiftUI

struct RequestsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme
    @State private var filter: Filter = .top
    @State private var showingBossChat = false

    enum Filter: String, CaseIterable, Identifiable, Hashable {
        case top = "Top"
        case features = "Features"
        case bugs = "Bugs"
        var id: String { rawValue }
    }

    var body: some View {
        FFScreen {
            FFScreenTitle(
                title: "Requests",
                subtitle: "Vote on what gets built next.",
                trailing: AnyView(FFIconButton(systemName: "plus", size: 38) {})
            )
            .padding(.bottom, 6)

            FFAddRow(title: "Talk to the boss", subtitle: "Tell Marc what you want") {
                showingBossChat = true
            }

            HStack(spacing: 8) {
                ForEach(Filter.allCases) { option in
                    FFChip(
                        title: option.rawValue,
                        count: count(option),
                        selected: filter == option
                    ) { filter = option }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 6)

            ForEach(filtered) { item in
                RequestCard(item: item)
            }

            Text("Anything you post is public to everyone using FitFight.")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.top, theme.space.lg)
        }
        .sheet(isPresented: $showingBossChat) {
            BossChatView()
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
    }

    private func count(_ option: Filter) -> Int {
        switch option {
        case .top: return model.requests.count
        case .features: return model.requests.filter { $0.kind == .feature }.count
        case .bugs: return model.requests.filter { $0.kind == .bug }.count
        }
    }

    private var filtered: [RequestItem] {
        switch filter {
        case .top:
            return model.requests.sorted { votes($0) > votes($1) }
        case .features:
            return model.requests.filter { $0.kind == .feature }
        case .bugs:
            return model.requests.filter { $0.kind == .bug }
        }
    }

    private func votes(_ item: RequestItem) -> Int {
        item.votes + (model.voted.contains(item.id) ? 1 : 0)
    }
}

struct RequestCard: View {
    let item: RequestItem
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let voted = model.voted.contains(item.id)
        let votes = item.votes + (voted ? 1 : 0)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                if voted { model.voted.remove(item.id) } else { model.voted.insert(item.id) }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .heavy))
                    Text("\(votes)")
                        .ffType(.button)
                }
                .foregroundStyle(voted ? theme.mossOn : theme.textDim)
                .padding(.vertical, 10)
                .frame(width: 44)
                // The pill stretches to the height of the card, with the count pinned top.
                .frame(maxHeight: .infinity, alignment: .top)
                .background(
                    voted ? theme.mossFill : theme.control,
                    in: RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
                )
                .ffBorder(voted ? theme.mossEdge : theme.line, radius: theme.radius.glyph)
            }
            .buttonStyle(FFPressStyle())

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    FFTag(
                        item.kind == .feature ? "Feature" : "Bug",
                        tone: item.kind == .feature ? .moss : .ember
                    )
                    FFTag(statusText, tone: statusTone)
                }
                .padding(.bottom, 8)
                Text(item.title)
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                    .padding(.bottom, 4)
                Text(item.body)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 11)
                HStack(spacing: 8) {
                    FFAvatar(item.author, size: 22)
                    Text("\(item.author.name) · \(item.ago)")
                        .ffType(.micro)
                        .foregroundStyle(theme.textSecondary)
                    Spacer(minLength: 8)
                    Image(systemName: "bubble.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textFaint)
                    Text("\(item.comments)")
                        .ffType(.micro)
                        .foregroundStyle(theme.textFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.card)
    }

    private var statusText: String {
        switch item.status {
        case .open: return "Open"
        case .planned: return "Planned"
        case .shipped: return "Shipped"
        }
    }

    private var statusTone: FFTone {
        switch item.status {
        case .open: return .neutral
        case .planned: return .gold
        case .shipped: return .moss
        }
    }
}
