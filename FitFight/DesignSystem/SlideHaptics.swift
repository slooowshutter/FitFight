import CoreHaptics
import Foundation
import UIKit

/// Slide-to-start vibration. Intensity is strength, sharpness is crisp vs dull.
struct FFSlideHapticRecipe: Identifiable, Equatable {
    static let storageKey = "ff.slideHapticRecipe"
    static let shippedID = "ratchet-12"

    let id: String
    let name: String
    let summary: String
    var continuous: Continuous?
    var ticks: Ticks?

    struct Continuous: Equatable {
        var intensityStart: Float
        var intensityEnd: Float
        var sharpnessStart: Float
        var sharpnessEnd: Float
        var intensityPower: Double = 1
        var sharpnessPower: Double = 1
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
    }

    static var shipped: FFSlideHapticRecipe { named(shippedID) }

    static func named(_ id: String) -> FFSlideHapticRecipe {
        all.first { $0.id == id } ?? all[0]
    }

    static let all: [FFSlideHapticRecipe] = [
        ratchet(
            id: shippedID,
            name: "Switch",
            summary: "12 ticks along the track. Intensity 0.40–0.72, sharpness 0.30–0.50. No rumble. Success at the end. Shipped default.",
            count: 12,
            intensity: 0.40...0.72,
            sharpness: 0.30...0.50
        ),
        FFSlideHapticRecipe(
            id: "old-buzz",
            name: "Old buzz",
            summary: "Continuous rumble plus 20–50 Hz ticks. Intensity 0.20–1.00, sharpness 0.08–1.00. This is the one that felt unnatural.",
            continuous: Continuous(
                intensityStart: 0.20,
                intensityEnd: 1.00,
                sharpnessStart: 0.08,
                sharpnessEnd: 1.00,
                intensityPower: 1.15,
                sharpnessPower: 1.55
            ),
            ticks: Ticks(
                kind: .haptic,
                pace: .time(startHz: 20, endHz: 50),
                intensityStart: 0.70,
                intensityEnd: 0.70,
                sharpnessStart: 0.25,
                sharpnessEnd: 1.00
            )
        ),
        ratchet(
            id: "ratchet-8",
            name: "Sparse switch",
            summary: "8 ticks. Intensity 0.38–0.70, sharpness 0.28–0.48. Chunkier, fewer hits.",
            count: 8,
            intensity: 0.38...0.70,
            sharpness: 0.28...0.48
        ),
        ratchet(
            id: "ratchet-20",
            name: "Fine switch",
            summary: "20 ticks. Intensity 0.36–0.68, sharpness 0.28–0.48. Denser track.",
            count: 20,
            intensity: 0.36...0.68,
            sharpness: 0.28...0.48
        ),
        ratchet(
            id: "ratchet-32",
            name: "Texture",
            summary: "32 ticks. Intensity 0.32–0.62, sharpness 0.22–0.42. Almost a grain, not a click.",
            count: 32,
            intensity: 0.32...0.62,
            sharpness: 0.22...0.42
        ),
        ratchet(
            id: "ratchet-soft",
            name: "Soft switch",
            summary: "12 ticks. Intensity 0.22–0.48, sharpness 0.12–0.28. Quiet and rounded.",
            count: 12,
            intensity: 0.22...0.48,
            sharpness: 0.12...0.28
        ),
        ratchet(
            id: "ratchet-hard",
            name: "Hard switch",
            summary: "12 ticks. Intensity 0.58–0.95, sharpness 0.55–0.90. Strong and crisp.",
            count: 12,
            intensity: 0.58...0.95,
            sharpness: 0.55...0.90
        ),
        ratchet(
            id: "ratchet-rise",
            name: "Quiet then firm",
            summary: "16 ticks. Intensity 0.12–0.80, sharpness 0.18–0.62. Starts almost silent.",
            count: 16,
            intensity: 0.12...0.80,
            sharpness: 0.18...0.62
        ),
        FFSlideHapticRecipe(
            id: "engine-soft",
            name: "Soft rumble",
            summary: "Continuous only. Intensity 0.18–0.42, sharpness 0.08–0.20. No ticks.",
            continuous: Continuous(
                intensityStart: 0.18,
                intensityEnd: 0.42,
                sharpnessStart: 0.08,
                sharpnessEnd: 0.20
            )
        ),
        FFSlideHapticRecipe(
            id: "engine-build",
            name: "Building rumble",
            summary: "Continuous only. Intensity 0.12–0.78, sharpness 0.10–0.55, power 1.4. No ticks.",
            continuous: Continuous(
                intensityStart: 0.12,
                intensityEnd: 0.78,
                sharpnessStart: 0.10,
                sharpnessEnd: 0.55,
                intensityPower: 1.4,
                sharpnessPower: 1.4
            )
        ),
        FFSlideHapticRecipe(
            id: "engine-sharp",
            name: "Sharp rumble",
            summary: "Continuous only. Intensity 0.28–0.70, sharpness 0.55–0.95. Buzzy, not dull.",
            continuous: Continuous(
                intensityStart: 0.28,
                intensityEnd: 0.70,
                sharpnessStart: 0.55,
                sharpnessEnd: 0.95
            )
        ),
        FFSlideHapticRecipe(
            id: "pulse-slow",
            name: "Slow pulses",
            summary: "Time ticks 4–10 Hz. Intensity 0.45–0.75, sharpness 0.30–0.50. No rumble.",
            ticks: Ticks(
                kind: .haptic,
                pace: .time(startHz: 4, endHz: 10),
                intensityStart: 0.45,
                intensityEnd: 0.75,
                sharpnessStart: 0.30,
                sharpnessEnd: 0.50
            )
        ),
        FFSlideHapticRecipe(
            id: "pulse-heart",
            name: "Heartbeat",
            summary: "Time ticks 1.2–2.6 Hz. Intensity 0.50–0.82, sharpness 0.22–0.40. Slow thumps.",
            ticks: Ticks(
                kind: .haptic,
                pace: .time(startHz: 1.2, endHz: 2.6),
                intensityStart: 0.50,
                intensityEnd: 0.82,
                sharpnessStart: 0.22,
                sharpnessEnd: 0.40
            )
        ),
        FFSlideHapticRecipe(
            id: "pulse-metro",
            name: "Metronome",
            summary: "Steady 8 Hz ticks. Intensity 0.42, sharpness 0.35. Does not speed up.",
            ticks: Ticks(
                kind: .haptic,
                pace: .time(startHz: 8, endHz: 8),
                intensityStart: 0.42,
                intensityEnd: 0.42,
                sharpnessStart: 0.35,
                sharpnessEnd: 0.35
            )
        ),
        ratchet(
            id: "ui-select",
            name: "iOS selection",
            summary: "10 UIKit selection-style light impacts along the track. Intensity 0.40–0.70.",
            count: 10,
            intensity: 0.40...0.70,
            sharpness: 0.40...0.40,
            kind: .impact(.light)
        ),
        ratchet(
            id: "ui-heavy",
            name: "Heavy taps",
            summary: "8 UIKit heavy impacts. Intensity 0.55–0.90. Thud, not click.",
            count: 8,
            intensity: 0.55...0.90,
            sharpness: 0.50...0.50,
            kind: .impact(.heavy)
        ),
        ratchet(
            id: "ui-light",
            name: "Light taps",
            summary: "16 UIKit light impacts. Intensity 0.30–0.60. Soft ticks.",
            count: 16,
            intensity: 0.30...0.60,
            sharpness: 0.30...0.30,
            kind: .impact(.light)
        ),
        FFSlideHapticRecipe(
            id: "combo-mild",
            name: "Soft rumble + ticks",
            summary: "Low rumble (0.12–0.32) plus 10 track ticks (0.35–0.65). Milder mix than Old buzz.",
            continuous: Continuous(
                intensityStart: 0.12,
                intensityEnd: 0.32,
                sharpnessStart: 0.08,
                sharpnessEnd: 0.22
            ),
            ticks: Ticks(
                kind: .haptic,
                pace: .distance(count: 10),
                intensityStart: 0.35,
                intensityEnd: 0.65,
                sharpnessStart: 0.28,
                sharpnessEnd: 0.48
            )
        ),
        FFSlideHapticRecipe(
            id: "silent-hit",
            name: "Silence then hit",
            summary: "No drag vibration. Success notification only when you reach the end."
        ),
        FFSlideHapticRecipe(
            id: "crescendo",
            name: "Crescendo ticks",
            summary: "Time ticks 6–18 Hz. Intensity 0.28–0.88, sharpness 0.20–0.70. Speeds up, no rumble.",
            ticks: Ticks(
                kind: .haptic,
                pace: .time(startHz: 6, endHz: 18),
                intensityStart: 0.28,
                intensityEnd: 0.88,
                sharpnessStart: 0.20,
                sharpnessEnd: 0.70
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
        kind: Ticks.Kind = .haptic
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
                sharpnessEnd: sharpness.upperBound
            )
        )
    }
}

/// Plays a recipe while the thumb is down. Distance ticks follow the track; time ticks keep beating if you hold still.
@MainActor
final class FFSlideHapticEngine {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var pulse = UIImpactFeedbackGenerator(style: .medium)
    private var recipe = FFSlideHapticRecipe.shipped
    private var progress: CGFloat = 0
    private var loop: Task<Void, Never>?
    private var lastPulse = Date.distantPast
    private var lastTickIndex = -1
    private var started = false

    func drag(progress: CGFloat, recipe: FFSlideHapticRecipe) {
        if recipe.id != self.recipe.id {
            stop()
            self.recipe = recipe
        }
        self.progress = min(max(progress, 0), 1)
        startIfNeeded()
        updateContinuous()
        if let ticks = recipe.ticks, case .distance(let count) = ticks.pace {
            fireDistanceTick(count: count)
        }
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

        let wantsHapticTicks: Bool
        if let ticks, case .haptic = ticks.kind {
            wantsHapticTicks = true
        } else {
            wantsHapticTicks = false
        }
        let wantsEngine = recipe.continuous != nil || wantsHapticTicks
        if wantsEngine, CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            if let continuous = recipe.continuous, let startedEngine = try? makeContinuousPlayer(continuous) {
                engine = startedEngine.engine
                player = startedEngine.player
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

    private func makeContinuousPlayer(_ continuous: FFSlideHapticRecipe.Continuous) throws -> (engine: CHHapticEngine, player: CHHapticAdvancedPatternPlayer) {
        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        try engine.start()
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: continuous.intensityStart),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: continuous.sharpnessStart),
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
        let index = Int(progress * CGFloat(count + 1))
        guard index != lastTickIndex else { return }
        let inBand = { (value: Int) in (1...count).contains(value) }
        if inBand(index) || inBand(lastTickIndex) {
            playTick()
        }
        lastTickIndex = index
    }

    private func tick() {
        guard let ticks = recipe.ticks, case .time(let startHz, let endHz) = ticks.pace, startHz > 0, endHz > 0 else { return }
        let hz = startHz * pow(endHz / startHz, Double(progress))
        guard Date().timeIntervalSince(lastPulse) >= 1 / hz else { return }
        lastPulse = Date()
        playTick()
    }

    private func playTick() {
        guard let ticks = recipe.ticks else { return }
        let t = Double(progress)
        let intensity = lerp(ticks.intensityStart, ticks.intensityEnd, t)
        let sharpness = lerp(ticks.sharpnessStart, ticks.sharpnessEnd, t)
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
