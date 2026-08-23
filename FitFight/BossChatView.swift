import MessageUI
import SwiftUI
import UIKit

struct BossMessage: Identifiable, Hashable, Codable {
    var id: String
    var text: String
    var fromBoss: Bool
    var sentAt: Date
}

/// Private line to Marc. Messages live on the phone; sending also opens Mail
/// so they actually land in his inbox until there is a server.
final class BossChatStore: ObservableObject {
    @Published var messages: [BossMessage]

    static let marc = Person(
        id: "marc",
        name: "Marc",
        handle: "@marc",
        initials: "ML"
    )

    static let hello = BossMessage(
        id: "hello",
        text: "Hey — Marc here. This line is private, not the public board. What’s on your mind?",
        fromBoss: true,
        sentAt: Date(timeIntervalSince1970: 0)
    )

    private let persist: Bool
    private static let defaultsKey = "ff.bossChat"

    init(messages: [BossMessage]? = nil, persist: Bool = true) {
        self.persist = persist
        if let messages {
            self.messages = messages
        } else if persist, let loaded = Self.load(), !loaded.isEmpty {
            self.messages = loaded
        } else {
            self.messages = [Self.hello]
            if persist { save() }
        }
    }

    static var screenshot: BossChatStore {
        BossChatStore(
            messages: [
                hello,
                BossMessage(
                    id: "you-1",
                    text: "The vote pills feel tiny on the Requests page.",
                    fromBoss: false,
                    sentAt: Date()
                ),
                BossMessage(
                    id: "ack",
                    text: "Got it — I’ll reply to this email.",
                    fromBoss: true,
                    sentAt: Date()
                ),
            ],
            persist: false
        )
    }

    func append(_ text: String, fromBoss: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(
            BossMessage(
                id: UUID().uuidString,
                text: trimmed,
                fromBoss: fromBoss,
                sentAt: Date()
            )
        )
        save()
    }

    func ackIfNeeded() {
        guard !messages.contains(where: { $0.id == "ack" }) else { return }
        messages.append(
            BossMessage(
                id: "ack",
                text: "Got it — I’ll reply to this email.",
                fromBoss: true,
                sentAt: Date()
            )
        )
        save()
    }

    private func save() {
        guard persist else { return }
        let data = try? JSONEncoder().encode(messages)
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func load() -> [BossMessage]? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode([BossMessage].self, from: data)
    }
}

struct BossChatView: View {
    @StateObject private var store: BossChatStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ffStaticRender) private var staticRender

    @State private var draft = ""
    @State private var pendingSend: String?
    @State private var showingMail = false

    init(store: BossChatStore? = nil) {
        _store = StateObject(wrappedValue: store ?? BossChatStore())
    }

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner()
            header
            thread
            composer
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showingMail, onDismiss: mailSheetDismissed) {
            MailComposeView(
                to: ["marc@marclamy.com"],
                subject: "FitFight — talk to the boss",
                body: pendingSend ?? ""
            ) { result in
                showingMail = false
                if result == .sent {
                    commitPending()
                }
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            FFAvatar(BossChatStore.marc, size: 36, ring: true)
            VStack(alignment: .leading, spacing: 2) {
                FFLabel(text: "Marc", role: .headline)
                Text("the boss · private")
                    .font(.ff(12))
                    .foregroundStyle(theme.faint)
            }
            Spacer(minLength: 8)
            Button("Close") { dismiss() }
                .font(theme.font(.bodyStrong))
                .foregroundStyle(theme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { theme.line.frame(height: 1) }
    }

    @ViewBuilder
    private var thread: some View {
        if staticRender {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.messages) { message in
                    bubble(message)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(store.messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .onChange(of: store.messages.count) { _, _ in
                    if let last = store.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = store.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func bubble(_ message: BossMessage) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.fromBoss {
                FFAvatar(BossChatStore.marc, size: 24)
            } else {
                Spacer(minLength: 48)
            }
            Text(message.text)
                .font(.ff(15))
                .foregroundStyle(message.fromBoss ? theme.text : theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    message.fromBoss ? theme.surface : theme.accent,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    if message.fromBoss {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(theme.line, lineWidth: 1)
                    }
                }
            if message.fromBoss {
                Spacer(minLength: 48)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sends to Marc’s inbox. He replies by email.")
                .font(.ff(11))
                .foregroundStyle(theme.faint)
            HStack(spacing: 10) {
                TextField("Write to Marc", text: $draft, axis: .vertical)
                    .font(.ff(15))
                    .foregroundStyle(theme.text)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(theme.chip, in: Capsule())
                    .overlay { Capsule().strokeBorder(theme.line, lineWidth: 1) }
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.ink)
                        .frame(width: 36, height: 36)
                        .background(theme.accent, in: Circle())
                }
                .buttonStyle(FFPressStyle(scale: 0.97))
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(theme.bg)
        .overlay(alignment: .top) { theme.line.frame(height: 1) }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pendingSend = text
        if MFMailComposeViewController.canSendMail() {
            showingMail = true
        } else if let url = mailtoURL(text) {
            UIApplication.shared.open(url)
            commitPending()
        } else {
            commitPending()
        }
    }

    private func mailSheetDismissed() {
        // Cancel / fail leave the draft in the field so nothing is lost.
    }

    private func commitPending() {
        guard let text = pendingSend else { return }
        store.append(text, fromBoss: false)
        store.ackIfNeeded()
        pendingSend = nil
        draft = ""
    }

    private func mailtoURL(_ body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "marc@marclamy.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "FitFight — talk to the boss"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}

private struct MailComposeView: UIViewControllerRepresentable {
    var to: [String]
    var subject: String
    var body: String
    var onFinish: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients(to)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) {
                self.onFinish(result)
            }
        }
    }
}

#Preview {
    BossChatView(store: .screenshot)
        .fitFightTheme(ThemeCatalog.theme(base: .dark, accent: .blue))
}
