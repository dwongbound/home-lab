// Sends last night's sleep from Apple Health to Jarvis (Dylan, 2026-11-20:
// "can i also send and get sleep score from my apple watch and more
// specific sleep details"). Read-only: the app never writes to Health.
//
// - Asked once, from a small card at the top of Home ("Allow"), never
//   sprung at launch. Settings → Sleep details turns sending off.
// - A finished night goes in the morning on its own: an observer on sleep
//   with background delivery wakes the app when the watch writes it, and
//   every return to the app catches up on any night not yet sent. The
//   first allow sends the last 14 nights.
// - Each night is built by JarvisKit SleepNights (pure, tested) and sent
//   once; a night that grew since (a late watch sync) is sent again, which
//   Jarvis takes as a replacement.
// - iPhone only: an iPad has no Health data of its own here.
//
// Never logs, prints or reports a health value.
//
// Needs the HealthKit capability (and background delivery) in the app's
// entitlements; until that's signed in, asking simply fails and the card
// says so. The upload itself waits for SleepUpload.live.
import Foundation
import HealthKit
import UIKit
import JarvisKit

/// The upload switch for this build. Off until the page route
/// /api/jarvis/health/sleep is live; turn it on by setting `live` to true.
enum SleepUpload {
    static let live = true
}

@MainActor
final class SleepSync: ObservableObject {
    static let shared = SleepSync()

    /// Settings → Sleep details (on unless he turns it off).
    static let enabledKey = "sleep.enabled"
    private static let askedKey = "sleep.asked"
    private static let dismissedKey = "sleep.cardDismissed"
    private static let sentKey = "sleep.sentNights"
    private static let failuresKey = "sleep.failures"
    private static let retryAtKey = "sleep.retryAt"

    private let store = HKHealthStore()
    private var observing = false
    private var syncing = false
    /// Waiting for the phone to unlock before reading Health.
    private var unlockWatch: NSObjectProtocol?

    /// The Allow card: what it says under its line when asking failed.
    @Published var askProblem: String?
    @Published private(set) var askedOrDismissed: Bool

    private init() {
        let defaults = UserDefaults.standard
        askedOrDismissed = defaults.bool(forKey: Self.askedKey) || defaults.bool(forKey: Self.dismissedKey)
    }

    /// Health exists here: an iPhone (never the iPad, TV or Watch builds).
    static var available: Bool {
        SleepAccess.canAsk(entitled: entitled, healthAvailable: HKHealthStore.isHealthDataAvailable(),
                           isPhone: UIDevice.current.userInterfaceIdiom == .phone)
    }

    /// The build carries the HealthKit entitlement: set in Info.plist
    /// (JarvisHealthKit) in the same change that adds the entitlement, so
    /// the two can't disagree.
    static var entitled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "JarvisHealthKit") as? Bool == true
    }

    /// Jarvis at the address in Settings (the same one AppModel uses); read
    /// here too, since Health can wake the app before any screen exists.
    private static var client: JarvisClient {
        let server = UserDefaults.standard.string(forKey: "jarvis.server") ?? ""
        return JarvisClient(base: URL(string: server.trimmingCharacters(in: .whitespaces)) ?? JarvisClient.defaultBase)
    }

    private var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
    private var asked: Bool { UserDefaults.standard.bool(forKey: Self.askedKey) }

    /// Whether Home shows the one-time Allow card.
    var showsCard: Bool { Self.available && enabled && !askedOrDismissed }

    /// What it reads: sleep and the overnight vitals. Nothing is written.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis)]
        let quantities: [HKQuantityTypeIdentifier] = [
            .heartRate, .heartRateVariabilitySDNN, .respiratoryRate, .oxygenSaturation,
            .appleSleepingWristTemperature,
        ]
        for id in quantities { types.insert(HKQuantityType(id)) }
        if #available(iOS 18.0, *) { types.insert(HKQuantityType(.appleSleepingBreathingDisturbances)) }
        // RMSSD is new in the iOS 27 SDK; CI's older Xcode must not see it.
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) { types.insert(HKQuantityType(.heartRateVariabilityRMSSD)) }
        #endif
        return types
    }

    // MARK: Asking

    /// "Allow" on the card: Health's own sheet, then the first 14 nights.
    func allow() async {
        guard Self.available else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            UserDefaults.standard.set(true, forKey: Self.askedKey)
            askedOrDismissed = true
            askProblem = nil
            start()
            await catchUp()
        } catch {
            // The likely one before the capability is signed in.
            askProblem = "Apple Health isn't set up in this version of the app yet."
        }
    }

    /// "Not now" on the card: it doesn't come back (Settings still has the switch).
    func dismissCard() {
        UserDefaults.standard.set(true, forKey: Self.dismissedKey)
        askedOrDismissed = true
    }

    // MARK: Watching

    /// At launch (once he's allowed it): the observer that wakes the app
    /// when sleep is written, so a finished night goes without opening it.
    func start() {
        guard Self.available, asked, !observing else { return }
        observing = true
        let sleep = HKCategoryType(.sleepAnalysis)
        let query = HKObserverQuery(sampleType: sleep, predicate: nil) { [weak self] _, done, error in
            guard error == nil else { done(); return }
            Task { @MainActor in
                await self?.catchUp()
                done()
            }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: sleep, frequency: .immediate) { _, _ in }
    }

    /// Sends any recent night Jarvis doesn't have yet. Quiet on failure:
    /// the next wake or return to the app tries again.
    func catchUp(now: Date = Date()) async {
        let client = Self.client
        let defaults = UserDefaults.standard
        // Jarvis was away lately: leave him a while (SleepWire.backoff).
        if let retryAt = defaults.object(forKey: Self.retryAtKey) as? Date, retryAt > now { return }
        guard Self.available, enabled, asked, SleepUpload.live, !syncing else { return }
        // Health can't be read while the phone is locked, and a wake from
        // Health often comes then (the watch syncs at dawn), which used to
        // read nothing and wait for the next time he opened the app. Now
        // it waits for the unlock instead, if the app is still awake then;
        // Jarvis's quiet morning push and opening the app cover the rest.
        guard UIApplication.shared.isProtectedDataAvailable else {
            waitForUnlock()
            return
        }
        syncing = true
        defer { syncing = false }
        let nights = SleepNights.recent(SentNights.backfill, now: now)
        var sent = SentNights(sent: UserDefaults.standard.dictionary(forKey: Self.sentKey) as? [String: String] ?? [:])
        sent.prune(keeping: nights)
        for night in nights {
            guard let built = await build(night), sent.needs(built) else { continue }
            // Over 500 stages even merged: skipped, and not looked at again.
            guard SleepWire.sendable(built) else { sent.mark(built); continue }
            var status: Int?
            do {
                try await client.sendSleep(SleepWire.body(built))
                status = 200
            } catch JarvisError.server(let code, _) {
                status = code
            } catch {
                status = nil
            }
            switch SleepWire.outcome(status: status) {
            case .stored, .refused: sent.mark(built)
            case .later: break
            }
            // Jarvis away: stop here and try the rest later, backing off.
            if SleepWire.outcome(status: status) == .later {
                let failures = defaults.integer(forKey: Self.failuresKey) + 1
                defaults.set(failures, forKey: Self.failuresKey)
                defaults.set(now.addingTimeInterval(SleepWire.backoff(failures: failures)), forKey: Self.retryAtKey)
                break
            }
            defaults.removeObject(forKey: Self.failuresKey)
            defaults.removeObject(forKey: Self.retryAtKey)
        }
        UserDefaults.standard.set(sent.stored, forKey: Self.sentKey)
    }

    /// Runs catchUp once when the phone is next unlocked.
    private func waitForUnlock() {
        guard unlockWatch == nil else { return }
        unlockWatch = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let watch = self.unlockWatch { NotificationCenter.default.removeObserver(watch) }
                self.unlockWatch = nil
                await self.catchUp()
            }
        }
    }

    // MARK: Reading

    /// One night from Health (nil when there's no sleep in its window).
    private func build(_ night: String) async -> SleepNight? {
        guard let window = SleepNights.window(night) else { return nil }
        let stages = await samples(HKCategoryType(.sleepAnalysis), in: window).compactMap { sample -> SleepStageSample? in
            guard let category = sample as? HKCategorySample, let value = SleepValue(rawValue: category.value) else { return nil }
            return SleepStageSample(value: value, start: category.startDate, end: category.endDate, source: source(of: category))
        }
        guard !stages.isEmpty else { return nil }
        var vitals = SleepVitals()
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        let perSecond = HKUnit.count().unitDivided(by: .second())
        vitals.heartRate = await readings(.heartRate, unit: perMinute, in: window)
        vitals.hrvSDNN = await readings(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), in: window)
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            vitals.hrvRMSSD = await readings(.heartRateVariabilityRMSSD, unit: .secondUnit(with: .milli), in: window)
        }
        #endif
        vitals.respiratoryPerSecond = await readings(.respiratoryRate, unit: perSecond, in: window)
        vitals.oxygenFraction = await readings(.oxygenSaturation, unit: .percent(), in: window)
        vitals.wristTemperature = await readings(.appleSleepingWristTemperature, unit: .degreeCelsius(), in: window)
        if #available(iOS 18.0, *) {
            vitals.breathingDisturbances = await readings(.appleSleepingBreathingDisturbances, unit: .count(), in: window)
        }
        return SleepNights.build(night: night, stages: stages, vitals: vitals)
    }

    private func readings(_ id: HKQuantityTypeIdentifier, unit: HKUnit, in window: DateInterval) async -> [SleepReading] {
        await samples(HKQuantityType(id), in: window).compactMap { sample in
            guard let quantity = sample as? HKQuantitySample, quantity.quantity.is(compatibleWith: unit) else { return nil }
            return SleepReading(value: quantity.quantity.doubleValue(for: unit), start: quantity.startDate, end: quantity.endDate, source: source(of: quantity))
        }
    }

    /// Everything of a type that touches the window.
    private func samples(_ type: HKSampleType, in window: DateInterval) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: [])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                continuation.resume(returning: results ?? [])
            }
            store.execute(query)
        }
    }

    /// Which app or device wrote it, and whether that's an Apple Watch.
    private func source(of sample: HKSample) -> SleepSource {
        let revision = sample.sourceRevision
        let isWatch = (revision.productType ?? "").hasPrefix("Watch") || sample.device?.model == "Watch"
        return SleepSource(id: revision.source.bundleIdentifier, isWatch: isWatch)
    }
}
