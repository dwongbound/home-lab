// The Apple TV's chat (Dylan, 2026-11-18: "it should just be a continuous
// conversation, where I can use dictation to 'text it' and it would
// respond… during dictation the right side of the screen turns into the
// chat"). The running conversation as lines, built up from the streaming
// chat events, and when the chat slides away again. The TV draws it.
import Foundation

/// One line of the TV chat.
public struct TVChatLine: Equatable, Identifiable, Sendable {
    public enum Who: Equatable, Sendable { case me, jarvis }
    public let id: Int
    public let who: Who
    public var text: String
    /// An approval asked in this reply, and how it ended (nil while waiting).
    public var approval: Approval?
    public var outcome: String?
}

/// The conversation so far and what Jarvis is doing.
public struct TVChat: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case idle, thinking, answering }
    public private(set) var lines: [TVChatLine] = []
    public private(set) var phase: Phase = .idle
    /// The slow lookup he's on ("Searching the web."), or nil.
    public private(set) var working: String?
    public var problem: String?
    private var nextId = 0

    /// Lines kept on screen; older ones scroll away for good.
    public static let keep = 30
    /// Seconds of quiet after the last reply before the chat slides away.
    public static let idleSeconds: Double = 60

    public init() {}

    /// The last few turns of the conversation Jarvis already has, so the
    /// TV picks up where the phone left off.
    public mutating func seed(_ history: [ChatTurn], count: Int = 6) {
        guard lines.isEmpty else { return }
        for turn in history.suffix(count) where !turn.text.isEmpty {
            append(turn.isUser ? .me : .jarvis, turn.text)
        }
    }

    /// Dylan sends a line: it shows straight away and Jarvis starts thinking.
    public mutating func send(_ text: String) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, phase == .idle else { return nil }
        append(.me, clean)
        phase = .thinking
        problem = nil
        return clean
    }

    /// One event from the reply stream.
    public mutating func apply(_ event: ChatEvent) {
        switch event {
        case .delta(let words):
            if phase != .answering || lines.last?.who != .jarvis || lines.last?.approval != nil {
                append(.jarvis, "")
            }
            lines[lines.count - 1].text += words
            phase = .answering
        case .working(let label):
            working = label
        case .workingDone:
            working = nil
        case .approval(let approval):
            guard !lines.contains(where: { $0.approval?.id == approval.id }) else { return }
            append(.jarvis, "")
            lines[lines.count - 1].approval = approval
        case .approvalDone(let id, let ok, let by, let later):
            settle(id, ApprovalWording.outcomeText(ok: ok, later: later, by: by))
        case .error(let message):
            problem = message
        default:
            break
        }
    }

    /// The reply finished (or failed): back to waiting for Dylan.
    public mutating func finish(error: String? = nil) {
        if let error { problem = error }
        working = nil
        phase = .idle
        // A reply that never wrote anything leaves no empty bubble.
        if let last = lines.last, last.who == .jarvis, last.text.isEmpty, last.approval == nil {
            lines.removeLast()
        }
    }

    /// Writes how an approval ended (nil puts its buttons back).
    public mutating func settle(_ id: String, _ outcome: String?) {
        guard let index = lines.firstIndex(where: { $0.approval?.id == id }) else { return }
        lines[index].outcome = outcome
    }

    /// True while an approval is waiting for Approve or Deny.
    public var approvalWaiting: Bool {
        lines.contains { $0.approval != nil && $0.outcome == nil }
    }

    /// The text of the reply just finished, for reading aloud.
    public var lastReply: String? {
        guard let last = lines.last, last.who == .jarvis, !last.text.isEmpty else { return nil }
        return last.text
    }

    /// The chat slides away after a minute of quiet, unless Jarvis is still
    /// answering or an approval waits.
    public func shouldClose(lastActivity: Date, now: Date) -> Bool {
        phase == .idle && !approvalWaiting && now.timeIntervalSince(lastActivity) >= Self.idleSeconds
    }

    private mutating func append(_ who: TVChatLine.Who, _ text: String) {
        lines.append(TVChatLine(id: nextId, who: who, text: text))
        nextId += 1
        if lines.count > Self.keep { lines.removeFirst(lines.count - Self.keep) }
    }
}
