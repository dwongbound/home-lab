// The Dynamic Island and Lock Screen view of a Talk call (Dylan,
// 2026-11-17): a small glowing orb and what Jarvis is doing; expanded, Mute
// and End.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct JarvisLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        TalkLiveActivity()
        GlanceWidget()
        TodayWidget()
        CaloriesWidget()
        SleepWidget()
        HomeWidget()
        BoardWidget()
    }
}

struct TalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TalkActivityAttributes.self) { context in
            // Lock Screen and banner.
            HStack(spacing: 14) {
                MiniOrb(state: context.state.state, size: 36, pulse: context.state.pulse, beat: context.state.beat, muted: context.state.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jarvis").font(.headline)
                    Text(context.state.words).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                controls(context.state)
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.06, green: 0.09, blue: 0.15))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MiniOrb(state: context.state.state, size: 44, pulse: context.state.pulse, beat: context.state.beat, muted: context.state.muted)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("Jarvis").font(.headline)
                        Text(context.state.words).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    controls(context.state)
                        .padding(.top, 6)
                }
            } compactLeading: {
                MiniOrb(state: context.state.state, size: 20, pulse: context.state.pulse, beat: context.state.beat, muted: context.state.muted)
            } compactTrailing: {
                Text(context.state.words)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint(context.state.state))
            } minimal: {
                MiniOrb(state: context.state.state, size: 20, pulse: context.state.pulse, beat: context.state.beat, muted: context.state.muted)
            }
            .keylineTint(tint(context.state.state))
        }
    }

    /// Mute and End.
    private func controls(_ state: TalkActivityAttributes.ContentState) -> some View {
        HStack(spacing: 10) {
            Button(intent: ToggleTalkMuteIntent()) {
                Label(state.muted ? "Unmute" : "Mute", systemImage: state.muted ? "mic.slash.fill" : "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(state.muted ? Color(red: 0.94, green: 0.57, blue: 0.6) : .gray)
            Button(intent: EndTalkIntent()) {
                Label("End", systemImage: "phone.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.borderedProminent)
    }

    /// Blue while listening, violet while thinking, white while speaking.
    private func tint(_ state: String) -> Color {
        switch state {
        case "thinking": return Color(red: 0.73, green: 0.65, blue: 0.94)
        case "working": return Color(red: 0.91, green: 0.69, blue: 0.42)
        case "speaking": return .white
        default: return Color(red: 0.56, green: 0.77, blue: 0.92)
        }
    }
}

/// The orb, small (Dylan, 2026-11-17: animate it): a glass core inside a
/// ring of constellation dots, like the app's orb. The island can't run
/// a continuous animation, so it moves between updates instead: the core
/// swells with `pulse` (the voice), the ring turns a step on every `beat`,
/// and iOS animates each change.
struct MiniOrb: View {
    let state: String
    let size: CGFloat
    var pulse: Int = 0
    var beat: Int = 0
    var muted = false

    var body: some View {
        // Violet while thinking, amber while working, blue otherwise.
        let glow: Color = state == "thinking" ? Color(red: 0.73, green: 0.65, blue: 0.94)
            : state == "working" ? Color(red: 0.91, green: 0.69, blue: 0.42)
            : Color(red: 0.56, green: 0.77, blue: 0.92)
        let swell = 1 + CGFloat(min(max(pulse, 0), 3)) * 0.07
        ZStack {
            // The ring: eight dots, alternately near and far, turning a step a beat.
            ForEach(0..<8, id: \.self) { i in
                let near = i % 2 == 0
                Circle()
                    .fill(.white.opacity(near ? 0.9 : 0.45))
                    .frame(width: size * (near ? 0.11 : 0.08), height: size * (near ? 0.11 : 0.08))
                    .offset(y: -size * 0.46 * swell)
                    .rotationEffect(.degrees(Double(i) * 45 + Double(beat % 24) * 15))
            }
            Circle()
                .fill(RadialGradient(colors: [.white, glow, glow.opacity(0.55)], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.36))
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                .shadow(color: glow.opacity(0.8), radius: size * 0.12 * swell)
                .frame(width: size * 0.58 * swell, height: size * 0.58 * swell)
        }
        .frame(width: size, height: size)
        // Muted: dim and still (the app stops sending steps).
        .opacity(muted ? 0.5 : 1)
        .animation(.smooth(duration: 0.8), value: pulse)
        .animation(.smooth(duration: 0.8), value: beat)
        .animation(.smooth(duration: 0.6), value: state)
    }
}
