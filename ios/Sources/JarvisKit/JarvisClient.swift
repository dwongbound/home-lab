// Talks to the home page server on the PC, the same front door the web
// page uses. `tailscale serve` adds Dylan's Tailscale login to every
// request, so there is no sign-in here; the phone just has to be on the
// tailnet.
import Foundation

/// What went wrong talking to the PC, worded for Dylan.
public enum JarvisError: Error, Equatable, LocalizedError {
    /// The request never reached the PC: Tailscale off, no signal, PC asleep.
    case unreachable
    /// The PC answered, but not with a yes.
    case server(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .unreachable:
            return "Can’t reach Jarvis. Is Tailscale on?"
        case .server(_, let message):
            return message
        }
    }
}

/// The app's one way to the PC.
public struct JarvisClient: Sendable {
    /// The home page's address, e.g. https://jarvis.snakebird-ph.ts.net
    public let base: URL
    private let session: URLSession

    /// The address the app ships with; changeable in Settings.
    public static let defaultBase = URL(string: "https://jarvis.snakebird-ph.ts.net")!

    /// A client for `base`. Tests pass their own session.
    public init(base: URL = JarvisClient.defaultBase, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    /// A request with the headers the server checks: `x-home-lab` on every
    /// write, and an `Origin` matching the server, which the Talk socket
    /// (server/talk.mjs) requires and the rest ignore.
    func request(_ path: String, method: String = "GET", json: [String: Any]? = nil) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("1", forHTTPHeaderField: "x-home-lab")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }
        return request
    }

    /// "https://host" for the Origin header (no path, no trailing slash).
    var origin: String {
        var parts = URLComponents()
        parts.scheme = base.scheme
        parts.host = base.host
        parts.port = base.port
        return parts.string ?? base.absoluteString
    }

    /// Sends a message and streams Jarvis's reply as it's written. `offerId`
    /// says which offer card's Start began it, so he knows the context.
    public func chat(_ text: String, offerId: String? = nil) -> AsyncThrowingStream<ChatEvent, Error> {
        var body: [String: Any] = ["text": text]
        if let offerId { body["offerId"] = offerId }
        let request = request("api/jarvis/chat", method: "POST", json: body)
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status != 200 {
                        throw JarvisError.server(status: status, message: "Jarvis answered \(status)")
                    }
                    for try await line in bytes.lines {
                        if let event = ChatEvent.parse(line: line) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch let error as JarvisError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: JarvisError.unreachable)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The chat so far, oldest first.
    public func history() async throws -> [ChatTurn] {
        struct Body: Decodable { let turns: [ChatTurn]? }
        let body: Body = try await get("api/jarvis/history")
        return body.turns ?? []
    }

    /// What Jarvis is still waiting on an answer for.
    public func pendingApprovals() async throws -> [Approval] {
        struct Body: Decodable { let pending: [Approval]? }
        let body: Body = try await get("api/jarvis/approvals")
        return body.pending ?? []
    }

    /// Approve (ok) or Deny one thing Jarvis asked to do.
    public func answer(approval id: String, ok: Bool) async throws {
        try await post("api/jarvis/approve", ["id": id, "ok": ok])
    }

    /// "That was wrong" on a reply: what was asked, what he said, what Dylan wanted.
    public func flagWrong(question: String, answer: String, note: String) async throws {
        try await post("api/jarvis/feedback", ["question": question, "answer": answer, "note": note])
    }

    /// Hide on an offer card.
    public func hideOffer(_ id: String) async throws {
        try await post("api/jarvis/offers/hide", ["id": id])
    }

    /// Wakes Jarvis's model when the chat opens, so the first reply is quick.
    public func warm() async {
        _ = try? await session.data(for: request("api/jarvis/warm", method: "POST"))
    }

    /// The home page snapshot (Today tab).
    public func snapshot() async throws -> Snapshot {
        try await get("api/snapshot")
    }

    /// GETs `path` and decodes the JSON body.
    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(request(path))
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// POSTs a JSON body; throws unless the server says yes.
    private func post(_ path: String, _ json: [String: Any]) async throws {
        _ = try await send(request(path, method: "POST", json: json))
    }

    /// Sends a request; a network failure reads as "can't reach", a non-2xx
    /// answer as the server's own message when it gives one.
    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw JarvisError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return data }
        struct Message: Decodable { let message: String? }
        let message = (try? JSONDecoder().decode(Message.self, from: data))?.message
        throw JarvisError.server(status: status, message: message ?? "Jarvis answered \(status)")
    }
}
