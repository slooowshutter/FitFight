import CoreHaptics
import Foundation
import UIKit

/// Slide-to-start vibration. Recipes use Core Haptics' 0...1 range; the lab displays 0-100.
struct FFSlideHapticRecipe: Identifiable, Equatable {
    static let storageKey = "ff.slideHapticRecipe"
    static let shippedID = "ratchet-12"

    let id: String
    let name: String
    let summary: String
    var continuous: Continuous?
    var ticks: Ticks?
    var finish: Finish? = Finish()
    var confirmationProgress: CGFloat = 0.85

    struct Continuous: Codable, Equatable {
        var intensityStart: Float
        var intensityEnd: Float
        var sharpnessStart: Float
        var sharpnessEnd: Float
        var intensityPower: Double = 1
        var sharpnessPower: Double = 1
    }

    enum ImpactStyle: String, Codable, CaseIterable {
        case soft, light, medium, rigid, heavy

        var feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .soft: return .soft
            case .light: return .light
            case .medium: return .medium
            case .rigid: return .rigid
            case .heavy: return .heavy
            }
        }
    }

    struct Finish: Codable, Equatable {
        var style: ImpactStyle = .heavy
        var intensity: Float = 1
    }

    struct Ticks: Equatable {
        enum Kind: Equatable {
            case haptic
            case impact(UIImpactFeedbackGenerator.FeedbackStyle)
        }

        enum Pace: Equatable {
            case distance(count: Int)
            case time(startHz: Double, endHz: Double)
        }

        var kind: Kind
        var pace: Pace
        var intensityStart: Float
        var intensityEnd: Float
        var sharpnessStart: Float = 0.4
        var sharpnessEnd: Float = 0.4
        var power: Double = 1
        var movementCount: Int = 20
    }

    static var shipped: FFSlideHapticRecipe { named(shippedID) }

    static func named(_ id: String) -> FFSlideHapticRecipe {
        all.first { $0.id == id } ?? all[0]
    }

    static let all: [FFSlideHapticRecipe] = [
        ratchet(
            id: shippedID,
            name: "Switch",
            summary: "12 track ticks. Strength 5-100, crispness 0-100. A soft start that builds to a hard finish. Default.",
            count: 12,
            intensity: 0.05...1.00,
            sharpness: 0.00...1.00
        ),
        FFSlideHapticRecipe(
            id: "old-buzz",
            name: "Ignition",
            summary: "Rumble 0-100 plus pulses accelerating from 2 to 60 per second. Crispness 0-100. A full-throttle finish.",
            continuous: Continuous(
                intensityStart: 0.00,
                intensityEnd: 1.00,
                sharpnessStart: 0.00,
                sharpnessEnd: 1.00,
                intensityPower: 0.7,
                sharpnessPower: 1.5
            ),
            ticks: Ticks(
                kind: .haptic,
                pace: .time(startHz: 2, endHz: 60),
                intensityStart: 0.05,
                intensityEnd: 1.00,
                sharpnessStart: 0.00,
                sharpnessEnd: 1.00
            )
        ),
        ratchet(
            id: "ratchet-8",
            name: "Sparse switch",
            summary: "8 chunky track ticks. Strength 5-100, crispness 0-100. Widely spaced knocks that get heavy.",
            count: 8,
            intensity: 0.05...1.00,
            sharpness: 0.00...1.00
        ),
        ratchet(
            id: "ratchet-20",
            name: "Fine switch",
            summary: "20 track ticks. Strength 0-100, crispness 0-100. A dense ramp that gets strong early.",
            count: 20,
            intensity: 0.00...1.00,
            sharpness: 0.00...1.00,
            power: 0.7
        ),
        ratchet(
            id: "ratchet-32",
            name: "Texture",
            summary: "32 track ticks. Strength 0-100, crispness 0-100. Fine grain turns into a harsh texture.",
            count: 32,
            intensity: 0.00...1.00,
            sharpness: 0.00...1.00,
            power: 1.5
        ),
        ratchet(
            id: "ratchet-soft",
            name: "Soft then slam",
            summary: "12 track ticks. Strength 0-100, crispness 0-100. Stays soft through the middle, then hits hard.",
            count: 12,
            intensity: 0.00...1.00,
            sharpness: 0.00...1.00,
            power: 2.5
        ),
        ratchet(
            id: "ratchet-hard",
            name: "Hard switch",
            summary: "12 track ticks. Strength 15-100, crispness 10-100. Gets aggressive soon after you start.",
            count: 12,
            intensity: 0.15...1.00,
            sharpness: 0.10...1.00,
            power: 0.5
        ),
        ratchet(
            id: "ratchet-rise",
            name: "Quiet then firm",
            summary: "16 track ticks. Strength 0-100, crispness 0-100. Almost silent at first, with a steep final climb.",
            count: 16,
            intensity: 0.00...1.00,
            sharpness: 0.00...1.00,
            power: 2
        ),
        FFSlideHapticRecipe(
            id: "engine-soft",
            name: "Deep rumble",
            summary: "Continuous strength 0-100, crispness 0-60. A deep vibration that swells early. No ticks.",
            continuous: Continuous(
                intensityStart: 0.00,
                intensityEnd: 1.00,
                sharpnessStart: 0.00,
                sharpnessEnd: 0.60,
                intensityPower: 0.65
            )
        ),
        FFSlideHapticRecipe(
            id: "engine-build",
            name: "Building rumble",
            summary: "Continuous strength 0-100, crispness 0-100. A gentle opening with a powerful second half. No ticks.",
            continuous: Continuous(
                intensityStart: 0.00,
                intensityEnd: 1.00,
                sharpnessStart: 0.00,
                sharpnessEnd: 1.00,
                intensityPower: 2,
                sharpnessPower: 2
            )
        ),
        FFSlideHapticRecipe(
            id: "engine-sharp",
            name: "Sharp rumble",
            summary: "Continuous strength 5-100, crispness 0-100. Turns sharp early and buzzes hard at the end. No ticks.",
            continuous: Continuous(
                intensityStart: 0.05,
                intensityEnd: 1.00,
                sharpnessStart: 0.00,
                sharpnessEnd: 1.00,
                intensityPower: 0.8,
                sharpnessPower: 0.5
            )
        ),
        FFSlideHapticRecipe(
            id: "pulse-slow",
            name: "Slow pulses",
            summary: "Pulses accelerate from 1 to 30 per second. Strength 5-100, crispness 0-100. Slow knocks become a rapid rattle.",
            ticks: Ticks(
                kind: .haptic,
                pace: .time(startHz: 1, endHz: 30),
                intensityStart: 0.05,
                intensityEnd: 1.00,
                sharpnessStart: 0.00,
                sharpnessEnd: 1.00
            )
        ),
        FFSlideHapticRecipe(
            id: "pulse-heart",
            name: "Heartbeat",
            summary: "Pulses accelerate from 1 to 12 per second. Strength 10-100, crispness 0-70. Slow thumps turn into pounding.",
            ticks: Ticks(
                kind: .haptic,
                pace: .time(startHz: 1, endHz: 12),
                intensityStart: 0.10,
                intensityEnd: 1.00,
                sharpnessStart: 0.00,
                sharpnessEnd: 0.70
            )
        ),
        FFSlideHapticRecipe(
            id: "pulse-metro",
            name: "Metronome",
            summary: "Steady 12 pulses per second while held. Strength 0-100, crispness 0-100. Same rhythm, much harder hits.",
            ticks: Ticks(
                kind: .haptic,
                pace: .time(startHz: 12, endHz: 12),
                intensityStart: 0.00,
                intensityEnd: 1.00,
                sharpnessStart: 0.00,
                sharpnessEnd: 1.00,
                power: 1.5
            )
        ),
        ratchet(
            id: "ui-select",
            name: "Crisp taps",
            summary: "10 light-style track impacts. Strength 5-100. Crisp taps build quickly, with a heavy finish.",
            count: 10,
            intensity: 0.05...1.00,
            sharpness: 0.00...1.00,
            kind: .impact(.light),
            power: 0.7
        ),
        ratchet(
            id: "ui-heavy",
            name: "Heavy taps",
            summary: "8 heavy-style track impacts. Strength 10-100. Deep thuds ramp up to a slam.",
            count: 8,
            intensity: 0.10...1.00,
            sharpness: 0.00...1.00,
            kind: .impact(.heavy)
        ),
        ratchet(
            id: "ui-light",
            name: "Light then heavy",
            summary: "16 light-style track impacts. Strength 0-100. Soft at first, then a steep rise and a heavy finish.",
            count: 16,
            intensity: 0.00...1.00,
            sharpness: 0.00...1.00,
            kind: .impact(.light),
            power: 2
        ),
        FFSlideHapticRecipe(
            id: "combo-mild",
            name: "Rumble + hammer",
            summary: "Continuous rumble 0-100 plus 10 track knocks at strength 5-100. A deep build with a hard edge.",
            continuous: Continuous(
                intensityStart: 0.00,
                intensityEnd: 1.00,
                sharpnessStart: 0.00,
                sharpnessEnd: 0.70,
                intensityPower: 1.5
            ),
            ticks: Ticks(
                kind: .haptic,
                pace: .distance(count: 10),
                intensityStart: 0.05,
                intensityEnd: 1.00,
                sharpnessStart: 0.00,
                sharpnessEnd: 1.00
            )
        ),
        FFSlideHapticRecipe(
            id: "silent-hit",
            name: "Late detonation",
            summary: "Continuous strength 0-100, crispness 0-100. Almost silent until the final stretch, then full power.",
            continuous: Continuous(
                intensityStart: 0.00,
                intensityEnd: 1.00,
                sharpnessStart: 0.00,
                sharpnessEnd: 1.00,
                intensityPower: 4,
                sharpnessPower: 3
            )
        ),
        FFSlideHapticRecipe(
            id: "crescendo",
            name: "Crescendo ticks",
            summary: "Pulses accelerate from 2 to 50 per second. Strength 0-100, crispness 0-100. A steep climb into a fierce buzz.",
            ticks: Ticks(
                kind: .haptic,
                pace: .time(startHz: 2, endHz: 50),
                intensityStart: 0.00,
                intensityEnd: 1.00,
                sharpnessStart: 0.00,
                sharpnessEnd: 1.00,
                power: 2
            )
        ),
    ]

    private static func ratchet(
        id: String,
        name: String,
        summary: String,
        count: Int,
        intensity: ClosedRange<Float>,
        sharpness: ClosedRange<Float>,
        kind: Ticks.Kind = .haptic,
        power: Double = 1
    ) -> FFSlideHapticRecipe {
        FFSlideHapticRecipe(
            id: id,
            name: name,
            summary: summary,
            ticks: Ticks(
                kind: kind,
                pace: .distance(count: count),
                intensityStart: intensity.lowerBound,
                intensityEnd: intensity.upperBound,
                sharpnessStart: sharpness.lowerBound,
                sharpnessEnd: sharpness.upperBound,
                power: power
            )
        )
    }
}

/// One editable recipe, persisted separately from the selected preset on this phone.
struct FFCustomSlideHaptics: Codable, Equatable {
    static let storageKey = "ff.customSlideHaptics.v1"
    static let recipeID = "custom"

    var rumbleEnabled = true
    var rumble = FFSlideHapticRecipe.Continuous(
        intensityStart: 0,
        intensityEnd: 1,
        sharpnessStart: 0,
        sharpnessEnd: 1,
        intensityPower: 2,
        sharpnessPower: 2
    )
    var ticksEnabled = true
    var systemImpacts = false
    var impactStyle: FFSlideHapticRecipe.ImpactStyle = .heavy
    var timedTicks = true
    var tickCount = 20
    var startHz: Double = 1
    var endHz: Double = 50
    var movementCount = 20
    var tickIntensityStart: Float = 0
    var tickIntensityEnd: Float = 1
    var tickSharpnessStart: Float = 0
    var tickSharpnessEnd: Float = 1
    var tickPower: Double = 2
    var finishEnabled = true
    var finish = FFSlideHapticRecipe.Finish()
    var confirmationProgress: Double = 0.85

    var recipe: FFSlideHapticRecipe {
        FFSlideHapticRecipe(
            id: Self.recipeID,
            name: "Custom",
            summary: "Your saved haptic settings.",
            continuous: rumbleEnabled ? rumble : nil,
            ticks: ticksEnabled ? FFSlideHapticRecipe.Ticks(
                kind: systemImpacts ? .impact(impactStyle.feedbackStyle) : .haptic,
                pace: timedTicks ? .time(startHz: startHz, endHz: endHz) : .distance(count: tickCount),
                intensityStart: tickIntensityStart,
                intensityEnd: tickIntensityEnd,
                sharpnessStart: tickSharpnessStart,
                sharpnessEnd: tickSharpnessEnd,
                power: tickPower,
                movementCount: movementCount
            ) : nil,
            finish: finishEnabled ? finish : nil,
            confirmationProgress: CGFloat(confirmationProgress)
        )
    }

    static func restore(from data: Data?) -> FFCustomSlideHaptics {
        guard let data, let saved = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        // Saved values are a boundary: reject invalid ranges before constructing
        // haptic parameters or dividing by the confirmation distance.
        let levels = [
            saved.rumble.intensityStart, saved.rumble.intensityEnd,
            saved.rumble.sharpnessStart, saved.rumble.sharpnessEnd,
            saved.tickIntensityStart, saved.tickIntensityEnd,
            saved.tickSharpnessStart, saved.tickSharpnessEnd, saved.finish.intensity,
        ]
        let powers = [saved.rumble.intensityPower, saved.rumble.sharpnessPower, saved.tickPower]
        guard levels.allSatisfy({ (0...1).contains($0) }),
              powers.allSatisfy({ (0.25...4).contains($0) }),
              (1...64).contains(saved.tickCount), (0...64).contains(saved.movementCount),
              (0.5...60).contains(saved.startHz), (0.5...60).contains(saved.endHz),
              (0.5...1).contains(saved.confirmationProgress)
        else { return Self() }
        return saved
    }

    func save(to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: Self.storageKey)
    }
}

/// Time ticks also follow movement so a quick swipe cannot outrun the pulse clock.
@MainActor
final class FFSlideHapticEngine {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var pulse = UIImpactFeedbackGenerator(style: .medium)
    private var finishImpact = UIImpactFeedbackGenerator(style: .heavy)
    private var recipe = FFSlideHapticRecipe.shipped
    private var progress: CGFloat = 0
    private var loop: Task<Void, Never>?
    private var lastPulse = Date.distantPast
    private var lastTickIndex = -1
    private var started = false

    func drag(progress: CGFloat, recipe: FFSlideHapticRecipe) {
        if recipe != self.recipe {
            stop()
            self.recipe = recipe
        }
        self.progress = min(max(progress / recipe.confirmationProgress, 0), 1)
        startIfNeeded()
        updateContinuous()
        if let ticks = recipe.ticks {
            switch ticks.pace {
            case .distance(let count):
                fireDistanceTick(count: count)
            case .time:
                fireDistanceTick(count: ticks.movementCount)
            }
        }
    }

    func finish(recipe: FFSlideHapticRecipe) {
        guard let finish = recipe.finish, finish.intensity > 0 else { return }
        // Accessible confirmation can happen without a preceding drag.
        if recipe.finish != self.recipe.finish {
            finishImpact = UIImpactFeedbackGenerator(style: finish.style.feedbackStyle)
        }
        self.recipe = recipe
        finishImpact.impactOccurred(intensity: CGFloat(finish.intensity))
    }

    func stop() {
        loop?.cancel()
        loop = nil
        lastPulse = .distantPast
        lastTickIndex = -1
        started = false
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        engine?.stop(completionHandler: { _ in })
        engine = nil
        progress = 0
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        let ticks = recipe.ticks
        if let ticks, case .impact(let style) = ticks.kind {
            pulse = UIImpactFeedbackGenerator(style: style)
        }
        pulse.prepare()
        if let finish = recipe.finish {
            finishImpact = UIImpactFeedbackGenerator(style: finish.style.feedbackStyle)
        }
        finishImpact.prepare()

        let wantsHapticTicks: Bool
        if let ticks, case .haptic = ticks.kind {
            wantsHapticTicks = true
        } else {
            wantsHapticTicks = false
        }
        let wantsEngine = recipe.continuous != nil || wantsHapticTicks
        if wantsEngine, CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            if recipe.continuous != nil, let startedEngine = try? makeContinuousPlayer() {
                engine = startedEngine.engine
                player = startedEngine.player
                updateContinuous()
                try? player?.start(atTime: CHHapticTimeImmediate)
            } else if wantsHapticTicks {
                engine = try? makeTickEngine()
            }
        }

        if let ticks, case .time = ticks.pace {
            loop = Task { @MainActor [weak self] in
                while let engine = self, !Task.isCancelled {
                    engine.tick()
                    do {
                        try await Task.sleep(nanoseconds: 8_000_000)
                    } catch {
                        return
                    }
                }
            }
        }
    }

    private func makeTickEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        try engine.start()
        return engine
    }

    private func makeContinuousPlayer() throws -> (engine: CHHapticEngine, player: CHHapticAdvancedPatternPlayer) {
        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        try engine.start()
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                // Intensity control multiplies; sharpness control adds. Neutral
                // bases let the ramp reach full power without doubling sharpness.
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0),
            ],
            relativeTime: 0,
            duration: 60
        )
        let pattern = try CHHapticPattern(events: [event], parameters: [])
        return (engine, try engine.makeAdvancedPlayer(with: pattern))
    }

    private func updateContinuous() {
        guard let player, let continuous = recipe.continuous else { return }
        let t = Double(progress)
        let params = [
            CHHapticDynamicParameter(
                parameterID: .hapticIntensityControl,
                value: lerp(continuous.intensityStart, continuous.intensityEnd, t, power: continuous.intensityPower),
                relativeTime: 0
            ),
            CHHapticDynamicParameter(
                parameterID: .hapticSharpnessControl,
                value: lerp(continuous.sharpnessStart, continuous.sharpnessEnd, t, power: continuous.sharpnessPower),
                relativeTime: 0
            ),
        ]
        try? player.sendParameters(params, atTime: CHHapticTimeImmediate)
    }

    private func fireDistanceTick(count: Int) {
        guard count > 0 else { return }
        // The last notch lands exactly at confirmation, at full strength.
        let index = Int(progress * CGFloat(count))
        guard index != lastTickIndex else { return }
        if (1...count).contains(index) || (1...count).contains(lastTickIndex) {
            playTick()
        }
        lastTickIndex = index
    }

    private func tick() {
        guard let ticks = recipe.ticks, case .time(let startHz, let endHz) = ticks.pace, startHz > 0, endHz > 0 else { return }
        let hz = startHz * pow(endHz / startHz, Double(progress))
        guard Date().timeIntervalSince(lastPulse) >= 1 / hz else { return }
        playTick()
    }

    private func playTick() {
        guard let ticks = recipe.ticks else { return }
        lastPulse = Date()
        let t = Double(progress)
        let intensity = lerp(ticks.intensityStart, ticks.intensityEnd, t, power: ticks.power)
        let sharpness = lerp(ticks.sharpnessStart, ticks.sharpnessEnd, t, power: ticks.power)
        guard intensity > 0 else { return }
        switch ticks.kind {
        case .impact:
            pulse.impactOccurred(intensity: CGFloat(intensity))
            pulse.prepare()
        case .haptic:
            if let engine {
                playHapticTick(on: engine, intensity: intensity, sharpness: sharpness)
            } else {
                pulse.impactOccurred(intensity: CGFloat(intensity))
                pulse.prepare()
            }
        }
    }

    private func playHapticTick(on engine: CHHapticEngine, intensity: Float, sharpness: Float) {
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: 0
        )
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let click = try? engine.makePlayer(with: pattern)
        else { return }
        try? click.start(atTime: CHHapticTimeImmediate)
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Double, power: Double = 1) -> Float {
        a + (b - a) * Float(pow(min(max(t, 0), 1), power))
    }
}
