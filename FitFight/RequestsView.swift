import SwiftUI

struct RequestsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme
    @State private var filter: Filter = .top

    enum Filter: String, CaseIterable, Identifiable {
        case top = "Top"
        case features = "Features"
        case bugs = "Bugs"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.sectionGap) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        FFLabel(text: "Requests", role: .display)
                        FFLabel(text: "Vote on what gets built next", role: .body, color: theme.muted)
                    }
                    Spacer()
                    FFButton(title: "+ New", kind: .small) {}
                }

                HStack(spacing: 0) {
                    ForEach(Filter.allCases) { item in
                        Button {
                            filter = item
                        } label: {
                            VStack(spacing: 8) {
                                FFLabel(
                                    text: item.rawValue,
                                    role: .bodyStrong,
                                    color: filter == item ? theme.text : theme.muted
                                )
                                Rectangle()
                                    .fill(filter == item ? theme.accent : Color.clear)
                                    .frame(height: 2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: theme.space.cardGap) {
                    ForEach(filtered) { item in
                        RequestCard(item: item)
                    }
                }
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, theme.space.xl)
        }
        .background(theme.bg)
    }

    private var filtered: [RequestItem] {
        switch filter {
        case .top:
            return model.requests.sorted { $0.votes > $1.votes }
        case .features:
            return model.requests.filter { $0.kind == .feature }
        case .bugs:
            return model.requests.filter { $0.kind == .bug }
        }
    }
}

struct RequestCard: View {
    let item: RequestItem
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let voted = model.voted.contains(item.id)
        let votes: Int = {
            if item.id == "r1" {
                return voted ? item.votes : item.votes - 1
            }
            return voted ? item.votes + 1 : item.votes
        }()
        return FFCard {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    if voted { model.voted.remove(item.id) } else { model.voted.insert(item.id) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                        Text("\(votes)")
                            .font(theme.font(.bodyStrong))
                            .monospacedDigit()
                    }
                    .foregroundStyle(voted ? theme.ink : theme.muted)
                    .frame(width: 44, height: 56)
                    .background(
                        voted ? theme.accent : theme.chip,
                        in: RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
                    )
                }
                .buttonStyle(FFPressStyle(scale: 0.97))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        FFBadge(
                            text: item.kind == .feature ? "Feature" : "Bug",
                            tone: item.kind == .feature ? .blue : .red
                        )
                        FFBadge(text: statusText, tone: statusTone)
                    }
                    FFLabel(text: item.title, role: .bodyStrong)
                    FFLabel(text: item.body, role: .caption, color: theme.muted)
                    HStack(spacing: 8) {
                        FFAvatar(initials: item.author.initials, size: 18)
                        FFLabel(text: item.author.name, role: .micro, color: theme.muted)
                        FFLabel(text: item.ago, role: .micro, color: theme.faint)
                        Spacer()
                        Image(systemName: "text.bubble")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.faint)
                        FFLabel(text: "\(item.comments)", role: .micro, color: theme.faint)
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
