import Combine
import CoreHaptics
import Foundation
import UIKit

/// Owns the Taptic Engine and drives an `AgitationPattern` on it as a seamless
/// loop for a fixed duration.
@MainActor
final class HapticAgitator: ObservableObject {

    enum Readiness: Equatable {
        case ready
        /// Device has no Taptic Engine, or haptics are unavailable to apps.
        case unsupported
        /// Low Power Mode silences the Taptic Engine system-wide. Nothing the
        /// app can do about it, but the user needs to know why it feels dead.
        case lowPowerMode
        case failed(String)
    }

    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var readiness: Readiness = .ready

    /// How long a single press runs for, in seconds.
    @Published var duration: TimeInterval = 20 {
        didSet { if !isRunning { remaining = duration } }
    }

    @Published var pattern: AgitationPattern = .resuspend {
        didSet {
            guard oldValue != pattern else { return }
            // Swap patterns live so the user can feel the difference without
            // stopping and restarting.
            if isRunning { restartPlayer() }
        }
    }

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var ticker: Timer?
    private var endsAt: Date?
    private var observers: [NSObjectProtocol] = []

    /// Fraction of the run still to go, 1 → 0. Drives the progress ring.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, remaining / duration))
    }

    init() {
        remaining = duration
        observePowerState()
    }

    // MARK: - Lifecycle

    func prepare() {
        // `.onAppear` can fire more than once; don't orphan a live engine.
        guard engine == nil else {
            refreshPowerState()
            return
        }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            readiness = .unsupported
            return
        }
        refreshPowerState()

        do {
            let engine = try CHHapticEngine()
            // Haptics must fire regardless of the ring/silent switch and without
            // us claiming the audio session away from whatever else is playing.
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false

            // The system stops the engine on interruptions (calls, Siri, the app
            // going to the background). If we still think we're running, bring it
            // back and pick the loop up where it left off.
            engine.stoppedHandler = { [weak self] reason in
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    if reason == .audioSessionInterrupt || reason == .applicationSuspended {
                        self.stop()
                    } else {
                        self.restartEngineAndPlayer()
                    }
                }
            }

            // Fired when the engine recovers from a server-side reset; every
            // player built from the old engine is dead and must be rebuilt.
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    self.restartEngineAndPlayer()
                }
            }

            try engine.start()
            self.engine = engine
        } catch {
            readiness = .failed(error.localizedDescription)
        }
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !isRunning else { return }
        refreshPowerState()
        if engine == nil { prepare() }
        guard let engine else { return }

        do {
            try engine.start()
            try makeAndStartPlayer(on: engine)
        } catch {
            readiness = .failed(error.localizedDescription)
            return
        }

        if case .failed = readiness { readiness = .ready }

        isRunning = true
        remaining = duration
        endsAt = Date().addingTimeInterval(duration)

        // A run is short and the phone is in the user's hand the whole time —
        // don't let the screen lock out from under it.
        UIApplication.shared.isIdleTimerDisabled = true
        startTicker()
    }

    func stop() {
        guard isRunning || player != nil else { return }
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        ticker?.invalidate()
        ticker = nil
        endsAt = nil
        isRunning = false
        remaining = duration
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Player plumbing

    private func makeAndStartPlayer(on engine: CHHapticEngine) throws {
        let built = try pattern.makePattern()
        let player = try engine.makeAdvancedPlayer(with: built)
        player.loopEnabled = true
        // Loop exactly one period — the default (0) would trail whatever silence
        // the pattern ends with into the seam.
        player.loopEnd = pattern.loopPeriod
        try player.start(atTime: CHHapticTimeImmediate)
        self.player = player
    }

    /// Rebuild the player in place, preserving the countdown.
    private func restartPlayer() {
        guard let engine else { return }
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        do {
            try makeAndStartPlayer(on: engine)
        } catch {
            readiness = .failed(error.localizedDescription)
            stop()
        }
    }

    private func restartEngineAndPlayer() {
        do {
            try engine?.start()
            restartPlayer()
        } catch {
            readiness = .failed(error.localizedDescription)
            stop()
        }
    }

    // MARK: - Countdown

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common so the countdown keeps updating while the user is dragging a
        // picker or scrolling.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard let endsAt else { return }
        let left = endsAt.timeIntervalSinceNow
        if left <= 0 {
            finish()
        } else {
            remaining = left
        }
    }

    private func finish() {
        stop()
        playCompletionCue()
    }

    /// Three quick taps so you know the run ended without looking at the screen.
    private func playCompletionCue() {
        guard let engine else { return }
        let taps = (0..<3).map { i in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                ],
                relativeTime: Double(i) * 0.12
            )
        }
        do {
            try engine.start()
            let cue = try CHHapticPattern(events: taps, parameterCurves: [])
            try engine.makePlayer(with: cue).start(atTime: CHHapticTimeImmediate)
        } catch {
            // A missing end-of-run cue isn't worth surfacing as an error.
        }
    }

    // MARK: - Power state

    private func observePowerState() {
        let token = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPowerState() }
        }
        observers.append(token)
    }

    private func refreshPowerState() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            readiness = .unsupported
            return
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            readiness = .lowPowerMode
        } else if case .lowPowerMode = readiness {
            readiness = .ready
        } else if case .unsupported = readiness {
            readiness = .ready
        }
    }

    deinit {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
