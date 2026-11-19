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
    public func chat(_ text: String, offerId: String? = nil, photos: [ChatPhoto] = []) -> AsyncThrowingStream<ChatEvent, Error> {
        let request = chatRequest(text, offerId: offerId, photos: photos)
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

    /// The chat request: the words, which offer started it, and up to four
    /// photos as {media_type, data}. Text may be empty when photos go.
    public func chatRequest(_ text: String, offerId: String? = nil, photos: [ChatPhoto] = []) -> URLRequest {
        var body: [String: Any] = ["text": text]
        if let offerId { body["offerId"] = offerId }
        if !photos.isEmpty { body["images"] = photos.prefix(PhotoLimits.maxPhotos).map(\.json) }
        var request = request("api/jarvis/chat", method: "POST", json: body)
        // Photos take a while to upload on a slow line.
        if !photos.isEmpty { request.timeoutInterval = 120 }
        return request
    }

    /// The request answering a meal question: same, leftovers or new.
    public func mealRequest(key: String, choice: String) -> URLRequest {
        request("api/jarvis/chat/meal", method: "POST", json: ["key": key, "choice": choice])
    }

    /// Answers a meal question; Jarvis's reply comes back as `message`.
    public func answerMeal(key: String, choice: String) async throws -> String {
        struct Body: Decodable { let ok: Bool?; let message: String? }
        let data = try await send(mealRequest(key: key, choice: choice))
        let body = try? JSONDecoder().decode(Body.self, from: data)
        return body?.message ?? "Done."
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

    /// Approve (ok) or Deny one thing Jarvis asked to do. An approval
    /// that's already over comes back `.gone`, not as an error; only not
    /// reaching Jarvis at all throws.
    public func answer(approval id: String, ok: Bool) async throws -> ApprovalReply {
        let request = request("api/jarvis/approve", method: "POST", json: ["id": id, "ok": ok])
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw JarvisError.unreachable
        }
        return ApprovalReply.read(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }

    /// One report's page (GET /reports/{id}). Only a good id is ever fetched.
    public func report(id: String) async -> ReportFetch {
        guard Reports.isId(id) else { return .gone }
        var request = request("reports/\(id)")
        request.timeoutInterval = 30
        do {
            let (data, response) = try await session.data(for: request)
            return ReportFetch.read(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            return .failed(JarvisError.unreachable.localizedDescription)
        }
    }

    /// One day's food (the Diet screen); nil when Jarvis can't say (an
    /// older Jarvis, Jarvis down, or no Tailscale login).
    public func nutritionDay(date: String) async throws -> NutritionDay? {
        struct Body: Decodable { let day: NutritionDay? }
        let data = try await send(request("api/jarvis/nutrition/day", query: ["date": date]))
        let body = try JSONDecoder().decode(Body.self, from: data)
        return body.day
    }

    /// The week's calorie rings, Monday first; nil when Jarvis can't say.
    public func nutritionWeek(start: String) async throws -> NutritionWeek? {
        struct Body: Decodable { let week: NutritionWeek? }
        let data = try await send(request("api/jarvis/nutrition/week", query: ["start": start]))
        let body = try JSONDecoder().decode(Body.self, from: data)
        return body.week
    }

    /// Keeps a chat message (by its history turn id) as a yellow dot.
    public func keep(turnId: Int) async throws -> KeepResult {
        try await keepChange("api/jarvis/notices/keep", ["turnId": turnId])
    }

    /// Keeps an existing notice (by its id) instead of clearing it.
    public func keep(noticeId: String) async throws -> KeepResult {
        try await keepChange("api/jarvis/notices/keep", ["id": noticeId])
    }

    /// Lets a kept item go.
    public func unkeep(noticeId: String) async throws -> KeepResult {
        try await keepChange("api/jarvis/notices/unkeep", ["id": noticeId])
    }

    /// One keep or unkeep POST; a refusal comes back as a result.
    private func keepChange(_ path: String, _ body: [String: Any]) async throws -> KeepResult {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request(path, method: "POST", json: body))
        } catch {
            throw JarvisError.unreachable
        }
        return KeepResult.read(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }

    /// Jarvis's playbooks; nil when he can't say (older Jarvis, or down).
    public func playbooks() async throws -> [Playbook]? {
        Playbooks.list(from: try await send(request("api/jarvis/playbooks")))
    }

    /// Switches a playbook on or off by saving it whole with only that changed.
    public func setPlaybook(_ playbook: Playbook, enabled: Bool) async throws -> PlaybookResult {
        try await playbookChange(["op": "save", "playbook": playbook.draft(enabled: enabled)])
    }

    /// Runs a playbook now. Jarvis answers within about 50 s; a longer run
    /// comes back with detail "running" and carries on.
    public func runPlaybook(id: String) async throws -> PlaybookResult {
        try await playbookChange(["op": "run", "id": id])
    }

    /// One POST to /api/jarvis/playbooks; a refusal comes back as a result,
    /// not an error, so its words can go on screen.
    private func playbookChange(_ body: [String: Any]) async throws -> PlaybookResult {
        var request = request("api/jarvis/playbooks", method: "POST", json: body)
        request.timeoutInterval = 75
        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw JarvisError.unreachable
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return PlaybookResult(json: object)
    }

    /// Keep a report past its days, or let it go again.
    public func keepReport(id: String, keep: Bool) async throws {
        try await post("api/jarvis/reports", ["op": "keep", "id": id, "keep": keep])
    }

    /// Delete a report now.
    public func deleteReport(id: String) async throws {
        try await post("api/jarvis/reports", ["op": "delete", "id": id])
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

    /// A GET with query parameters (`appendingPathComponent` would escape a "?").
    func request(_ path: String, query: [String: String]) -> URLRequest {
        var request = request(path)
        if let url = request.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.url = parts.url
        }
        return request
    }

    /// GETs `path` and decodes the JSON body.
    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(request(path))
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// POSTs a JSON body; throws unless the server says yes.
    /// The request telling Jarvis Dylan has gone to bed (`asleep: true`)
    /// or is up after all (the Apple TV's Night button, Dylan 2026-11-18).
    public func sleepRequest(asleep: Bool, source: String) -> URLRequest {
        request("api/jarvis/sleep", method: "POST", json: ["asleep": asleep, "source": source])
    }

    /// Sends it. An older server answers 404 or 409; callers ignore that.
    public func setSleep(asleep: Bool, source: String) async throws {
        _ = try await send(sleepRequest(asleep: asleep, source: source))
    }

    /// Clears notices everywhere: these ids, or all of them.
    public func clearNotices(ids: [String]) async throws {
        try await post("api/jarvis/notices/clear", ["ids": ids])
    }

    /// Clears every notice.
    public func clearAllNotices() async throws {
        try await post("api/jarvis/notices/clear", ["all": true])
    }

    /// The request registering this device for push notifications.
    public func pushRegisterRequest(token: String, platform: String, environment: String, bundle: String, name: String) -> URLRequest {
        request("api/jarvis/push/register", method: "POST", json: [
            "token": token, "platform": platform, "environment": environment, "bundle": bundle, "name": name,
        ])
    }

    /// Registers this device's push token with the page server.
    public func registerPush(token: String, platform: String, environment: String, bundle: String, name: String) async throws {
        _ = try await send(pushRegisterRequest(token: token, platform: platform, environment: environment, bundle: bundle, name: name))
    }

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
