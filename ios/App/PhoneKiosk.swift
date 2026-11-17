// The iPhone's StandBy-style kiosk (Dylan, 2026-11-17): turn the phone on
// its side while it's charging and Jarvis becomes a bedside display. A big
// clock, the live orb with its work dots, what's next, the weather and any
// alert. It leaves when the phone goes upright or comes off power; a tap
// shows Close, which keeps it away until the next rotate or plug-in. The
// screen stays awake while it's up. No money, ever. The rule itself is
// PhoneKiosk.decide in JarvisKit.
import SwiftUI
import UIKit
import JarvisKit

/// Which ways the app may turn. The normal tabs are portrait on iPhone;
/// only the kiosk turns sideways. The iPad turns freely.
final class OrientationLock: NSObject, UIApplicationDelegate {
    /// The orientations allowed right now on iPhone.
    static var phoneMask: UIInterfaceOrientationMask = .portrait

    /// Asked by UIKit whenever it considers rotating.
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : Self.phoneMask
    }

    /// Lets the phone turn to landscape (kiosk) or back to portrait, now.
    @MainActor
    static func allow(_ mask: UIInterfaceOrientationMask) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        phoneMask = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}

/// Watches the phone's orientation and power and decides whether the
/// kiosk is up.
@MainActor
final class PhoneKioskMonitor: ObservableObject {
    /// The Settings switch: "Bedside display", on by default.
    static let enabledKey = "kiosk.phoneAuto"

    @Published private(set) var showing = false
    private var dismissed = false
    private var observers: [NSObjectProtocol] = []

    /// Starts listening for rotation and power changes (iPhone only).
    func start() {
        guard UIDevice.current.userInterfaceIdiom == .phone, observers.isEmpty else { return }
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        device.beginGeneratingDeviceOrientationNotifications()
        let center = NotificationCenter.default
        for name in [UIDevice.orientationDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        update()
    }

    /// Close: back to the app until the next rotate or plug-in.
    func dismiss() {
        dismissed = true
        update()
    }

    /// Works out the new state and turns the screen to match.
    func update() {
        let enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        let next = PhoneKiosk.decide(enabled: enabled, orientation: orientation, power: power, dismissed: dismissed, showing: showing)
        dismissed = next.dismissed
        guard next.showing != showing else { return }
        showing = next.showing
        OrientationLock.allow(showing ? .landscape : .portrait)
        UIApplication.shared.isIdleTimerDisabled = showing
    }

    /// The phone's physical orientation, in the kiosk's terms.
    private var orientation: PhoneKiosk.Orientation {
        switch UIDevice.current.orientation {
        case .portrait, .portraitUpsideDown: return .portrait
        case .landscapeLeft, .landscapeRight: return .landscape
        case .faceUp, .faceDown: return .flat
        default: return .unknown
        }
    }

    /// Whether it's charging, in the kiosk's terms.
    private var power: PhoneKiosk.Power {
        #if DEBUG
        // The simulator has no battery; `-pretendCharging` stands in for a cable.
        if ProcessInfo.processInfo.arguments.contains("-pretendCharging") { return .charging }
        #endif
        switch UIDevice.current.batteryState {
        case .charging: return .charging
        case .full: return .full
        case .unplugged: return .unplugged
        default: return .unknown
        }
    }
}

/// The bedside display itself: the clock and what matters on the left,
/// the orb on the right. A tap shows Close for a few seconds.
struct PhoneKioskView: View {
    @ObservedObject var today: TodayModel
    @ObservedObject var talk: TalkModel
    let onClose: () -> Void
    /// True for a few seconds after a tap, while Close shows.
    @State private var showClose = false

    /// Two halves over the night sky, a dim Close in the corner when tapped.
    var body: some View {
        GeometryReader { area in
            ZStack(alignment: .topTrailing) {
                Theme.sky.ignoresSafeArea()
                HStack(spacing: 24) {
                    clock.frame(maxWidth: .infinity, alignment: .leading)
                    OrbView(
                        state: (today.snapshot?.jobs?.running.isEmpty ?? true) ? .listening : .working,
                        size: min(area.size.height * 0.78, area.size.width * 0.42),
                        level: Double(talk.level),
                        work: today.snapshot?.jobs?.running ?? []
                    )
                }
                .padding(.horizontal, 36)
                .frame(maxHeight: .infinity)
                if showClose {
                    Button("Close", action: onClose)
                        .font(.headline)
                        .foregroundStyle(Theme.frostDim)
                        .frame(minWidth: 88, minHeight: 44)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .padding(16)
                        .transition(.opacity)
                        .accessibilityLabel("Close bedside display")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.smooth) { showClose = true }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation(.smooth) { showClose = false }
                }
            }
        }
        .fontDesign(.rounded)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    /// The big clock, the date and weather, and one line of what matters.
    private var clock: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 96, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text(context.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.frostDim)
                }
            }
            if let weather = today.snapshot?.home?.weather {
                Label(weatherText(weather), systemImage: TodayWording.weatherSymbol(weather.condition))
                    .font(.headline)
                    .foregroundStyle(Theme.frostDim)
                    .symbolRenderingMode(.multicolor)
            }
            matters
                .padding(.top, 6)
        }
    }

    /// An alert or what's next, from the same rule as the iPad kiosk.
    @ViewBuilder
    private var matters: some View {
        switch KioskPlan.hero(snapshot: today.snapshot, pending: []) {
        case .alert(let name, let status):
            Label("\(name) is \(status)", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Theme.ember)
        case .soon(let title, let minutes):
            Label(minutes <= 0 ? "\(title) is starting" : "\(title) in \(minutes) min", systemImage: "calendar.badge.clock")
                .font(.headline)
                .foregroundStyle(Theme.glacier)
        default:
            if let next = nextUp {
                Label("\(AgendaTime.label(at: next.at, allDay: next.allDay ?? false)) · \(next.title)", systemImage: KioskIcons.agendaSymbol(next.title))
                    .font(.headline)
                    .foregroundStyle(Theme.frostDim)
                    .lineLimit(1)
            }
        }
    }

    /// The next thing on today's schedule that hasn't started.
    private var nextUp: AgendaItem? {
        let now = Date()
        let format = ISO8601DateFormatter()
        return today.snapshot?.today.first { item in
            guard let start = format.date(from: item.at) else { return false }
            return start > now
        }
    }

    /// "Cloudy, 58°F".
    private func weatherText(_ weather: Weather) -> String {
        guard let temperature = weather.temperature else { return TodayWording.weatherWords(weather.condition) }
        return "\(TodayWording.weatherWords(weather.condition)), \(Int(temperature.rounded()))\(weather.unit)"
    }
}
