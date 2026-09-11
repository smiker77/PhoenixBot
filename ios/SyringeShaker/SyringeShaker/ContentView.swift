import SwiftUI

struct ContentView: View {
    @StateObject private var agitator = HapticAgitator()
    @Environment(\.scenePhase) private var scenePhase

    private let durations: [TimeInterval] = [10, 20, 30, 60]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Spacer(minLength: 12)

                AgitateButton(
                    isRunning: agitator.isRunning,
                    progress: agitator.progress,
                    remaining: agitator.remaining,
                    enabled: agitator.readiness != .unsupported,
                    action: agitator.toggle
                )

                Spacer(minLength: 12)

                Text(agitator.isRunning
                     ? "Hold the barrel flat against the lower back of the phone."
                     : "Press the syringe barrel to the back of the phone, then tap.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 40)
                    .animation(.easeInOut, value: agitator.isRunning)

                controls

                if let warning = warningText {
                    WarningBanner(text: warning)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }
            }
            .padding(.vertical, 24)
        }
        .preferredColorScheme(.dark)
        .onAppear { agitator.prepare() }
        .onChange(of: scenePhase) { _, phase in
            // Haptics die the moment we lose the foreground; stop cleanly rather
            // than leaving a countdown running against a silent engine.
            if phase != .active { agitator.stop() }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 4) {
            Text("Syringe Agitator")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
            Text("Taptic resuspension")
                .font(.caption)
                .textCase(.uppercase)
                .tracking(1.6)
                .foregroundStyle(Color.accentColor.opacity(0.8))
        }
    }

    private var controls: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Picker("Pattern", selection: $agitator.pattern) {
                    ForEach(AgitationPattern.allCases) { pattern in
                        Text(pattern.title).tag(pattern)
                    }
                }
                .pickerStyle(.segmented)

                Text(agitator.pattern.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(height: 14)
            }

            Picker("Duration", selection: $agitator.duration) {
                ForEach(durations, id: \.self) { seconds in
                    Text("\(Int(seconds))s").tag(seconds)
                }
            }
            .pickerStyle(.segmented)
            .disabled(agitator.isRunning)
            .opacity(agitator.isRunning ? 0.4 : 1)
        }
        .padding(.horizontal, 20)
    }

    private var warningText: String? {
        switch agitator.readiness {
        case .ready:
            return nil
        case .unsupported:
            return "This device has no Taptic Engine, so there's nothing to drive."
        case .lowPowerMode:
            return "Low Power Mode silences the Taptic Engine. Turn it off in Settings › Battery."
        case .failed(let message):
            return "Haptic engine error: \(message)"
        }
    }
}

// MARK: - Button

private struct AgitateButton: View {
    let isRunning: Bool
    let progress: Double
    let remaining: TimeInterval
    let enabled: Bool
    let action: () -> Void

    private let size: CGFloat = 244

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 10)

            // Countdown ring, draining clockwise from 12 o'clock.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .opacity(isRunning ? 1 : 0)
                .animation(.linear(duration: 0.05), value: progress)

            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: isRunning
                                    ? [Color.accentColor, Color.accentColor.opacity(0.55)]
                                    : [Color.white.opacity(0.16), Color.white.opacity(0.06)],
                                center: .topLeading,
                                startRadius: 8,
                                endRadius: size
                            )
                        )

                    VStack(spacing: 6) {
                        Image(systemName: isRunning ? "stop.fill" : "waveform.path")
                            .font(.system(size: 40, weight: .medium))
                        Text(isRunning ? timeString : "AGITATE")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .tracking(isRunning ? 0 : 2)
                    }
                    .foregroundStyle(isRunning ? Color.black.opacity(0.85) : .white)
                }
                .padding(22)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.2), value: isRunning)
    }

    private var timeString: String {
        String(format: "%.1fs", max(0, remaining))
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Warning

private struct WarningBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(Color.orange)
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    ContentView()
}
