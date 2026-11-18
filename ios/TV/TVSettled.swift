// The TV's record of approvals that are over (JarvisKit SettledApprovals),
// shared by the board and the chat, so an approval answered anywhere (out
// loud, on the phone, here) never comes back as a card, a notice row or a
// count on the chip. Kept for a day, across relaunches.
import Foundation
import JarvisKit

@MainActor
final class TVSettled: ObservableObject {
    static let shared = TVSettled()

    @Published private(set) var record = SettledApprovals.load()

    /// Marks it over. `replace` lets Jarvis's own account beat ours.
    func settle(_ id: String, line: String, replace: Bool = false) {
        if record.isSettled(id) {
            guard replace else { return }
            record.unsettle(id)
        }
        record.prune()
        record.settle(id, line: line)
        record.save()
    }

    /// Takes back an answer that never reached Jarvis.
    func unsettle(_ id: String) {
        record.unsettle(id)
        record.save()
    }
}
