// Reads the Activity card's numbers from Apple Health on the iPhone (Dylan,
// 2026-11-24: "the health section on iphone app only pulls my steps…
// maybe theres more that can be pulled?"): today's Move, Exercise and Stand
// rings, a week of steps, resting heart rate and heart rate variability,
// 30 days of weight, cardio fitness, walking heart rate and flights.
//
// Read-only and on the phone only: nothing here is sent to Jarvis, logged
// or printed. Asked once, from the card's own button, never at launch
// (the same rule as SleepSync). iPhone only, like SleepSync.
import Foundation
import HealthKit
import JarvisKit

@MainActor
final class ActivitySync: ObservableObject {
    static let shared = ActivitySync()

    private static let askedKey = "activity.asked"
    private let store = HKHealthStore()
    private var loading = false

    /// The latest reading; nil until the first load after Allow.
    @Published private(set) var glance: ActivityGlance?
    /// Whether he has been asked (the card then reads instead of asking).
    @Published private(set) var asked: Bool

    private init() {
        asked = UserDefaults.standard.bool(forKey: Self.askedKey)
    }

    /// Health exists here: the same test as sleep (iPhone, entitled).
    static var available: Bool { SleepSync.available }

    /// The quantity types the card reads.
    private static let quantities: [HKQuantityTypeIdentifier] = [
        .stepCount, .activeEnergyBurned, .appleExerciseTime, .restingHeartRate,
        .heartRateVariabilitySDNN, .walkingHeartRateAverage, .vo2Max, .bodyMass, .flightsClimbed,
    ]

    /// What it asks to read: those, plus the rings' goals and stand hours.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.activitySummaryType()]
        for id in Self.quantities { types.insert(HKQuantityType(id)) }
        return types
    }

    /// "Show more" on the card: Health's own sheet, then the first read.
    func allow() async {
        guard Self.available else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            // Asking failed (no capability in this build): stay on the old card.
            return
        }
        UserDefaults.standard.set(true, forKey: Self.askedKey)
        asked = true
        await refresh()
    }

    /// Reads everything again; quiet when Health has nothing.
    func refresh(now: Date = Date()) async {
        guard Self.available, asked, !loading else { return }
        loading = true
        defer { loading = false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let monthStart = calendar.date(byAdding: .day, value: -30, to: today) ?? today

        var glance = ActivityGlance()
        let kcal = HKUnit.kilocalorie()
        let bpm = HKUnit.count().unitDivided(by: .minute())
        glance.steps = await daily(.stepCount, .cumulativeSum, unit: .count(), from: weekStart, to: now)
        glance.moveKcal = await daily(.activeEnergyBurned, .cumulativeSum, unit: kcal, from: today, to: now).last
        glance.exerciseMin = await daily(.appleExerciseTime, .cumulativeSum, unit: .minute(), from: today, to: now).last
        glance.flights = await daily(.flightsClimbed, .cumulativeSum, unit: .count(), from: today, to: now).last
        glance.restingHR = await daily(.restingHeartRate, .discreteAverage, unit: bpm, from: weekStart, to: now)
        glance.hrv = await daily(.heartRateVariabilitySDNN, .discreteAverage, unit: .secondUnit(with: .milli), from: weekStart, to: now)
        glance.walkingHR = await daily(.walkingHeartRateAverage, .discreteAverage, unit: bpm, from: today, to: now).last
        glance.weightKg = await samples(.bodyMass, unit: .gramUnit(with: .kilo), from: monthStart, to: now)
        let vo2Unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        glance.vo2Max = await samples(.vo2Max, unit: vo2Unit, from: calendar.date(byAdding: .day, value: -180, to: today) ?? monthStart, to: now).last
        if let summary = await activitySummary(for: now) {
            glance.moveGoal = summary.activeEnergyBurnedGoal.doubleValue(for: kcal)
            glance.standHours = summary.appleStandHours.doubleValue(for: .count())
            glance.standGoal = summary.appleStandHoursGoal.doubleValue(for: .count())
            glance.exerciseGoal = summary.appleExerciseTimeGoal.doubleValue(for: .minute())
            // The ring's own numbers win when the watch has them.
            glance.moveKcal = summary.activeEnergyBurned.doubleValue(for: kcal)
            glance.exerciseMin = summary.appleExerciseTime.doubleValue(for: .minute())
        }
        self.glance = glance
    }

    // MARK: Reading

    /// One value per day from `from` to `to` (days with no data left out).
    private func daily(_ id: HKQuantityTypeIdentifier, _ option: HKStatisticsOptions, unit: HKUnit, from: Date, to: Date) async -> [Double] {
        await withCheckedContinuation { continuation in
            let type = HKQuantityType(id)
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate, options: option,
                                                    anchorDate: from, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, _ in
                var values: [Double] = []
                results?.enumerateStatistics(from: from, to: to) { stats, _ in
                    let quantity = option == .cumulativeSum ? stats.sumQuantity() : stats.averageQuantity()
                    if let quantity, quantity.is(compatibleWith: unit) { values.append(quantity.doubleValue(for: unit)) }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    /// Every reading in the range, oldest first.
    private func samples(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> [Double] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            let query = HKSampleQuery(sampleType: HKQuantityType(id), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, results, _ in
                let values = (results ?? []).compactMap { sample -> Double? in
                    guard let quantity = (sample as? HKQuantitySample)?.quantity, quantity.is(compatibleWith: unit) else { return nil }
                    return quantity.doubleValue(for: unit)
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    /// Today's Activity rings, from the watch.
    private func activitySummary(for day: Date) async -> HKActivitySummary? {
        await withCheckedContinuation { continuation in
            var parts = Calendar.current.dateComponents([.era, .year, .month, .day], from: day)
            parts.calendar = Calendar.current
            let predicate = HKQuery.predicateForActivitySummary(with: parts)
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                continuation.resume(returning: summaries?.first)
            }
            store.execute(query)
        }
    }
}
