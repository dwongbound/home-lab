// The Diet screen (Dylan, 2026-11-18: "Can you recreate this page for my
// diet?"): one day's food in Jarvis's own look. The week strip on top (a
// ring per day filling with that day's calories), the four totals against
// their goals, then an hour-by-hour list of what was eaten. Read-only; the
// numbers and the grouping come from JarvisKit's Diet.
import SwiftUI
import JarvisKit

/// The day's data as the screen shows it.
@MainActor
final class DietModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ready(NutritionDay)
        /// Jarvis answered, but with no day (older Jarvis, down, no login).
        case unreachable
        case failed(String)
    }

    /// The day showing, "YYYY-MM-DD" (Pacific).
    @Published var date: String
    @Published private(set) var state: State = .loading
    @Published private(set) var week: NutritionWeek?

    init(date: String = Diet.dayString(Date())) {
        self.date = date
    }

    /// Loads the day and its week together.
    func load(client: JarvisClient) async {
        #if DEBUG
        // `-demoDiet` shows sample food, whatever Jarvis has.
        if ProcessInfo.processInfo.arguments.contains("-demoDiet") {
            state = .ready(DemoDiet.day(date))
            week = DemoDiet.week(Diet.weekStart(of: date) ?? date)
            return
        }
        #endif
        if case .ready(let shown) = state, shown.date != date { state = .loading }
        let start = Diet.weekStart(of: date) ?? date
        async let day = client.nutritionDay(date: date)
        async let week = client.nutritionWeek(start: start)
        do {
            if let found = try await day {
                state = .ready(found)
            } else {
                state = .unreachable
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
        self.week = (try? await week) ?? self.week
    }
}

struct DietView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = DietModel()
    @Environment(\.horizontalSizeClass) private var width

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.sky.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        weekStrip
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await model.load(client: app.client) }
            }
            .navigationTitle(Diet.title(model.date))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .task(id: model.date) { await model.load(client: app.client) }
    }

    // MARK: Week

    /// The seven days of the week, each in a ring that fills with that
    /// day's calories; today marked; a tap shows that day.
    private var weekStrip: some View {
        let days = model.week?.days ?? placeholderWeek
        return HStack(spacing: 4) {
            ForEach(days) { day in
                Button {
                    model.date = day.date
                } label: {
                    VStack(spacing: 6) {
                        Text(Diet.weekdayInitials(day.date))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(day.date == model.date ? Theme.frost : Theme.frostDim)
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.10), lineWidth: 3)
                            if let ring = day.ring {
                                Circle()
                                    .trim(from: 0, to: ring)
                                    .stroke(Diet.isOver(day.calories, goal: day.goal) ? Theme.ember : Theme.moss, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            Text(Diet.dayNumber(day.date))
                                .font(.footnote.weight(day.date == today ? .bold : .medium))
                                .foregroundStyle(day.date == today ? Theme.glacier : Theme.frost)
                        }
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(day.date == model.date ? Color.white.opacity(0.10) : .clear))
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dayLabel(day))
                .accessibilityAddTraits(day.date == model.date ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .glassPanel()
    }

    /// Today, Pacific.
    private var today: String { Diet.dayString(Date()) }

    /// Empty rings for the week while it loads.
    private var placeholderWeek: [WeekDay] {
        let start = Diet.weekStart(of: model.date) ?? model.date
        return (0..<7).map { WeekDay(date: Diet.shift(start, by: $0) ?? start, calories: nil, goal: nil) }
    }

    /// "Wednesday 18, 1051 of 1750 calories" for VoiceOver.
    private func dayLabel(_ day: WeekDay) -> String {
        let eaten = day.calories.map { "\(Diet.whole($0)) of \(Diet.whole(day.goal)) calories" } ?? "nothing logged"
        return "\(Diet.title(day.date)), \(eaten)"
    }

    // MARK: The day

    /// Totals and the hours, or a wait, an empty day, or a problem.
    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().tint(Theme.frost)
                Text("Loading what you ate…").foregroundStyle(Theme.frostDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        case .unreachable:
            note("Jarvis can’t be reached, so the food log can’t be shown right now.", icon: "wifi.exclamationmark")
        case .failed(let words):
            note(words, icon: "exclamationmark.triangle")
        case .ready(let day):
            totals(day)
            if day.isEmpty {
                note("Nothing logged \(model.date == today ? "yet today" : "this day"). Tell Jarvis what you ate, or send him a photo.", icon: "fork.knife")
            } else {
                ForEach(Diet.hours(day.items)) { hour in
                    hourCard(hour, isNow: model.date == today && hour.hour == Diet.currentHour())
                }
                Text("To fix an entry, tell Jarvis in Chat.")
                    .font(.caption)
                    .foregroundStyle(Theme.frostDim)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }

    /// A plain message with an icon.
    private func note(_ words: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(Theme.frostDim)
            Text(words).multilineTextAlignment(.center).foregroundStyle(Theme.frost)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassPanel()
    }

    // MARK: Totals

    /// Calories, protein, fat and carbs against their goals, each with a
    /// thin bar (full when over). A total with no goal shows no bar.
    private func totals(_ day: NutritionDay) -> some View {
        let columns = width == .regular ? 4 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
            total("Calories", day.totals.calories, goal: day.goals.calories, unit: "", tint: Theme.moss)
            total("Protein", day.totals.protein, goal: day.goals.protein, unit: "g", tint: Theme.glacier)
            total("Fat", day.totals.fat, goal: day.goals.fat, unit: "g", tint: Theme.ember)
            total("Carbs", day.totals.carbs, goal: day.goals.carbs, unit: "g", tint: Theme.rose)
        }
        .padding(14)
        .glassPanel()
    }

    /// One total: "1052 / 1750" and its bar.
    private func total(_ name: String, _ value: Double?, goal: Double?, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(Theme.frostDim)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Diet.whole(value) + unit).font(.title3.weight(.semibold)).foregroundStyle(Theme.frost)
                if let goal {
                    Text("/ \(Diet.whole(goal))\(unit)").font(.footnote).foregroundStyle(Theme.frostDim)
                }
            }
            if let fraction = Diet.fraction(value ?? 0, of: goal) {
                GeometryReader { area in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        // Past the goal the full bar turns ember.
                        Capsule().fill(Diet.isOver(value, goal: goal) ? Theme.ember : tint).frame(width: area.size.width * fraction)
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Hours

    /// One hour with food: its time and subtotal, then a row per item.
    private func hourCard(_ hour: DietHour, isNow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(hour.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isNow ? Theme.glacier : Theme.frost)
                if isNow {
                    Text("Now").font(.caption2.weight(.bold)).foregroundStyle(Theme.glacier)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.glacier.opacity(0.15)))
                }
                Spacer()
                Text("\(Diet.whole(hour.totals.calories)) kcal  \(Diet.macroLine(hour.totals))")
                    .font(.caption)
                    .foregroundStyle(Theme.frostDim)
            }
            ForEach(hour.items) { item in
                itemRow(item)
            }
        }
        .padding(14)
        .glassPanel()
    }

    /// Name and portion on the left; calories and macros on the right.
    private func itemRow(_ item: FoodItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline).foregroundStyle(Theme.frost).fixedSize(horizontal: false, vertical: true)
                if let portion = item.portion {
                    Text(portion).font(.caption).foregroundStyle(Theme.frostDim)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Diet.whole(item.macros.calories)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.frost)
                Text(Diet.macroLine(item.macros)).font(.caption).foregroundStyle(Theme.frostDim)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
