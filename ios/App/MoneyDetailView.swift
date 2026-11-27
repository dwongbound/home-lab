// The Money screen, opened by tapping Home's Money card once Face ID has
// shown it (Dylan, 2026-11-26: port transactions, accounts and category
// picks from the web page). Purchases Copilot left unsorted come first,
// each with a menu of categories; picks wait on the PC until he applies
// them in Copilot, then "Done" clears them. Then accounts by kind and the
// recent purchases. Read from the snapshot; closes when money locks again.
import SwiftUI
import JarvisKit

struct MoneyDetailView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var today: TodayModel
    @Environment(\.dismiss) private var dismiss
    @State private var busy: String?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                if let money = today.snapshot?.money {
                    toSort(money)
                    picked
                    accounts(money)
                    recent(money)
                } else {
                    Text("No money from Copilot yet.").foregroundStyle(Theme.frostDim).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.sky.ignoresSafeArea())
            .navigationTitle("Money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetClose { dismiss() } }
            .alert("Couldn't save", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("Close") { problem = nil }
            } message: {
                Text(problem ?? "")
            }
        }
        // Money hides the moment it locks (the app left the screen).
        .onChange(of: app.moneyUnlocked) { _, open in if !open { dismiss() } }
    }

    private var picks: [MoneyPick] { today.snapshot?.moneyPicks ?? [] }

    // MARK: Sections

    /// Unsorted purchases, each with a menu of categories to pick from.
    @ViewBuilder private func toSort(_ money: Money) -> some View {
        let list = money.stillToPick(picks)
        if !list.isEmpty {
            Section {
                ForEach(list) { purchase in
                    Menu {
                        ForEach(money.categoryChoices(picks), id: \.self) { name in
                            Button(name) { Task { await pick(purchase, name) } }
                        }
                    } label: {
                        row(purchase, note: busy == purchase.id ? "Saving…" : "Pick", noteTint: Theme.ember)
                    }
                    .disabled(busy != nil)
                }
                .fullWidthSeparators()
            } header: {
                Text("To sort")
            } footer: {
                Text("Copilot left these without a category. Pick one here, then apply it in Copilot.")
            }
        }
    }

    /// Picks waiting to be applied in Copilot; swipe one off, or Done clears all.
    @ViewBuilder private var picked: some View {
        if !picks.isEmpty {
            Section {
                ForEach(picks) { pick in
                    HStack(spacing: 10) {
                        Circle().fill(Color.yellow).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pick.merchant.isEmpty ? "Purchase" : pick.merchant).lineLimit(1)
                            Text(pick.category).font(.caption).foregroundStyle(Theme.frostDim)
                        }
                        Spacer()
                        Text(Money.amount(pick.amount)).monospacedDigit().foregroundStyle(Theme.frostDim)
                    }
                    .frame(minHeight: 44)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Clear", role: .destructive) { Task { await clear([pick.id]) } }
                    }
                }
                .fullWidthSeparators()
                Button("Done in Copilot") { Task { await clear(picks.map(\.id)) } }
                    .frame(minHeight: 44)
                    .disabled(busy != nil)
            } header: {
                Text("Picked, apply in Copilot")
            } footer: {
                Text("Each one also drops off by itself once Copilot shows its category.")
            }
        }
    }

    /// Accounts by kind with their totals.
    @ViewBuilder private func accounts(_ money: Money) -> some View {
        ForEach(money.accountGroups, id: \.label) { group in
            Section {
                ForEach(group.accounts) { account in
                    HStack {
                        Text(account.name).lineLimit(1)
                        Spacer()
                        Text(MoneyText.dollars(account.balance)).monospacedDigit().foregroundStyle(Theme.frostDim)
                    }
                    .frame(minHeight: 44)
                }
                .fullWidthSeparators()
            } header: {
                HStack {
                    Text(group.label)
                    Spacer()
                    Text(MoneyText.dollars(group.total)).monospacedDigit()
                }
            }
        }
    }

    /// The digest's recent purchases and payments, newest first.
    @ViewBuilder private func recent(_ money: Money) -> some View {
        if !money.recent.isEmpty {
            Section("Recent") {
                ForEach(money.recent) { purchase in
                    row(purchase, note: purchase.needsCategory ? nil : purchase.category, noteTint: Theme.frostDim)
                }
                .fullWidthSeparators()
            }
        }
    }

    /// Merchant, date and account; the amount on the right, money in green.
    private func row(_ purchase: Money.Transaction, note: String?, noteTint: Color) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(purchase.merchant).lineLimit(1).foregroundStyle(Theme.frost)
                Text([Self.day(purchase.date), purchase.account, purchase.pending == true ? "Pending" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.frostDim).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.amount(purchase.amount)).monospacedDigit()
                    .foregroundStyle(purchase.amount < 0 ? Theme.moss : Theme.frost)
                if let note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(noteTint).lineLimit(1)
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    /// "Nov 24" from "2026-11-24" (or an ISO time).
    static func day(_ raw: String) -> String? {
        let key = String(raw.prefix(10))
        guard let date = ActivityDay.date(key) else { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.dateFormat = "MMM d"
        return format.string(from: date)
    }

    // MARK: Changes

    private func pick(_ purchase: Money.Transaction, _ category: String) async {
        busy = purchase.id
        defer { busy = nil }
        do {
            try await app.client.pickCategory(purchase, category: category)
            Haptics.play(.runOK)
            await today.load(app: app)
        } catch {
            Haptics.play(.runFailed)
            problem = error.localizedDescription
        }
    }

    private func clear(_ ids: [String]) async {
        busy = "clear"
        defer { busy = nil }
        do {
            try await app.client.clearPicks(ids)
            Haptics.play(.runOK)
            await today.load(app: app)
        } catch {
            Haptics.play(.runFailed)
            problem = error.localizedDescription
        }
    }
}
