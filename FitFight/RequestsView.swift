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

                FFSegmented(items: Filter.allCases, selection: $filter) { $0.rawValue }

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
        let votes = item.votes + (voted ? 1 : 0)
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
                    .frame(width: 40, height: 64)
                    .background(voted ? theme.accent : theme.chip, in: Capsule())
                }
                .buttonStyle(FFPressStyle(scale: 0.97))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        FFBadge(
                            text: item.kind == .feature ? "Feature" : "Bug",
                            tone: item.kind == .feature ? .blue : .red
                        )
                        FFBadge(text: statusText, tone: statusTone, style: .plain)
                    }
                    FFLabel(text: item.title, role: .bodyStrong)
                    FFLabel(text: item.body, role: .caption, color: theme.muted)
                    HStack(spacing: 8) {
                        FFAvatar(initials: item.author.initials, size: 18)
                        FFLabel(text: item.author.name, role: .micro, color: theme.muted)
                        Text("·").font(theme.font(.micro)).foregroundStyle(theme.faint)
                        FFLabel(text: item.ago, role: .micro, color: theme.faint)
                        Spacer()
                        Image(systemName: "bubble.left")
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
