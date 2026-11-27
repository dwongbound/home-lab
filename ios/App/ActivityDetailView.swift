// The Activity screen, opened by tapping Home's Activity card (Dylan,
// 2026-11-26: "activity should also have a details when clicked. and it
// should be able to show by day just like diet and sleep"). Built like
// Sleep: the week pinned at the top as small ring circles with the week's
// average steps; below, one day at a time (today at first), tap a day or
// swipe the page sideways to move. Read from Health on the phone only.
import SwiftUI
import JarvisKit

struct ActivityDetailView: View {
    @ObservedObject var sync: ActivitySync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The day shown (nil: today).
    @State private var chosen: String?
    /// Which week the row shows: 0 this week, 1 the one before.
    @State private var page = 0

    private static let colors = [ActivityCard.move, ActivityCard.exercise, ActivityCard.stand]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.sky.ignoresSafeArea()
                if let days = sync.days, !days.isEmpty {
                    VStack(spacing: 0) {
                        weekHeader(days)
                        pager(days)
                    }
                } else if sync.days != nil {
                    Text("Nothing from Apple Health yet.").foregroundStyle(Theme.frostDim)
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading your activity").foregroundStyle(Theme.frostDim)
                    }
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetClose { dismiss() } }
        }
        .task { await sync.loadDays() }
    }

    private func shown(_ days: [ActivityDay]) -> String {
        chosen ?? days.last?.day ?? ""
    }

    /// The days side by side, oldest on the left; one swipe is one day.
    private func pager(_ days: [ActivityDay]) -> some View {
        let selected = Binding<String?>(
            get: { shown(days) },
            set: { key in
                guard let key, key != shown(days) else { return }
                Haptics.play(.tab)
                chosen = key
                let index = days.firstIndex { $0.day == key } ?? days.count - 1
                page = index < days.count - 7 ? 1 : 0
            })
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(days) { day in
                    ScrollView(.vertical) {
                        dayPanel(day)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .containerRelativeFrame(.horizontal)
                    .id(day.day)
                    .task { await sync.loadHours(day.day) }
                }
            }
            .scrollTargetLayout()
            .background(PagerNoBounce())
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: selected)
    }

    /// The week row: average steps, then seven days as small ring circles.
    private func weekHeader(_ days: [ActivityDay]) -> some View {
        let end = days.count - page * 7
        let week = Array(days[max(0, end - 7)..<max(0, end)])
        let current = shown(days)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                if let average = ActivityDay.averageSteps(week) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(ActivityGlance.whole(average)).font(.title3.weight(.bold)).monospacedDigit()
                        Text("avg steps").font(.caption).foregroundStyle(Theme.frostDim)
                    }
                }
                let closed = week.filter { $0.ringsClosed == 3 }.count
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(closed) of \(week.count)").font(.title3.weight(.bold)).monospacedDigit()
                    Text("days all rings closed").font(.caption).foregroundStyle(Theme.frostDim)
                }
                Spacer()
            }
            HStack(spacing: 4) {
                ForEach(week) { day in
                    Button {
                        Haptics.play(.tab)
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { chosen = day.day }
                    } label: {
                        VStack(spacing: 6) {
                            Text(ActivityDay.weekday(day.day)).font(.caption2.weight(.semibold))
                                .foregroundStyle(day.day == current ? Theme.frost : Theme.frostDim)
                            ActivityRings(rings: day.rings, colors: Self.colors)
                                .frame(width: 34, height: 34)
                                .opacity(day.recorded ? 1 : 0.35)
                                .padding(3)
                                .background(Circle().fill(day.day == current ? Color.white.opacity(0.12) : .clear))
                            Text(ActivityDay.dayNumber(day.day)).font(.caption2.weight(day.day == current ? .bold : .regular))
                                .foregroundStyle(day.day == current ? Theme.frost : Theme.frostDim)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ActivityDay.heading(day.day) + (day.steps.map { ", \(ActivityGlance.whole($0)) steps" } ?? ""))
                    .accessibilityAddTraits(day.day == current ? .isSelected : [])
                }
            }
            // Swiping the row moves a week.
            .gesture(DragGesture(minimumDistance: 30).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                if drag.translation.width > 0, page == 0, days.count > 7 { withAnimation(.smooth) { page = 1 } }
                if drag.translation.width < 0, page > 0 { withAnimation(.smooth) { page = 0 } }
            })
        }
        .padding(14)
        .glassPanel()
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// One day: rings with numbers, steps by hour, then heart and climbing tiles.
    private func dayPanel(_ day: ActivityDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ActivityDay.heading(day.day))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.frostDim)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 18) {
                    ActivityRings(rings: day.rings, colors: Self.colors).frame(width: 110, height: 110)
                    VStack(alignment: .leading, spacing: 8) {
                        ringLine("Move", day.moveKcal, goal: day.moveGoal, unit: "kcal", tint: ActivityCard.move)
                        ringLine("Exercise", day.exerciseMin, goal: day.exerciseGoal ?? 30, unit: "min", tint: ActivityCard.exercise)
                        ringLine("Stand", day.standHours, goal: day.standGoal ?? 12, unit: "hr", tint: ActivityCard.stand)
                    }
                    Spacer(minLength: 0)
                }
                HourBars(steps: day.hourlySteps, total: day.steps)
                let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: sizeClass == .regular ? 3 : 2)
                LazyVGrid(columns: columns, spacing: 10) {
                    if let value = day.restingHR { tile("Resting heart", "\(Int(value.rounded())) bpm", "heart.fill", Theme.rose) }
                    if let value = day.hrv { tile("Heart variability", "\(Int(value.rounded())) ms", "waveform.path.ecg", Theme.glacier) }
                    if let value = day.walkingHR { tile("Walking heart", "\(Int(value.rounded())) bpm", "figure.walk", Theme.rose) }
                    if let value = day.flights, value > 0 { tile("Flights", ActivityGlance.whole(value), "figure.stairs", Theme.moss) }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.07)))
        }
    }

    /// "Move 412 / 600 kcal" in the ring's colour.
    private func ringLine(_ name: String, _ value: Double?, goal: Double?, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.caption).foregroundStyle(Theme.frostDim)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map { ActivityGlance.whole($0) } ?? "–").font(.headline.weight(.bold)).foregroundStyle(tint).monospacedDigit()
                Text(goal.map { "/ \(ActivityGlance.whole($0)) \(unit)" } ?? unit).font(.footnote).foregroundStyle(Theme.frostDim)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A small tile: icon, name and number.
    private func tile(_ title: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(Theme.frostDim).lineLimit(1)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
        .accessibilityElement(children: .combine)
    }
}

/// The day's steps hour by hour, with the total; a thin line until read.
private struct HourBars: View {
    let steps: [Double]
    let total: Double?
    /// The hour a finger picked (Dylan, 2026-11-27: "more interactive").
    @State private var picked: Int?

    var body: some View {
        let top = max(steps.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let hour = picked {
                    let value = steps.indices.contains(hour) ? steps[hour] : 0
                    Text("\(ChartPick.hourName(hour))–\(ChartPick.hourName(hour + 1))").font(.caption.weight(.semibold)).foregroundStyle(Theme.frost)
                    Spacer()
                    Text("\(ActivityGlance.whole(value)) steps").font(.caption.weight(.semibold)).foregroundStyle(Theme.moss).monospacedDigit()
                } else {
                    Text("Steps").font(.caption.weight(.semibold)).foregroundStyle(Theme.frostDim)
                    Spacer()
                    Text(total.map { ActivityGlance.whole($0) } ?? "–").font(.caption).foregroundStyle(Theme.frostDim).monospacedDigit()
                }
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    let value = steps.indices.contains(hour) ? steps[hour] : 0
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.moss.opacity(value > 0 ? (picked == nil || picked == hour ? 0.9 : 0.35) : 0.2))
                        .frame(height: max(2, 50 * CGFloat(value / top)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 50, alignment: .bottom)
            .chartScrub(count: 24, bars: true, picked: $picked)
            .animation(.easeOut(duration: 0.15), value: picked)
            HStack {
                Text("12 AM"); Spacer(); Text("6 AM"); Spacer(); Text("12 PM"); Spacer(); Text("6 PM")
            }
            .font(.caption2)
            .foregroundStyle(Theme.frostFaint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Steps by hour" + (total.map { ", \(ActivityGlance.whole($0)) in all" } ?? ""))
    }
}
