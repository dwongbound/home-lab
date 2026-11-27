// The Money screen's rules (Dylan, 2026-11-26: port transactions, accounts
// and category picks from the web page before it goes). Copilot's connector
// is read-only, so a category picked here waits on the PC (POST
// /api/money/picks) until he applies it in Copilot; once the digest shows a
// real category the pick drops off by itself. Same rules as the page had.
import Foundation

/// One category picked here for an unsorted purchase.
public struct MoneyPick: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let category: String
    public let merchant: String
    public let date: String
    public let amount: Double
}

/// The snapshot's `moneyPicks`: the picks (the reminder time is unused in the apps).
struct MoneyPicks: Decodable {
    let picks: [MoneyPick]
}

extension Money.Transaction {
    /// A purchase still needing a real category: not money coming in, not a
    /// transfer between his own accounts, and in "Other" or none.
    public var needsCategory: Bool {
        guard amount > 0, type != "transfer" else { return false }
        return Money.unsorted.contains((category ?? "").trimmingCharacters(in: .whitespaces).lowercased())
    }
}

extension Money {
    /// Category names that mean "not sorted yet".
    static let unsorted: Set<String> = ["", "other", "uncategorized", "uncategorised"]

    /// Accounts by kind (Cash, Cards, Investments, Loans, Other), biggest first, empty ones left out.
    public var accountGroups: [(label: String, total: Double, accounts: [Account])] {
        let kinds = [("cash", "Cash"), ("credit", "Cards"), ("investment", "Investments"), ("loan", "Loans"), ("other", "Other")]
        return kinds.compactMap { kind, label in
            let list = accounts.filter { $0.kind == kind && abs($0.balance) >= 0.005 }.sorted { $0.balance > $1.balance }
            guard !list.isEmpty else { return nil }
            return (label, list.reduce(0) { $0 + $1.balance }, list)
        }
    }

    /// Purchases still to sort that haven't been picked here yet.
    public func stillToPick(_ picks: [MoneyPick]) -> [Transaction] {
        let picked = Set(picks.map(\.id))
        return recent.filter { $0.needsCategory && !picked.contains($0.id) }
    }

    /// Categories to offer: Copilot's from the digest, then ones picked before, no repeats.
    public func categoryChoices(_ picks: [MoneyPick]) -> [String] {
        var seen = Set<String>()
        var choices: [String] = []
        for name in categories.map(\.name) + picks.map(\.category) {
            let clean = name.trimmingCharacters(in: .whitespaces)
            let key = clean.lowercased()
            if Self.unsorted.contains(key) || seen.contains(key) { continue }
            seen.insert(key)
            choices.append(clean)
        }
        return choices
    }

    /// "$12.40" with cents, for one purchase; money coming in reads "+$1,200.00".
    public static func amount(_ value: Double) -> String {
        let format = NumberFormatter()
        format.numberStyle = .currency
        format.currencyCode = "USD"
        format.locale = Locale(identifier: "en_US")
        let text = format.string(from: NSNumber(value: abs(value))) ?? "$\(abs(value))"
        return value < 0 ? "+" + text : text
    }
}

extension JarvisClient {
    /// Saves a category for one unsorted purchase (kept on the PC until applied in Copilot).
    public func pickCategory(_ transaction: Money.Transaction, category: String) async throws {
        _ = try await send(request("api/money/picks", method: "POST", json: [
            "op": "pick", "id": transaction.id, "category": category,
            "merchant": transaction.merchant, "date": transaction.date, "amount": transaction.amount,
        ]))
    }

    /// Forgets picks: applied in Copilot, or picked by mistake.
    public func clearPicks(_ ids: [String]) async throws {
        _ = try await send(request("api/money/picks", method: "POST", json: ["op": "clear", "ids": ids]))
    }
}

// What Home's Money card shows instead of net worth (Dylan 2026-11-26:
// "show more useful metrics that id care about"): the month's spending
// against budget and against the calendar, and what's left a day.
extension Money.Spending {
    /// Where spending "should" be by now if the budget were spread evenly
    /// over the month; nil without a budget.
    public func pace(now: Date = Date(), calendar: Calendar = .current) -> Double? {
        guard let budget, budget > 0, let days = calendar.range(of: .day, in: .month, for: now)?.count else { return nil }
        let day = calendar.component(.day, from: now)
        return budget * Double(day) / Double(days)
    }

    /// Spent minus pace: above zero is ahead of pace (spending too fast).
    public func aheadOfPace(now: Date = Date(), calendar: Calendar = .current) -> Double? {
        pace(now: now, calendar: calendar).map { thisMonth - $0 }
    }

    /// What's left of the budget per remaining day, today included; nil
    /// without a budget, 0 once it's spent.
    public func leftPerDay(now: Date = Date(), calendar: Calendar = .current) -> Double? {
        guard let budget, budget > 0, let days = calendar.range(of: .day, in: .month, for: now)?.count else { return nil }
        let remaining = days - calendar.component(.day, from: now) + 1
        return max(0, budget - thisMonth) / Double(max(remaining, 1))
    }
}

extension Money {
    /// The month's biggest categories, most spent first.
    public func topCategories(_ count: Int = 3) -> [Category] {
        Array(categories.filter { $0.spent > 0 }.sorted { $0.spent > $1.spent }.prefix(count))
    }
}
