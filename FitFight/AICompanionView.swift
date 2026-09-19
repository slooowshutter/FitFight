import SwiftUI

struct AICompanionView: View {
    let initialDescription: String
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var companions: CompanionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AICompanionStore()
    @State private var workflow: FitFightAIRequest.Workflow = .avatar
    @State private var description = ""
    @State private var scene = ""
    @State private var selected: [UUID] = []
    @State private var operation: Task<Void, Never>?
    @State private var assigning = false

    var body: some View {
        FFScreen(clearance: false) {
            HStack {
                Text("Create your companion").ffType(.title).foregroundStyle(theme.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel(String(localized: "Close"))
                .foregroundStyle(theme.textSecondary)
            }
            if let allowance = store.allowance {
                HStack {
                    Text(String(localized: "ai.credits", defaultValue: "\(allowance.available) credits available"))
                    if allowance.reserved > 0 {
                        Text(String(localized: "ai.credits-reserved", defaultValue: "\(allowance.reserved) reserved"))
                    }
                }
                .ffType(.caption).foregroundStyle(theme.textSecondary)
                .accessibilityElement(children: .combine)
            }
            if let action = store.action {
                FFSection(title: String(localized: "Your generation")) {
                    Text(action.description).ffType(.body).foregroundStyle(theme.text)
                    Text(store.progress).ffType(.caption).foregroundStyle(theme.textSecondary)
                    Text("You can close this screen and return to check the same request.")
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                    FFButton(title: String(localized: "Check again"), kind: .secondary, enabled: !store.busy, busy: store.busy, fullWidth: true) {
                        operation = Task { await store.resume(session: session) }
                    }
                }
            } else {
                Picker(String(localized: "Generation"), selection: $workflow) {
                    Text("Avatar").tag(FitFightAIRequest.Workflow.avatar)
                    Text("Fitness levels").tag(FitFightAIRequest.Workflow.fitness)
                    Text("Group photo").tag(FitFightAIRequest.Workflow.groupPhoto)
                }
                .pickerStyle(.segmented)
                if workflow == .avatar {
                    FFField(label: String(localized: "Your animal"), counter: "\(description.count)/1000", minHeight: 120) {
                        TextField(String(localized: "Species, breed, accessories, colors…"), text: $description, axis: .vertical)
                            .lineLimit(4...8)
                            .onChange(of: description) { _, text in description = String(text.prefix(1000)) }
                    }
                } else {
                    Text(workflow == .fitness
                         ? String(localized: "Choose one of your saved avatars for five fitness levels.")
                         : String(localized: "Choose two to five of your saved avatars, in cast order."))
                        .ffType(.body).foregroundStyle(theme.textSecondary)
                    if store.avatars.isEmpty {
                        Text("Create an avatar first. Your saved avatars will appear here.")
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                    }
                    ForEach(store.avatars) { entry in
                        Button {
                            if workflow == .fitness { selected = [entry.id] }
                            else if selected.contains(entry.id) { selected.removeAll { $0 == entry.id } }
                            else if selected.count < 5 { selected.append(entry.id) }
                        } label: {
                            HStack(spacing: 12) {
                                RemotePhoto(url: entry.images.first?.media.url, contentMode: .fit) { theme.control }
                                    .frame(width: 64, height: 64)
                                Text(entry.description).ffType(.body).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                                if let index = selected.firstIndex(of: entry.id) {
                                    Text("\(index + 1)").ffType(.body).foregroundStyle(theme.mossText)
                                }
                            }
                            .padding(12)
                            .background(theme.control, in: RoundedRectangle(cornerRadius: 22))
                        }
                        .buttonStyle(.plain).foregroundStyle(theme.text)
                        .accessibilityAddTraits(selected.contains(entry.id) ? .isSelected : [])
                    }
                    if workflow == .groupPhoto {
                        FFField(label: String(localized: "Scene"), counter: "\(scene.count)/1000", minHeight: 100) {
                            TextField(String(localized: "Describe what your characters are doing."), text: $scene, axis: .vertical)
                                .lineLimit(3...6)
                                .onChange(of: scene) { _, text in scene = String(text.prefix(1000)) }
                        }
                    }
                }
                if let price {
                    Text(String(localized: "ai.generation-price", defaultValue: "\(price) credits per generation"))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                    if let allowance = store.allowance, allowance.available < price {
                        Text("You do not have enough available credits.").ffType(.caption).foregroundStyle(theme.emberText)
                    }
                } else {
                    Text("This generation is not available yet.").ffType(.caption).foregroundStyle(theme.textSecondary)
                }
                FFButton(title: String(localized: "Generate"), kind: .primary, enabled: canGenerate, busy: store.busy, fullWidth: true) {
                    let characters = selected.compactMap { id in
                        store.avatars.first(where: { $0.id == id }).map {
                            FitFightAICharacter(avatarRequestID: $0.id, identityDetails: $0.description)
                        }
                    }
                    let text = workflow == .avatar ? description : workflow == .groupPhoto ? scene : characters.first?.identityDetails ?? ""
                    operation = Task {
                        await store.begin(workflow: workflow, description: text.trimmingCharacters(in: .whitespacesAndNewlines), characters: characters, session: session)
                    }
                }
            }
            if !store.error.isEmpty {
                Text(store.error).ffType(.caption).foregroundStyle(theme.emberText)
                    .accessibilityLabel(store.error)
                if store.action == nil {
                    FFButton(title: String(localized: "Try again"), kind: .ghost, enabled: !store.busy, fullWidth: true) {
                        operation = Task { await store.open(session: session) }
                    }
                }
            }
            if !store.library.isEmpty {
                FFSection(title: String(localized: "Your generated images")) {
                    ForEach(store.library) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(entry.description).ffType(.body).foregroundStyle(theme.text)
                            ForEach(entry.images) { image in
                                VStack(spacing: 8) {
                                    RemotePhoto(url: image.url, contentMode: .fit) { theme.control }
                                        .frame(height: 220).accessibilityLabel(entry.description)
                                    if entry.workflow == .fitness {
                                        Text(stageLabel(image.stage)).ffType(.caption).foregroundStyle(theme.textSecondary)
                                    }
                                    if entry.workflow != .groupPhoto {
                                        FFButton(title: String(localized: "Use as companion"), kind: .secondary, enabled: !assigning && !store.busy, busy: assigning, fullWidth: true) {
                                            operation = Task {
                                                assigning = true
                                                defer { assigning = false }
                                                do {
                                                    try await session.setCompanion(image: .init(requestID: entry.requestID, stage: image.stage))
                                                    companions.apply(session.profile)
                                                    dismiss()
                                                } catch {
                                                    if !Task.isCancelled { store.error = error.localizedDescription }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { if description.isEmpty { description = initialDescription } }
        .onChange(of: workflow) { _, _ in selected = [] }
        .onDisappear { operation?.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { operation?.cancel() } }
        .task(id: "\(session.profile?.userId.uuidString ?? "")-\(scenePhase)") {
            guard scenePhase == .active else { return }
            await store.open(session: session)
            if !Task.isCancelled { await store.resume(session: session) }
        }
    }

    private var price: Int? {
        switch workflow {
        case .avatar: store.allowance?.avatarPrice
        case .fitness: store.allowance?.fitnessPrice
        case .groupPhoto: store.allowance?.groupPhotoPrice
        }
    }

    private var canGenerate: Bool {
        guard !store.busy, !assigning, !store.recoveryBlocked, let price, let allowance = store.allowance, allowance.available >= price else { return false }
        switch workflow {
        case .avatar: return !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .fitness: return selected.count == 1
        case .groupPhoto: return (2...5).contains(selected.count) && !scene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func stageLabel(_ stage: String) -> String {
        switch stage {
        case "resting": String(localized: "Resting")
        case "soft": String(localized: "Soft")
        case "average": String(localized: "Average")
        case "fit": String(localized: "Fit")
        case "strong": String(localized: "Strong")
        default: stage
        }
    }
}
