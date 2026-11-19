// What Dylan has already seen in Reports, Playbooks and Diet, kept on the
// device, for the orange "new" dots on the Home tiles (Dylan, 2026-11-19).
// The rules are JarvisKit's SeenTracker; this only stores. On a first
// launch nothing is stored, so the current state becomes the seen one and
// no dot shows.
import Foundation
import JarvisKit

@MainActor
enum SeenStore {
    private static let reportsKey = "seen.reports"
    private static let playbooksKey = "seen.playbooks"
    private static let dietKey = "seen.diet"
    /// Stored for "seen, and nothing was logged that day".
    private static let nothing = "-"

    /// The report ids he'd seen; nil before anything was stored.
    static var reports: [String]? { UserDefaults.standard.stringArray(forKey: reportsKey) }
    /// The playbook ids he'd seen; nil before anything was stored.
    static var playbooks: [String]? { UserDefaults.standard.stringArray(forKey: playbooksKey) }
    /// The Diet mark he'd seen: .none before anything was stored.
    static var diet: String?? {
        guard let raw = UserDefaults.standard.string(forKey: dietKey) else { return .none }
        return .some(raw == nothing ? nil : raw)
    }

    /// Marks these report ids seen.
    static func seeReports(_ ids: [String]) { UserDefaults.standard.set(ids, forKey: reportsKey) }
    /// Marks these playbook ids seen.
    static func seePlaybooks(_ ids: [String]) { UserDefaults.standard.set(ids, forKey: playbooksKey) }
    /// Marks Diet seen as it stands.
    static func seeDiet(_ mark: String?) { UserDefaults.standard.set(mark ?? nothing, forKey: dietKey) }

    /// The first launch: whatever is there now counts as seen.
    static func baseline(reports: [String]?, diet: String??, playbooks: [String]?) {
        if self.reports == nil, let reports { seeReports(reports) }
        if self.diet == nil, let diet { seeDiet(diet) }
        if self.playbooks == nil, let playbooks { seePlaybooks(playbooks) }
    }
}
