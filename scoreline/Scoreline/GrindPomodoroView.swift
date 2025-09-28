//
//  GrindPomodoroView.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/28/25.
//

import SwiftUI
import Combine

struct GrindPomodoroView: View {
    // MARK: - Timer mode & settings
    enum Mode: String, CaseIterable {
        case focus, shortBreak, longBreak
        var displayName: String {
            switch self {
            case .focus: return "Focus"
            case .shortBreak: return "Short Break"
            case .longBreak: return "Long Break"
            }
        }
    }

    // Persisted settings
    @AppStorage("gs_pomodoro_focus_mins") private var focusMinutes: Int = 25
    @AppStorage("gs_pomodoro_short_break_mins") private var shortBreakMinutes: Int = 5
    @AppStorage("gs_pomodoro_long_break_mins") private var longBreakMinutes: Int = 15
    @AppStorage("gs_pomodoro_sessions_until_long_break") private var sessionsUntilLong: Int = 4

    // Presets
    private enum Preset: String {
        case short, medium, long, custom
    }

    @AppStorage("gs_pomodoro_preset") private var presetRaw: String = Preset.medium.rawValue
    @AppStorage("gs_pomodoro_auto_start_next") private var autoStartNext: Bool = true

    // Derived helpers
    private var preset: Preset { Preset(rawValue: presetRaw) ?? .medium }

    private var currentFocusMinutes: Int {
        switch preset {
        case .short:  return 10
        case .medium: return 25
        case .long:   return 50
        case .custom: return focusMinutes
        }
    }

    private var currentBreakMinutes: Int {
        switch preset {
        case .short:  return 5
        case .medium: return 5
        case .long:   return 10
        case .custom: return shortBreakMinutes
        }
    }

    private var currentLongBreakMinutes: Int {
        switch preset {
        case .short:  return 10
        case .medium: return 10
        case .long:   return 10
        case .custom: return longBreakMinutes
        }
    }

    // Runtime state
    @State private var mode: Mode = .focus
    @State private var isRunning: Bool = false
    @State private var remainingSeconds: Int = 25 * 60
    @State private var totalSecondsForMode: Int = 25 * 60
    @State private var completedFocusSessions: Int = 0

    // Timer publisher
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var targetDate: Date?

    // Toast state
    @State private var toastMessage: String? = nil

    // Haptics
    private let haptic = UINotificationFeedbackGenerator()

    // Palette (kept local to this file to be drop-in)
    private enum Palette {
        static let amethyst       = Color(.sRGB, red: 167/255, green: 139/255, blue: 250/255, opacity: 1)
        static let goldSoft       = Color(.sRGB, red: 253/255, green: 224/255, blue: 130/255, opacity: 1)
        static let skySoft        = Color(.sRGB, red: 189/255, green: 219/255, blue: 255/255, opacity: 1)
        static let mintSoft       = Color(.sRGB, red: 197/255, green: 243/255, blue: 220/255, opacity: 1)
        static let roseSoft       = Color(.sRGB, red: 255/255, green: 214/255, blue: 222/255, opacity: 1)
        static let ink            = Color(.sRGB, red: 38/255,  green: 38/255,  blue: 43/255,  opacity: 1)
        static let inkTertiary    = Color(.sRGB, red: 74/255,  green: 74/255,  blue: 80/255,  opacity: 0.65)
        static let bgTop          = Color(.sRGB, red: 250/255, green: 247/255, blue: 255/255, opacity: 1)
        static let bgBottom       = Color(.sRGB, red: 255/255, green: 246/255, blue: 246/255, opacity: 1)
        static let cardTop        = Color(.sRGB, red: 255/255, green: 252/255, blue: 245/255, opacity: 1)
        static let cardBottom     = Color(.sRGB, red: 246/255, green: 244/255, blue: 255/255, opacity: 1)
        static let shadow         = Color.black.opacity(0.06)
        static let roseSoftAccent = Color(.sRGB, red: 255/255, green: 228/255, blue: 235/255, opacity: 1)
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Palette.bgTop, Palette.bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    headerCard

                    timerCard

                    controlRow

                    sessionSummary

                    Spacer(minLength: 16)
                }
                .padding(16)

                // Toast overlay
                if let msg = toastMessage {
                    toastView(message: msg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(10)
                        .padding(.bottom, 16)
                }
            }
            .navigationTitle("Pomodoro")
            .onReceive(timer) { now in
                guard isRunning else { return }
                tick(now: now)
            }
            .onChange(of: mode) { _old, _new in
                applyModeDurations()
            }
            .onChange(of: focusMinutes) { _, _ in applyModeDurations() }
            .onChange(of: shortBreakMinutes) { _, _ in applyModeDurations() }
            .onChange(of: longBreakMinutes) { _, _ in applyModeDurations() }
            .onChange(of: presetRaw) { _, _ in
                applyModeDurations()
            }
            .onAppear {
                applyModeDurations()
                haptic.prepare()
            }
        }
    }

    // MARK: - Subviews

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text("Grindstone Focus")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("Work in short sprints. Earn Stones, stay focused.")
                .font(.caption2)
                .foregroundStyle(Palette.inkTertiary)

            // Preset picker (top control)
            VStack(alignment: .leading, spacing: 8) {
                Picker("Preset", selection: $presetRaw) {
                    Text("Short 10/5").tag(Preset.short.rawValue)
                    Text("Medium 25/5").tag(Preset.medium.rawValue)
                    Text("Long 50/10").tag(Preset.long.rawValue)
                    Text("Custom").tag(Preset.custom.rawValue)
                }
                .pickerStyle(.segmented)
                .tint(Palette.amethyst)

                if preset == .custom {
                    // Inline custom controls (compact)
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Stepper("\(focusMinutes) min focus", value: $focusMinutes, in: 5...90, step: 1)
                            Stepper("\(shortBreakMinutes) min break", value: $shortBreakMinutes, in: 1...30, step: 1)
                        }
                        HStack(spacing: 12) {
                            Stepper("\(longBreakMinutes) min long break", value: $longBreakMinutes, in: 5...60, step: 1)
                            Stepper("\(sessionsUntilLong) sessions → long", value: $sessionsUntilLong, in: 2...8, step: 1)
                        }
                    }
                    Toggle("Auto-start next period", isOn: $autoStartNext)
                        .font(.caption)
                        .toggleStyle(.switch)
                        .tint(Palette.amethyst)
                } else {
                    // Show resolved minutes for the chosen preset
                    HStack {
                        Text("Focus \(currentFocusMinutes) min")
                        Spacer()
                        Text("Break \(currentBreakMinutes) min")
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.inkTertiary)
                }
            }

            // Current period badge (non-interactive)
            HStack {
                Spacer()
                Text(mode.displayName)
                    .font(.caption).bold()
                    .foregroundStyle(Palette.amethyst)
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Palette.cardTop)
                            .shadow(color: Palette.shadow, radius: 4, x: 0, y: 1)
                    )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Palette.cardTop, Palette.cardBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Palette.shadow, radius: 6, x: 0, y: 2)
        )
    }

    private var timerCard: some View {
        VStack(spacing: 16) {
            ZStack {
                // Base ring
                Circle()
                    .stroke(Color.white.opacity(0.6), lineWidth: 16)
                    .frame(width: 220, height: 220)
                    .shadow(color: Palette.shadow, radius: 6, x: 0, y: 2)

                // Progress ring
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 220, height: 220)
                    .foregroundStyle(AngularGradient(gradient: Gradient(colors: [Palette.amethyst, Palette.goldSoft]), center: .center))

                // Center content
                VStack(spacing: 6) {
                    Text(timeString(from: remainingSeconds))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()

                    Text(modeSubtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.inkTertiary)
                }
                .padding(.top, 4)
            }

            // small hint
            HStack {
                ProgressMeterLabel()
                Spacer()
                Text(progressLabel)
                    .font(.caption2)
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(.horizontal, 12)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.96)))
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            Button(action: { startPauseToggle() }) {
                Label(isRunning ? "Pause" : "Start", systemImage: isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRunning ? Palette.roseSoftAccent : Palette.amethyst)

            Button(action: { Task { await stopSessionAndAward() } }) {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Palette.inkTertiary)

            Button(action: { skipSession() }) {
                Label("Skip", systemImage: "forward.end.alt")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Palette.goldSoft)
        }
        .buttonBorderShape(.capsule)
    }

    private var sessionSummary: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text("Completed focus sessions")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkTertiary)
                Text("\(completedFocusSessions)")
                    .font(.title2).bold()
                    .foregroundStyle(Palette.amethyst)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("Session length")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkTertiary)
                Text("\(currentFocusMinutes) min")
                    .font(.title2).bold()
                    .foregroundStyle(Palette.goldSoft)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.95)))
    }

    // MARK: - Helpers / Logic

    private var progressFraction: Double {
        guard totalSecondsForMode > 0 else { return 0 }
        return 1 - (Double(remainingSeconds) / Double(totalSecondsForMode))
    }

    private var modeSubtitle: String {
        switch mode {
        case .focus: return "Focus — concentrate"
        case .shortBreak: return "Short break — breathe"
        case .longBreak: return "Long break — recharge"
        }
    }

    private var progressLabel: String {
        let pct = Int(round(progressFraction * 100))
        return "\(pct)%"
    }

    private func timeString(from seconds: Int) -> String {
        let s = max(0, seconds)
        let m = s / 60
        let sec = s % 60
        return String(format: "%02d:%02d", m, sec)
    }

    private func applyModeDurations() {
        switch mode {
        case .focus:
            totalSecondsForMode = max(1, currentFocusMinutes) * 60
        case .shortBreak:
            totalSecondsForMode = max(1, currentBreakMinutes) * 60
        case .longBreak:
            totalSecondsForMode = max(1, currentLongBreakMinutes) * 60
        }

        if !isRunning {
            remainingSeconds = totalSecondsForMode
        } else {
            // Re-anchor target so live timers stay accurate after changes
            targetDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        }
    }

    private func startPauseToggle() {
        if isRunning {
            // Pause: keep remainingSeconds as-is; clear target to stop drift
            isRunning = false
            targetDate = nil
        } else {
            // Start or resume
            if remainingSeconds <= 0 { applyModeDurations() }
            // Set a precise target that we’ll count down toward
            targetDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
            isRunning = true
        }
    }

    private func resetTimer() {
        isRunning = false
        targetDate = nil
        applyModeDurations()
    }

    private func skipSession() {
        isRunning = false
        // move to next mode
        advanceToNextMode(manualSkip: true)
    }

    private func tick(now: Date) {
        guard isRunning, let target = targetDate else { return }

        // Compute remaining from absolute target; this self-corrects if ticks are late
        let remaining = Int(ceil(target.timeIntervalSince(now)))

        if remaining <= 0 {
            remainingSeconds = 0
            isRunning = false
            targetDate = nil
            haptic.notificationOccurred(.success)
            Task { @MainActor in
                await periodCompleted()
            }
        } else if remaining != remainingSeconds {
            remainingSeconds = remaining
        }
    }

    @MainActor
    private func periodCompleted() async {
        if mode == .focus {
            completedFocusSessions += 1
            let becameLong = (completedFocusSessions % sessionsUntilLong == 0)
            mode = becameLong ? .longBreak : .shortBreak
        } else {
            mode = .focus
        }
        applyModeDurations()

        if autoStartNext {
            isRunning = true
            targetDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        }
    }

    private func advanceToNextMode(manualSkip: Bool = false) {
        switch mode {
        case .focus:
            let becameLong = ((completedFocusSessions + (manualSkip ? 1 : 0)) % sessionsUntilLong == 0)
            mode = becameLong ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            mode = .focus
        }
        applyModeDurations()
    }

    // small accessory view for labeling progress
    @ViewBuilder
    private func ProgressMeterLabel() -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.amethyst)
                .frame(width: 8, height: 8)
            Text("Focus progress")
                .font(.caption2)
                .foregroundStyle(Palette.inkTertiary)
        }
    }

    // MARK: - Award DTOs (simple, no anti-cheat)
    private struct FocusAwardRequest: Encodable {
        let seconds: Int      // seconds of focus to award
    }

    private struct FocusAwardResponse: Decodable {
        let awardedPoints: Int
        let totalPoints: Int
    }

    @MainActor
    private func stopSessionAndAward() async {
        // Only award for Focus periods
        guard mode == .focus else {
            // If user stops on a break, just reset to Focus without awarding
            isRunning = false
            targetDate = nil
            mode = .focus
            applyModeDurations()
            return
        }

        // Compute focused seconds in current period
        let elapsed = max(0, totalSecondsForMode - remainingSeconds)
        isRunning = false
        targetDate = nil

        // If nothing meaningful, just reset to Focus
        guard elapsed > 0 else {
            applyModeDurations()
            return
        }

        do {
            // POST /api/focus/award { seconds }
            let res: FocusAwardResponse = try await APIClient.shared.postJSON("/api/focus/award",
                                                                              body: FocusAwardRequest(seconds: elapsed))
            // Haptic + UI nudge
            haptic.notificationOccurred(.success)
            showToast("Awarded \(res.awardedPoints) Stones")
            #if DEBUG
            print("🏅 Awarded \(res.awardedPoints) Stones. Total: \(res.totalPoints)")
            #endif
        } catch {
            // Soft-fail: show failure toast
            showToast("Award failed")
            #if DEBUG
            print("⚠️ Award failed: \(error.localizedDescription)")
            #endif
        }

        // Move to break like a completed focus session
        completedFocusSessions += 1
        let becameLong = (completedFocusSessions % sessionsUntilLong == 0)
        mode = becameLong ? .longBreak : .shortBreak
        applyModeDurations()
    }

    // MARK: - Toast helpers

    @MainActor
    private func showToast(_ message: String, durationSeconds: UInt64 = 3) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toastMessage = message
        }
        // Auto-dismiss
        Task {
            try? await Task.sleep(nanoseconds: durationSeconds * 1_000_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    toastMessage = nil
                }
            }
        }
    }

    @ViewBuilder
    private func toastView(message: String) -> some View {
        HStack(spacing: 10) {
            Image("Coins")
                .imageScale(.medium)
                .foregroundColor(.yellow)
            Text(message)
                .font(.subheadline).bold()
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(VisualEffectBlurView(blurStyle: .systemThinMaterial))
        .clipShape(Capsule())
        .shadow(radius: 8)
        .padding(.horizontal, 24)
    }
}

// Small UIViewRepresentable to get a nice blurred capsule background on iOS
private struct VisualEffectBlurView: UIViewRepresentable {
    let blurStyle: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) { }
}
