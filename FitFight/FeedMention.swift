import SwiftUI

enum FeedMention {
    static func activeQuery(in text: String) -> (range: Range<String.Index>, query: String)? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at > text.startIndex {
            let before = text[text.index(before: at)]
            if before.isLetter || before.isNumber || before == "_" { return nil }
        }
        let start = text.index(after: at)
        let query = text[start...]
        if query.contains(where: { !$0.isLetter && !$0.isNumber && $0 != "_" }) {
            return nil
        }
        return (at..<text.endIndex, String(query).lowercased())
    }

    static func handles(in text: String) -> Set<String> {
        var handles = Set<String>()
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "@", isMentionBoundary(text, before: index) {
                let start = text.index(after: index)
                var cursor = start
                while cursor < text.endIndex {
                    let character = text[cursor]
                    if character.isLetter || character.isNumber || character == "_" {
                        cursor = text.index(after: cursor)
                    } else {
                        break
                    }
                }
                let handle = String(text[start..<cursor])
                if handle.count >= 2 && handle.count <= 30 {
                    handles.insert(handle.lowercased())
                }
            }
            index = text.index(after: index)
        }
        return handles
    }

    private static func isMentionBoundary(_ text: String, before index: String.Index) -> Bool {
        if index == text.startIndex { return true }
        let character = text[text.index(before: index)]
        return !character.isLetter && !character.isNumber && character != "_"
    }

    static func apply(handle: String, to text: String) -> String {
        guard let active = activeQuery(in: text) else {
            return text.hasSuffix(" ") ? text + "@\(handle) " : text + " @\(handle) "
        }
        return String(text[..<active.range.lowerBound]) + "@\(handle) "
    }

    static func taggedUserIDs(in text: String, people: [FitFightFightPost.Author]) -> [UUID] {
        let wanted = handles(in: text)
        return people.compactMap { person in
            wanted.contains(person.handle.lowercased()) ? person.userId : nil
        }
    }
}

struct FeedMentionField<Field: View>: View {
    @Binding var text: String
    @Binding var people: [FitFightFightPost.Author]
    var main: Bool
    var fightIDs: [UUID]
    /// Comment boxes wait for the first "@": a Feed page would otherwise request the
    /// directory once per open thread. The post composer loads eagerly because tags use it.
    var loadsOnFirstMention = false
    @ViewBuilder var field: () -> Field

    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @State private var requestedKey: String?

    private var suggestions: [FitFightFightPost.Author] {
        guard let active = FeedMention.activeQuery(in: text) else { return [] }
        let query = active.query
        let matches = query.isEmpty
            ? people
            : people.filter { person in
                person.handle.lowercased().hasPrefix(query)
                    || person.displayName.lowercased().contains(query)
            }
        return Array(matches.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.userId) { index, person in
                        Button {
                            text = FeedMention.apply(handle: person.handle, to: text)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: person.atHandle)
                                        .ffType(.label)
                                        .foregroundStyle(theme.text)
                                        .lineLimit(1)
                                    if !person.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(person.displayName)
                                            .ffType(.caption)
                                            .foregroundStyle(theme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(FFHapticPlainStyle())
                        if index < suggestions.count - 1 {
                            FFDivider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                .ffBorder(theme.hairline, radius: theme.radius.card)
            }
            field()
        }
        .task(id: loadsOnFirstMention ? nil : directoryKey) {
            guard !loadsOnFirstMention else { return }
            await loadPeople()
        }
        .onChange(of: FeedMention.activeQuery(in: text) != nil) { _, mentioning in
            guard loadsOnFirstMention, mentioning, requestedKey != directoryKey else { return }
            requestedKey = directoryKey
            Task { await loadPeople() }
        }
    }

    private var directoryKey: String {
        "\(main ? "1" : "0")-\(fightIDs.map(\.uuidString).sorted().joined(separator: ","))"
    }

    private func loadPeople() async {
        guard !staticRender, main || !fightIDs.isEmpty else {
            people = []
            return
        }
        guard let token = try? await session.freshAccessToken() else { return }
        do {
            people = try await FitFightAPI().feedPeople(
                main: main,
                fightIDs: fightIDs,
                accessToken: token
            )
        } catch {
            if Task.isCancelled || error is CancellationError { return }
        }
    }
}
