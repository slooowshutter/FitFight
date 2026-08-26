import SwiftUI
import UIKit

/// Renders every screen to PNG so CI can publish them as artifacts and we can
/// compare the app against docs/design/source/screenshots without a Mac.
/// Only runs when the app is launched with FF_SHOOT=1.
@MainActor
enum ScreenshotExport {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["FF_SHOOT"] == "1"
    }

    static let canvas = CGSize(width: 393, height: 852)
    static let tallHeight: CGFloat = 1800

    static func exportAll() {
        let themeStore = ThemeStore()
        themeStore.baseID = .dark
        themeStore.accentID = .blue
        let model = AppModel()
        let folder = URL.documentsDirectory.appendingPathComponent("shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for shot in shots(model: model) {
            write(shot.view(themeStore, model), name: shot.name, height: canvas.height, to: folder)
            write(shot.view(themeStore, model), name: shot.name + "-full", height: tallHeight, to: folder)
        }

        let light = ThemeStore()
        light.baseID = .light
        light.accentID = .blue
        write(
            frame(FightsListView(), tab: .fights, themeStore: light, model: model),
            name: "light-fights",
            height: canvas.height,
            to: folder
        )

        try? Data("ok".utf8).write(to: folder.appendingPathComponent("done.txt"))
    }

    private struct Shot {
        let name: String
        let view: (ThemeStore, AppModel) -> AnyView
    }

    private static func shots(model: AppModel) -> [Shot] {
        let fight = model.fights.first { $0.id == "sweat" }
        let invited = model.fights.first { $0.id == "desk" }
        return [
            Shot(name: "00-welcome") { store, _ in
                let theme = store.theme
                return AnyView(
                    VStack(spacing: 0) {
                        VersionBanner()
                        WelcomeView()
                    }
                    .background(theme.bg)
                    .environmentObject(store)
                    .environmentObject(model)
                    .environmentObject(SessionStore(preview: ()))
                    .environmentObject(FriendshipStore(client: SessionStore(preview: ()).client))
                    .environmentObject(HealthKitStepsStore())
                    .environment(\.ffTheme, theme)
                    .environment(\.colorScheme, theme.colorScheme)
                    .environment(\.ffStaticRender, true)
                )
            },
            Shot(name: "01-fights") { store, model in
                frame(FightsListView(), tab: .fights, themeStore: store, model: model)
            },
            Shot(name: "02-fight-detail") { store, model in
                frame(detail(fight), tab: .fights, themeStore: store, model: model)
            },
            Shot(name: "03-fight-invited") { store, model in
                frame(detail(invited), tab: .fights, themeStore: store, model: model)
            },
            Shot(name: "04-new") { store, model in
                frame(NewFightView(), tab: .newFight, themeStore: store, model: model)
            },
            Shot(name: "05-requests") { store, model in
                frame(RequestsView(), tab: .requests, themeStore: store, model: model)
            },
            Shot(name: "06-you") { store, model in
                frame(YouView(), tab: .you, themeStore: store, model: model)
            },
            Shot(name: "08-apple-health") { store, model in
                frame(AppleHealthSourceView(), tab: .you, themeStore: store, model: model)
            },
            Shot(name: "07-boss-chat") { store, model in
                frame(BossChatView(store: .screenshot), tab: .requests, themeStore: store, model: model)
            }
        ]
    }

    @ViewBuilder
    private static func detail(_ fight: Fight?) -> some View {
        if let fight {
            FightDetailView(fight: fight)
        } else {
            Color.clear
        }
    }

    private static func frame<Content: View>(
        _ content: Content,
        tab: FFTab,
        themeStore: ThemeStore,
        model: AppModel
    ) -> AnyView {
        let theme = themeStore.theme
        let session = SessionStore(preview: ())
        return AnyView(
            VStack(spacing: 0) {
                VersionBanner()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                FFTabBar(tab: .constant(tab))
            }
            .background(theme.bg)
            .environmentObject(themeStore)
            .environmentObject(model)
            .environmentObject(session)
            .environmentObject(FriendshipStore(client: session.client))
            .environmentObject(HealthKitStepsStore())
            .environment(\.ffTheme, theme)
            .environment(\.colorScheme, theme.colorScheme)
            .environment(\.ffStaticRender, true)
        )
    }

    private static func write(_ view: AnyView, name: String, height: CGFloat, to folder: URL) {
        let renderer = ImageRenderer(content: view.frame(width: canvas.width, height: height))
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.pngData() else { return }
        try? data.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
