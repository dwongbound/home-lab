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
    }
}

struct TalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TalkActivityAttributes.self) { context in
            // Lock Screen and banner.
            HStack(spacing: 14) {
                MiniOrb(state: context.state.state, size: 36)
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
                    MiniOrb(state: context.state.state, size: 44)
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
                MiniOrb(state: context.state.state, size: 20)
            } compactTrailing: {
                Text(context.state.words)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint(context.state.state))
            } minimal: {
                MiniOrb(state: context.state.state, size: 20)
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
        case "speaking": return .white
        default: return Color(red: 0.56, green: 0.77, blue: 0.92)
        }
    }
}

/// The orb, small: a glass core with a soft glow in the state's colour.
struct MiniOrb: View {
    let state: String
    let size: CGFloat

    var body: some View {
        let glow: Color = state == "thinking"
            ? Color(red: 0.73, green: 0.65, blue: 0.94)
            : Color(red: 0.56, green: 0.77, blue: 0.92)
        Circle()
            .fill(RadialGradient(colors: [.white, glow, glow.opacity(0.55)], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.6))
            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
            .shadow(color: glow.opacity(0.8), radius: size * 0.2)
            .frame(width: size, height: size)
    }
}
