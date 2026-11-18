// Talking to Jarvis from a kiosk (Dylan, 2026-11-18: "even while the kiosk
// mode is on for iphone, we should be able to talk to jarvis… if i tap the
// orb it will show listening animation… talk mode without any text or
// buttons", and "if tapped again it will go back to idle and not listen").
// The bedside display and the iPad kiosk share this: tap the orb to start a
// Talk call, tap again to hang up completely (mic off, no wake word). The
// orb alone shows the state; a waiting approval is a small amber ring (say
// yes or no out loud); a problem is the one short line, fading after a few
// seconds. The call is the app's own TalkModel, so the Dynamic Island and
// goodbye-hang-up work exactly as in the Talk tab.
import SwiftUI
import UIKit
import JarvisKit

struct KioskTalkOrb: View {
    @ObservedObject var talk: TalkModel
    let app: AppModel
    let size: CGFloat
    let work: [RunningTask]
    /// The orb's resting brightness when no call is on.
    var idleDim: Double = 0.85
    /// The problem showing under the orb, cleared after a few seconds.
    @State private var problem: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            OrbView(
                state: mood,
                size: size,
                level: Double(talk.level),
                tone: Double(talk.tone),
                work: work,
                dim: dim
            )
            // A little bigger while a call is on.
            .scaleEffect(callOpen ? 1.08 : 1)
            .overlay {
                if approvalWaiting {
                    Circle()
                        .strokeBorder(OrbView.workAmber, lineWidth: 3)
                        .frame(width: size * 0.42, height: size * 0.42)
                        .phaseAnimator([0.45, 1]) { ring, glow in ring.opacity(reduceMotion ? 1 : glow) } animation: { _ in .easeInOut(duration: 1.2) }
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Circle())
            .onTapGesture(perform: tap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(callOpen ? "Stop talking" : "Talk to Jarvis")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { tap() }
            .animation(.smooth(duration: 0.6), value: callOpen)
            Text(problem ?? " ")
                .font(.footnote)
                .foregroundStyle(Theme.rose)
                .lineLimit(1)
                .opacity(problem == nil ? 0 : 1)
                .animation(.smooth, value: problem)
                .accessibilityHidden(problem == nil)
        }
        .onChange(of: talk.problem) { _, message in
            guard let message, !message.isEmpty else { return }
            problem = message
            Task {
                try? await Task.sleep(for: .seconds(4))
                if problem == message { problem = nil }
            }
        }
    }

    /// Start, or hang up completely (PhoneKiosk.orbTap in JarvisKit).
    private func tap() {
        switch PhoneKiosk.orbTap(callOpen: callOpen, connecting: talk.phase == .connecting) {
        case .start:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            Task { await talk.start(app: app) }
        case .hangUp:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
            talk.hangUp()
        case .nothing:
            break
        }
    }

    /// True from dialling until the call ends.
    private var callOpen: Bool { talk.phase != .off }

    /// An approval asked on this call that hasn't been answered.
    private var approvalWaiting: Bool {
        callOpen && talk.approvals.contains { $0.outcome == nil }
    }

    /// The call's state, or the kiosk's own (working when Jarvis has jobs).
    private var mood: OrbView.Mood {
        if talk.working != nil { return .working }
        switch talk.phase {
        case .on(.thinking): return .thinking
        case .on(.speaking): return .speaking
        case .on, .connecting: return .listening
        case .off: return work.isEmpty ? .listening : .working
        }
    }

    /// Full while talking, dim while dozing, resting otherwise.
    private var dim: Double {
        switch talk.phase {
        case .on(.dozing): return 0.55
        case .on, .connecting: return 1
        case .off: return idleDim
        }
    }
}
