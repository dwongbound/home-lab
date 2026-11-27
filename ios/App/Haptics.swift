// Plays the app's haptic moments (JarvisKit HapticMoment) on the iPhone's
// Taptic Engine. Every haptic in the app goes through here; the moments
// and their feels are named in JarvisKit, so the feel is tuned there.
// Settings → Haptics turns them off; iPads have no Taptic Engine, so there
// the calls simply do nothing.
//
// While Talk has the microphone recording, iOS holds back haptics (the
// audio session's allowHapticsAndSystemSoundsDuringRecording is left off,
// so the mic never hears the buzz): moments inside a call are mostly not
// felt, and the call's own start is played at the tap, before the mic opens.
#if os(iOS)
import UIKit
import JarvisKit

@MainActor
enum Haptics {
    /// Settings → Haptics (on unless he turns it off).
    static let settingKey = "haptics.on"

    private static let gate = HapticGate(
        sink: TapticSink(),
        enabled: { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true },
        active: { UIApplication.shared.applicationState == .active }
    )

    static func play(_ moment: HapticMoment) {
        #if DEBUG
        // The moment's name only (never anything it's about), to check in
        // the simulator, which can't play them.
        if ProcessInfo.processInfo.arguments.contains("-logHaptics") { NSLog("haptic %@", moment.rawValue) }
        #endif
        gate.play(moment)
    }

    /// A failure he should notice: felt once, not on every quiet retry.
    static func failed(_ what: String) { gate.failed(what) }

    /// It works again.
    static func recovered(_ what: String) { gate.recovered(what) }
}

/// UIKit's generators, kept and re-prepared after each tap so the next one
/// lands with the touch rather than a beat late.
@MainActor
private final class TapticSink: HapticSink {
    private let selection = UISelectionFeedbackGenerator()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let outcome = UINotificationFeedbackGenerator()

    func play(_ feel: HapticFeel) {
        switch feel {
        case .selection: selection.selectionChanged(); selection.prepare()
        case .light: light.impactOccurred(); light.prepare()
        case .medium: medium.impactOccurred(); medium.prepare()
        case .soft: soft.impactOccurred(intensity: 0.7); soft.prepare()
        case .rigid: rigid.impactOccurred(intensity: 0.7); rigid.prepare()
        case .success: outcome.notificationOccurred(.success); outcome.prepare()
        case .warning: outcome.notificationOccurred(.warning); outcome.prepare()
        case .error: outcome.notificationOccurred(.error); outcome.prepare()
        }
    }
}
#endif
