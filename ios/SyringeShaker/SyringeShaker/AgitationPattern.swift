import CoreHaptics
import Foundation

/// The vibration recipes the app can drive through the Taptic Engine.
///
/// Design notes — why these patterns look the way they do:
///
/// The Taptic Engine is a linear resonant actuator (LRA). It has one mechanical
/// resonance and a fairly narrow usable band around it, so "louder" is mostly a
/// question of driving intensity to 1.0 and keeping it there. That gets you
/// energy, but energy alone is a poor way to redisperse a settled suspension:
///
///   * A *constant* single-frequency drive lets the fluid settle into a
///     standing-wave pattern. Crystals migrate to the velocity nodes and simply
///     sit there — you get vibration without much net mixing.
///   * Caked sediment at the bottom of a barrel needs a *shock* to break its
///     static friction with the glass. A smooth sine never delivers one.
///
/// So `resuspend`, the default, deliberately does three things at once:
///   1. Holds base intensity at maximum for raw energy transfer.
///   2. Sweeps sharpness (which shifts the LRA's spectral content) and
///      amplitude-modulates at a few Hz, so no standing-wave pattern has time
///      to establish and the excitation keeps wandering across the fluid's own
///      resonances.
///   3. Fires hard transients on top of the continuous bed — impulse shocks
///      that dislodge crystals caked against the wall.
///
/// This is engineering judgement about LRAs and suspensions, not a validated
/// clinical protocol. Treat it as an aid to hand agitation, not a replacement.
enum AgitationPattern: String, CaseIterable, Identifiable {
    /// Sweeping, amplitude-modulated drive with impulse shocks. The default.
    case resuspend
    /// Flat, unmodulated maximum-intensity drive. Smoothest in the hand.
    case continuousMax
    /// Pure hard transients. Highest peak impulse, for stubborn caked sediment.
    case percussive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resuspend:     return "Resuspend"
        case .continuousMax: return "Smooth"
        case .percussive:    return "Percussive"
        }
    }

    var subtitle: String {
        switch self {
        case .resuspend:     return "Sweep + impulse shocks. Best all-round."
        case .continuousMax: return "Flat max drive. Quietest in the hand."
        case .percussive:    return "Hard taps only. For caked sediment."
        }
    }

    /// Length of one loop of the pattern, in seconds. The player repeats this
    /// seamlessly, so every curve below must start and end at the same value or
    /// you hear (and feel) a click at the seam.
    var loopPeriod: TimeInterval {
        switch self {
        case .resuspend:     return 1.5
        case .continuousMax: return 1.0
        case .percussive:    return 1.0
        }
    }

    func makePattern() throws -> CHHapticPattern {
        switch self {
        case .resuspend:     return try Self.makeResuspendPattern()
        case .continuousMax: return try Self.makeContinuousPattern()
        case .percussive:    return try Self.makePercussivePattern()
        }
    }

    // MARK: - Builders

    private static func makeResuspendPattern() throws -> CHHapticPattern {
        let period = AgitationPattern.resuspend.loopPeriod

        // Continuous bed at full intensity. Base sharpness sits mid-range so the
        // sharpness *control* curve below has headroom to swing both ways.
        let bed = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: 0,
            duration: period
        )

        // Impulse shocks at 4 Hz, full intensity and maximum sharpness for the
        // steepest attack the engine will give us.
        let shockInterval: TimeInterval = 0.25
        var events: [CHHapticEvent] = [bed]
        var t: TimeInterval = 0
        while t < period - 0.001 {
            events.append(
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                    ],
                    relativeTime: t
                )
            )
            t += shockInterval
        }

        // Amplitude modulation, to keep breaking up standing waves. It never
        // drops below 0.56 — the point is to disrupt the fluid's steady state,
        // not to stop driving it.
        //
        // `cycles(of:over:)` snaps the rate to a whole number of cycles per
        // loop, which is what keeps the seam silent; the effective rate is
        // therefore close to the requested 2 Hz rather than exactly it.
        let amCycles = cycles(of: 2.0, over: period)
        let amplitude = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: rampPoints(
                over: period,
                samples: 24,
                value: { phase in 0.78 + 0.22 * sin(2 * Double.pi * amCycles * phase) }
            ),
            relativeTime: 0
        )

        // Sharpness sweep across the full ±0.5 range available on top of the
        // base 0.5, i.e. an effective 0.0 → 1.0 sweep of spectral content, once
        // per loop. Returns to its starting value so the loop seam is clean.
        let sweep = CHHapticParameterCurve(
            parameterID: .hapticSharpnessControl,
            controlPoints: rampPoints(
                over: period,
                samples: 24,
                value: { phase in -0.5 * cos(2 * Double.pi * phase) }
            ),
            relativeTime: 0
        )

        return try CHHapticPattern(events: events, parameterCurves: [amplitude, sweep])
    }

    private static func makeContinuousPattern() throws -> CHHapticPattern {
        let period = AgitationPattern.continuousMax.loopPeriod
        let bed = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ],
            relativeTime: 0,
            duration: period
        )
        return try CHHapticPattern(events: [bed], parameterCurves: [])
    }

    private static func makePercussivePattern() throws -> CHHapticPattern {
        let period = AgitationPattern.percussive.loopPeriod
        // 8 Hz of hard taps. Nothing underneath — all the energy goes into peaks.
        let interval: TimeInterval = 0.125
        var events: [CHHapticEvent] = []
        var t: TimeInterval = 0
        while t < period - 0.001 {
            events.append(
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                    ],
                    relativeTime: t
                )
            )
            t += interval
        }
        return try CHHapticPattern(events: events, parameterCurves: [])
    }

    /// Whole number of modulation cycles closest to `hz` over one `period`.
    ///
    /// A curve that doesn't complete an integer number of cycles per loop ends
    /// at a different value than it started, and the player's loop seam then
    /// produces an audible, palpable click once per period. Snapping to an
    /// integer trades an exact modulation rate for a silent seam.
    private static func cycles(of hz: Double, over period: TimeInterval) -> Double {
        max(1, (hz * period).rounded())
    }

    /// Samples `value` evenly over `period`. `phase` runs 0...1 across the loop.
    private static func rampPoints(
        over period: TimeInterval,
        samples: Int,
        value: (Double) -> Double
    ) -> [CHHapticParameterCurve.ControlPoint] {
        (0...samples).map { i in
            let phase = Double(i) / Double(samples)
            return CHHapticParameterCurve.ControlPoint(
                relativeTime: phase * period,
                value: Float(value(phase))
            )
        }
    }
}
