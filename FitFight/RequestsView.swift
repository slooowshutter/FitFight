import SwiftUI

struct RequestsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme
    @State private var filter: Filter = .top

    enum Filter: String, CaseIterable, Identifiable, Hashable {
        case top = "Top"
        case features = "Features"
        case bugs = "Bugs"
        var id: String { rawValue }
    }

    var body: some View {
        FFScreen {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        FFLabel(text: "Requests", role: .display)
                        Text("Vote on what gets built next.")
                            .font(.ff(13))
                            .foregroundStyle(theme.muted)
                    }
                    Spacer(minLength: 0)
                    FFButton(title: "New", kind: .small, icon: "plus") {}
                }
                .padding(.top, 2)
                .padding(.bottom, 20)

                FFSegmented(items: Filter.allCases, selection: $filter) { $0.rawValue }
                    .padding(.bottom, 16)

                VStack(spacing: 10) {
                    ForEach(filtered) { item in
                        RequestCard(item: item)
                    }
                }

                Text("Anything you post is public to everyone using FitFight.")
                    .font(.ff(13))
                    .foregroundStyle(theme.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, theme.space.xl)
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
        return FFCard(padding: 16.5) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    if voted { model.voted.remove(item.id) } else { model.voted.insert(item.id) }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(votes)")
                            .font(.ff(17, .bold))
                    }
                    .foregroundStyle(voted ? theme.ink : theme.text)
                    .frame(width: 44)
                    .frame(maxHeight: .infinity)
                    .background(
                        voted ? theme.accent : theme.chip,
                        in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                    )
                    .overlay {
                        if !voted {
                            RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                                .strokeBorder(theme.line, lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(FFPressStyle(scale: 0.97))

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        FFBadge(
                            text: item.kind == .feature ? "Feature" : "Bug",
                            tone: item.kind == .feature ? .blue : .red
                        )
                        FFBadge(text: statusText, tone: statusTone, style: .plain)
                    }
                    .padding(.bottom, 5.5)
                    Text(item.title)
                        .font(.ff(14, .bold))
                        .foregroundStyle(theme.text)
                        .padding(.bottom, 4)
                    Text(item.body)
                        .font(.ff(12))
                        .foregroundStyle(theme.muted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 9.5)
                    HStack(spacing: 8) {
                        FFAvatar(item.author, size: 17)
                        Text("\(item.author.name) · \(item.ago)")
                            .font(.ff(11))
                            .foregroundStyle(theme.muted)
                        Spacer(minLength: 8)
                        Image(systemName: "bubble.left")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.faint)
                        Text("\(item.comments)")
                            .font(.ff(12))
                            .foregroundStyle(theme.faint)
                    }
                }
            }
        }
    }

    private var statusText: String {
        switch item.status {
        case .open: return "Open"
        case .planned: return "Planned"
        case .shipped: return "Shipped"
        }
    }

    private var statusTone: FFBadge.Tone {
        switch item.status {
        case .open: return .muted
        case .planned: return .amber
        case .shipped: return .green
        }
    }
}
