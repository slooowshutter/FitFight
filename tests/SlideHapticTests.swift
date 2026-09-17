import Foundation

// The real engine runs below against recording boundaries. These doubles model
// Apple's multiplicative intensity and additive sharpness controls, not perception.
struct CHHapticEventParameter {
    enum ID { case hapticIntensity, hapticSharpness }
    let parameterID: ID
    let value: Float
}

struct CHHapticDynamicParameter {
    enum ID { case hapticIntensityControl, hapticSharpnessControl }
    let parameterID: ID
    let value: Float
    let relativeTime: Double
}

struct CHHapticEvent {
    enum EventType { case hapticContinuous, hapticTransient }
    let eventType: EventType
    let parameters: [CHHapticEventParameter]
    let relativeTime: Double
    var duration: Double = 0
}

struct CHHapticPattern {
    let events: [CHHapticEvent]
    init(events: [CHHapticEvent], parameters: [CHHapticDynamicParameter]) throws {
        self.events = events
    }
}

let CHHapticTimeImmediate: Double = 0

@MainActor final class CHHapticAdvancedPatternPlayer {
    let pattern: CHHapticPattern
    var intensityControl: Float = 1
    var sharpnessControl: Float = 0
    var playing = false
    var intensityAtStart: Float?

    init(pattern: CHHapticPattern) { self.pattern = pattern }

    var intensity: Float {
        pattern.events[0].parameters.first { $0.parameterID == .hapticIntensity }!.value * intensityControl
    }

    var sharpness: Float {
        min(1, max(0, pattern.events[0].parameters.first { $0.parameterID == .hapticSharpness }!.value + sharpnessControl))
    }

    func start(atTime: Double) throws {
        playing = true
        intensityAtStart = intensity
    }

    func stop(atTime: Double) throws { playing = false }

    func sendParameters(_ parameters: [CHHapticDynamicParameter], atTime: Double) throws {
        for parameter in parameters {
            switch parameter.parameterID {
            case .hapticIntensityControl: intensityControl = parameter.value
            case .hapticSharpnessControl: sharpnessControl = parameter.value
            }
        }
    }
}

@MainActor final class CHHapticEngine {
    static var supported = true
    static var players: [CHHapticAdvancedPatternPlayer] = []
    var playsHapticsOnly = false

    static func capabilitiesForHardware() -> (supportsHaptics: Bool, unused: Bool) { (supported, false) }
    init() throws {}
    func start() throws {}
    func stop(completionHandler: (Error?) -> Void) {
        for player in Self.players { player.playing = false }
        completionHandler(nil)
    }
    func makeAdvancedPlayer(with pattern: CHHapticPattern) throws -> CHHapticAdvancedPatternPlayer {
        let player = CHHapticAdvancedPatternPlayer(pattern: pattern)
        Self.players.append(player)
        return player
    }
    func makePlayer(with pattern: CHHapticPattern) throws -> CHHapticAdvancedPatternPlayer {
        try makeAdvancedPlayer(with: pattern)
    }
}

@MainActor final class UIImpactFeedbackGenerator {
    enum FeedbackStyle: Equatable { case soft, light, medium, rigid, heavy }
    static var impacts: [(style: FeedbackStyle, intensity: CGFloat)] = []
    let style: FeedbackStyle
    init(style: FeedbackStyle) { self.style = style }
    func prepare() {}
    func impactOccurred(intensity: CGFloat) { Self.impacts.append((style, intensity)) }
}

protocol Gesture {}

@MainActor final class DragGesture: Gesture {
    struct Value { let translation: CGSize }
    var changed: ((Value) -> Void)?
    var ended: ((Value) -> Void)?
    init(minimumDistance: CGFloat) {}
    func onChanged(_ action: @escaping (Value) -> Void) -> DragGesture { changed = action; return self }
    func onEnded(_ action: @escaping (Value) -> Void) -> DragGesture { ended = action; return self }
}

struct Animation {
    static func timingCurve(_ a: Double, _ b: Double, _ c: Double, _ d: Double, duration: Double) -> Animation { Animation() }
}

func withAnimation(_ animation: Animation, _ action: () -> Void) { action() }

@propertyWrapper final class TestState<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

@dynamicMemberLookup struct Binding<Value> {
    let get: () -> Value
    let set: (Value) -> Void
    var wrappedValue: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }
    subscript<Member>(dynamicMember keyPath: WritableKeyPath<Value, Member>) -> Binding<Member> {
        Binding<Member>(get: { wrappedValue[keyPath: keyPath] }, set: { member in
            var value = wrappedValue
            value[keyPath: keyPath] = member
            wrappedValue = value
        })
    }
}

struct LabSettingsHarness {
    @TestState var custom = FFCustomSlideHaptics.restore(
        from: UserDefaults.standard.data(forKey: FFCustomSlideHaptics.storageKey)
    )
    @TestState var saveFailed = false

    func adjustControls() {
        settings.rumble.intensityStart.wrappedValue = 0.24
        settings.rumbleEnabled.wrappedValue = false
        settings.finish.style.wrappedValue = .rigid
        settings.confirmationProgress.wrappedValue = 0.72
    }

    func simulateEncodingFailure() { settings.startHz.wrappedValue = .nan }

    // PRODUCTION_SETTINGS
}

@MainActor struct SlideControlHarness {
    @TestState var enabled = true
    @TestState var busy = false
    @TestState var completed = false
    @TestState var drag: CGFloat = 0
    @TestState var resetsAfterSuccess = false
    let slideHaptics = FFSlideHapticEngine()
    @TestState var recipe: FFSlideHapticRecipe?
    @TestState var selectedRecipeID = FFSlideHapticRecipe.shippedID
    @TestState var customHapticData = Data()
    @TestState var action: () -> Bool = { true }

    func makeGesture(travel: CGFloat) -> DragGesture { slideGesture(travel: travel) as! DragGesture }
    func accessibleConfirm() { confirm() }

    // PRODUCTION_RECIPE
    // PRODUCTION_GESTURE
}

@main struct SlideHapticTests {
    @MainActor static func main() async throws {
        var failures: [String] = []
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition { failures.append(message) }
        }
        expect(FFSlideHapticRecipe.all.count == 20, "Keep all 20 choices")
        expect(Set(FFSlideHapticRecipe.all.map(\.id)).count == 20, "Recipe IDs stay unique")

        for recipe in FFSlideHapticRecipe.all {
            CHHapticEngine.players = []
            UIImpactFeedbackGenerator.impacts = []
            let engine = FFSlideHapticEngine()
            engine.drag(progress: 0, recipe: recipe)
            let continuous = CHHapticEngine.players.first { $0.pattern.events[0].eventType == .hapticContinuous }
            if let continuous {
                expect(continuous.intensityAtStart! <= 0.2, "\(recipe.id): no full-power pop before the soft start")
                expect(continuous.sharpness <= 0.2, "\(recipe.id): rounded start")
                var previous = continuous.intensity
                for step in 1...10 {
                    engine.drag(progress: CGFloat(step) * 0.085, recipe: recipe)
                    expect(continuous.intensity >= previous, "\(recipe.id): strength must rise")
                    previous = continuous.intensity
                }
                expect(continuous.intensity >= 0.99, "\(recipe.id): actual rumble reaches full power by confirmation")
                engine.drag(progress: 0, recipe: recipe)
                expect(continuous.intensity <= 0.2, "\(recipe.id): reversing softens the rumble")
            }
            engine.stop()
            expect(CHHapticEngine.players.allSatisfy { !$0.playing }, "\(recipe.id): cancelling stops vibration")

            // Do not yield to the clock loop: a flick can end before its first run.
            CHHapticEngine.players = []
            UIImpactFeedbackGenerator.impacts = []
            engine.drag(progress: 0.02, recipe: recipe)
            engine.drag(progress: 0.85, recipe: recipe)
            let strongTransient = CHHapticEngine.players.contains {
                $0.pattern.events[0].eventType == .hapticTransient && $0.intensity >= 0.99
            }
            let strongRumble = CHHapticEngine.players.contains {
                $0.pattern.events[0].eventType == .hapticContinuous && $0.intensity >= 0.99
            }
            let strongImpact = UIImpactFeedbackGenerator.impacts.contains { $0.intensity >= 0.99 }
            expect(strongTransient || strongRumble || strongImpact, "\(recipe.id): a fast swipe must reach full strength synchronously")
            if recipe.ticks != nil {
                expect(strongTransient || strongImpact, "\(recipe.id): a fast swipe must not miss its final tick")
            }
            engine.stop()
        }

        // The final gesture sample can cross the threshold after the last change.
        var starts = 0
        let control = SlideControlHarness()
        control.action = { starts += 1; return true }
        let gesture = control.makeGesture(travel: 100)
        gesture.changed?(DragGesture.Value(translation: CGSize(width: 40, height: 0)))
        gesture.ended?(DragGesture.Value(translation: CGSize(width: 86, height: 0)))
        expect(starts == 1 && control.completed, "A fast final sample confirms the fight")
        expect(UIImpactFeedbackGenerator.impacts.last?.style == .heavy && UIImpactFeedbackGenerator.impacts.last?.intensity == 1, "Confirmed swipe ends with a full-strength heavy hit")
        gesture.ended?(DragGesture.Value(translation: CGSize(width: 100, height: 0)))
        expect(starts == 1, "Confirmation stays single-shot")

        let cancelled = SlideControlHarness()
        cancelled.action = { starts += 1; return true }
        let cancelGesture = cancelled.makeGesture(travel: 100)
        cancelGesture.changed?(DragGesture.Value(translation: CGSize(width: 90, height: 0)))
        let impactsBeforeCancel = UIImpactFeedbackGenerator.impacts.count
        cancelGesture.ended?(DragGesture.Value(translation: CGSize(width: 20, height: 0)))
        expect(starts == 1 && cancelled.drag == 0, "Pulling back before release cancels")
        expect(UIImpactFeedbackGenerator.impacts.count == impactsBeforeCancel, "Cancellation has no finish hit")

        let lab = SlideControlHarness()
        lab.resetsAfterSuccess = true
        lab.action = { starts += 1; return true }
        lab.accessibleConfirm()
        lab.accessibleConfirm()
        expect(starts == 3 && !lab.completed, "Lab resets for repeated tests, including accessible confirmation")
        let impactsBeforeFailure = UIImpactFeedbackGenerator.impacts.count
        lab.action = { false }
        lab.accessibleConfirm()
        expect(!lab.completed && UIImpactFeedbackGenerator.impacts.count == impactsBeforeFailure, "Rejected action does not play a successful finish")
        lab.action = { starts += 1; return true }
        lab.enabled = false
        lab.accessibleConfirm()
        expect(starts == 3, "Disabled slides cannot confirm")
        lab.enabled = true
        lab.busy = true
        lab.accessibleConfirm()
        expect(starts == 3, "Busy slides cannot confirm")

        let previousCustomData = UserDefaults.standard.data(forKey: FFCustomSlideHaptics.storageKey)
        defer { UserDefaults.standard.set(previousCustomData, forKey: FFCustomSlideHaptics.storageKey) }
        UserDefaults.standard.removeObject(forKey: FFCustomSlideHaptics.storageKey)
        let editor = LabSettingsHarness()
        editor.adjustControls()
        let reopenedEditor = LabSettingsHarness()
        expect(reopenedEditor.custom == editor.custom && !editor.saveFailed, "Editor bindings save every adjustment immediately, without waiting for dismissal")
        expect(!reopenedEditor.custom.rumbleEnabled && reopenedEditor.custom.rumble.intensityStart == 0.24, "Disabled rumble settings survive closing and reopening the editor")
        let lastSaved = UserDefaults.standard.data(forKey: FFCustomSlideHaptics.storageKey)
        editor.simulateEncodingFailure()
        expect(editor.saveFailed, "The editor reports a failed save")
        expect(UserDefaults.standard.data(forKey: FFCustomSlideHaptics.storageKey) == lastSaved, "A failed save preserves the previous settings")

        let suiteName = "fitfight-slide-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var custom = FFCustomSlideHaptics()
        custom.rumbleEnabled = false
        custom.rumble.intensityStart = 0.31
        custom.rumble.intensityEnd = 0.77
        custom.rumble.sharpnessStart = 0.2
        custom.rumble.sharpnessEnd = 0.85
        custom.rumble.intensityPower = 3
        custom.rumble.sharpnessPower = 0.5
        custom.ticksEnabled = false
        custom.systemImpacts = true
        custom.impactStyle = .rigid
        custom.timedTicks = false
        custom.tickCount = 9
        custom.startHz = 0.5
        custom.endHz = 60
        custom.movementCount = 0
        custom.tickIntensityStart = 0.15
        custom.tickIntensityEnd = 0.66
        custom.tickSharpnessStart = 0.1
        custom.tickSharpnessEnd = 0.9
        custom.tickPower = 4
        custom.finishEnabled = false
        custom.finish.style = .soft
        custom.finish.intensity = 0.35
        custom.confirmationProgress = 0.6
        try custom.save(to: defaults)
        defaults.set(FFCustomSlideHaptics.recipeID, forKey: FFSlideHapticRecipe.storageKey)
        let reopened = UserDefaults(suiteName: suiteName)!
        let restored = FFCustomSlideHaptics.restore(from: reopened.data(forKey: FFCustomSlideHaptics.storageKey))
        expect(restored == custom, "Every custom parameter, including disabled controls, survives reopening storage")
        expect(reopened.string(forKey: FFSlideHapticRecipe.storageKey) == FFCustomSlideHaptics.recipeID, "The custom selection persists separately")
        defaults.set(FFSlideHapticRecipe.shippedID, forKey: FFSlideHapticRecipe.storageKey)
        expect(FFCustomSlideHaptics.restore(from: defaults.data(forKey: FFCustomSlideHaptics.storageKey)) == custom, "Switching to a preset keeps the custom settings")

        expect(FFCustomSlideHaptics.restore(from: nil) == FFCustomSlideHaptics(), "First launch gets editable defaults")
        expect(FFCustomSlideHaptics.restore(from: Data("broken".utf8)) == FFCustomSlideHaptics(), "Damaged saved JSON cannot reach the engine")
        var invalid = custom
        invalid.confirmationProgress = 0
        expect(FFCustomSlideHaptics.restore(from: try JSONEncoder().encode(invalid)) == FFCustomSlideHaptics(), "Saved confirmation distance cannot divide by zero")
        invalid = custom
        invalid.rumble.intensityEnd = 100
        expect(FFCustomSlideHaptics.restore(from: try JSONEncoder().encode(invalid)) == FFCustomSlideHaptics(), "Saved strength outside the hardware range is rejected")
        invalid = custom
        invalid.tickPower = -1
        expect(FFCustomSlideHaptics.restore(from: try JSONEncoder().encode(invalid)) == FFCustomSlideHaptics(), "Invalid saved ramp powers are rejected")

        custom.finishEnabled = true
        try custom.save(to: defaults)
        let savedControl = SlideControlHarness()
        savedControl.selectedRecipeID = FFCustomSlideHaptics.recipeID
        savedControl.customHapticData = defaults.data(forKey: FFCustomSlideHaptics.storageKey)!
        let savedGesture = savedControl.makeGesture(travel: 100)
        savedGesture.ended?(DragGesture.Value(translation: CGSize(width: 59, height: 0)))
        expect(!savedControl.completed, "The saved custom threshold rejects an incomplete swipe")
        savedGesture.ended?(DragGesture.Value(translation: CGSize(width: 60, height: 0)))
        expect(savedControl.completed, "Slide to start reads the custom confirmation threshold from app storage")
        expect(UIImpactFeedbackGenerator.impacts.last?.style == .soft && abs(UIImpactFeedbackGenerator.impacts.last!.intensity - 0.35) < 0.001, "The saved custom finish works before any drag sample")

        savedControl.resetsAfterSuccess = true
        savedControl.completed = false
        savedControl.selectedRecipeID = FFSlideHapticRecipe.shippedID
        savedControl.accessibleConfirm()
        expect(UIImpactFeedbackGenerator.impacts.last?.style == .heavy, "Returning to a preset restores its finish style")
        savedControl.selectedRecipeID = FFCustomSlideHaptics.recipeID
        custom.finishEnabled = false
        savedControl.customHapticData = try JSONEncoder().encode(custom)
        let beforeSilentFinish = UIImpactFeedbackGenerator.impacts.count
        savedControl.accessibleConfirm()
        expect(UIImpactFeedbackGenerator.impacts.count == beforeSilentFinish, "A disabled custom finish is silent")
        custom.finishEnabled = true
        custom.finish.intensity = 0
        savedControl.customHapticData = try JSONEncoder().encode(custom)
        savedControl.accessibleConfirm()
        expect(UIImpactFeedbackGenerator.impacts.count == beforeSilentFinish, "Zero custom finish strength is silent")

        let engine = FFSlideHapticEngine()
        CHHapticEngine.players = []
        let timed = FFSlideHapticRecipe.named("pulse-heart")
        engine.drag(progress: 0.6, recipe: timed)
        engine.stop()
        let countAfterStop = CHHapticEngine.players.count
        try await Task.sleep(nanoseconds: 40_000_000)
        expect(CHHapticEngine.players.count == countAfterStop, "No scheduled tick after cancellation")

        engine.drag(progress: 0.85, recipe: timed)
        let countBeforeHold = CHHapticEngine.players.count
        try await Task.sleep(nanoseconds: 220_000_000)
        expect(CHHapticEngine.players.count > countBeforeHold, "Timed pulses keep beating while held still")
        engine.drag(progress: 0.5, recipe: FFSlideHapticRecipe.shipped)
        let countAfterSwitch = CHHapticEngine.players.count
        try await Task.sleep(nanoseconds: 120_000_000)
        expect(CHHapticEngine.players.count == countAfterSwitch, "Switching recipes cancels the old pulse clock")
        engine.stop()

        custom = FFCustomSlideHaptics()
        custom.ticksEnabled = false
        custom.confirmationProgress = 0.5
        custom.rumble.intensityEnd = 0.8
        engine.drag(progress: 0.5, recipe: custom.recipe)
        expect(abs(CHHapticEngine.players.last!.intensity - 0.8) < 0.001, "Custom rumble peaks at its chosen confirmation point")
        custom.rumble.intensityEnd = 0.25
        custom.rumble.sharpnessEnd = 0.4
        engine.drag(progress: 0.5, recipe: custom.recipe)
        expect(abs(CHHapticEngine.players.last!.intensity - 0.25) < 0.001 && abs(CHHapticEngine.players.last!.sharpness - 0.4) < 0.001, "Editing the same custom recipe ID updates strength and crispness")
        engine.stop()

        custom.rumbleEnabled = false
        custom.ticksEnabled = true
        custom.movementCount = 0
        let beforeClockOnly = CHHapticEngine.players.count
        engine.drag(progress: 0.5, recipe: custom.recipe)
        expect(CHHapticEngine.players.count == beforeClockOnly, "Clock-only custom pulses do not add movement ticks")
        custom.ticksEnabled = false
        engine.drag(progress: 0.5, recipe: custom.recipe)
        try await Task.sleep(nanoseconds: 40_000_000)
        expect(CHHapticEngine.players.count == beforeClockOnly, "Disabling pulses in the same custom recipe cancels its clock")
        engine.stop()

        custom.ticksEnabled = true
        custom.timedTicks = false
        custom.systemImpacts = true
        custom.tickIntensityEnd = 0.6
        for style in FFSlideHapticRecipe.ImpactStyle.allCases {
            custom.impactStyle = style
            engine.drag(progress: 0.5, recipe: custom.recipe)
            expect(UIImpactFeedbackGenerator.impacts.last?.style == style.feedbackStyle && abs(UIImpactFeedbackGenerator.impacts.last!.intensity - 0.6) < 0.001, "Custom tick style \(style.rawValue) reaches the engine")
        }
        engine.stop()

        CHHapticEngine.supported = false
        UIImpactFeedbackGenerator.impacts = []
        engine.drag(progress: 0.85, recipe: FFSlideHapticRecipe.shipped)
        expect(UIImpactFeedbackGenerator.impacts.last?.intensity == 1, "Existing UIKit fallback reaches full strength")
        engine.stop()

        for failure in failures { print("FAIL: \(failure)") }
        print("\(checks - failures.count)/\(checks) slide haptic checks passed")
        if !failures.isEmpty { exit(1) }
    }
}
