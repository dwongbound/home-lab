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
            return ErrorWording.unreachable
        case .server(let status, let message):
            return ErrorWording.server(status: status, message: message)
        }
    }

    /// Worth asking again (a read, never a write): Jarvis restarting
    /// (502, 503, 504) or the line dropped on the way.
    public var isPassing: Bool {
        switch self {
        case .unreachable: return true
        case .server(let status, _): return [502, 503, 504].contains(status)
        }
    }
}

/// The one place errors are put into words (Dylan, 2026-11-19: "a lot of
/// jarvis 502 error logs"). No status codes ever reach the screen.
public enum ErrorWording {
    public static let unreachable = "Can’t reach Jarvis. Check Tailscale."
    public static let restarting = "Jarvis is restarting. Try again in a moment."
    public static let sendFailed = "Didn’t send. Tap Try again."

    /// A server answer in words: its own message when it gave one that
    /// isn't just a code, else plain words for the kind of failure.
    public static func server(status: Int, message: String) -> String {
        if [502, 503, 504].contains(status) { return restarting }
        let own = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if own.isEmpty || own.hasPrefix("Jarvis answered") || own.range(of: #"\b[1-5]\d\d\b"#, options: .regularExpression) != nil && own.count < 24 {
            return status >= 500 ? "Jarvis had a problem. Try again in a moment." : "Jarvis didn’t take that."
        }
        return own
    }
}

/// How reads are retried while Jarvis restarts or the tunnel comes back:
/// a few quick tries, then quiet until the next refresh. Writes never.
public enum RetryPolicy {
    public static let delays: [Double] = [0.5, 1, 2, 4]

    /// Runs `read`, retrying a passing failure after each delay.
    public static func run<T: Sendable>(delays: [Double] = RetryPolicy.delays, sleep: @Sendable (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) }, _ read: @Sendable () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await read()
            } catch let error as JarvisError where error.isPassing && attempt < delays.count && !Task.isCancelled {
                await sleep(delays[attempt])
                attempt += 1
            }
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

    /// One page of chat history (JarvisKit ChatHistory); a server without
    /// paging ignores the parameters and answers its newest turns.
    public func history(_ query: HistoryQuery) async throws -> HistoryPage {
        let request = request("api/jarvis/history", query: query.parameters)
        let data = try await RetryPolicy.run { try await send(request) }
        return try JSONDecoder().decode(HistoryPage.self, from: data)
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

    /// Up to 14 days running back from `end`, newest first; nil when Jarvis
    /// can't say (then the screen falls back to one day at a time).
    public func nutritionDays(end: String, count: Int = 14) async throws -> NutritionDays? {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request("api/jarvis/nutrition/days", query: ["end": end, "count": String(count)]))
        } catch {
            throw JarvisError.unreachable
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        struct Body: Decodable { let days: [NutritionDay]?; let earliest: String? }
        guard let body = try? JSONDecoder().decode(Body.self, from: data), let days = body.days else { return nil }
        return NutritionDays(days: days, earliest: body.earliest)
    }

    /// A meal's photo (a thumbnail, or the full one); nil when there's none
    /// or Jarvis isn't answering. Only asked for items with hasPhoto.
    public func mealPhoto(id: String, thumb: Bool) async -> Data? {
        guard let path = MealPhotos.path(id: id) else { return nil }
        let query = MealPhotos.query(thumb: thumb)
        var request = query.isEmpty ? request(path) : request(path, query: query)
        request.timeoutInterval = 30
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        return data
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

    /// The playbooks and what their steps can use (devices, scenes, TVs),
    /// for the editor; nil when Jarvis can't say.
    public func playbookBook() async throws -> (playbooks: [Playbook], options: PlaybookOptions)? {
        let data = try await send(request("api/jarvis/playbooks"))
        guard let list = Playbooks.list(from: data), let book = Playbooks.book(from: data) else { return nil }
        return (list, book.options)
    }

    /// Saves a playbook the editor wrote (new or changed), as the page does.
    public func savePlaybook(_ draft: PlaybookDraft) async throws -> PlaybookResult {
        try await playbookChange(["op": "save", "playbook": draft.json])
    }

    /// Deletes a playbook.
    public func deletePlaybook(id: String) async throws -> PlaybookResult {
        try await playbookChange(["op": "delete", "id": id])
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

    /// Has Jarvis write a playbook from a description; nothing is saved.
    /// It takes about 6 s, so the wait allows 45.
    public func draftPlaybook(text: String) async throws -> PlaybookDraftAnswer {
        let words = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(PlaybookDraftAnswer.maxText))
        var request = request("api/jarvis/playbooks", method: "POST", json: ["op": "draft", "text": words])
        request.timeoutInterval = 45
        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw JarvisError.unreachable
        }
        return PlaybookDraftAnswer.read(data)
    }

    /// Stops a running job (Dylan, 2026-11-20: "swiping a running process
    /// all the way through would stop it"). The shape is proposed, not yet
    /// live: POST /api/jarvis/jobs/stop {id} → {ok, message}, 410 {gone}, 409
    /// when it had already finished. Kept in this one place so the names
    /// are easy to change; the app only offers it on jobs marked stoppable.
    public func stopJob(id: String) async throws -> StopReply {
        let (data, response): (Data, URLResponse)
        do {
            // Jarvis may take up to 30 s to stop and clean up; never retried.
            var stop = request("api/jarvis/jobs/stop", method: "POST", json: ["id": id])
            stop.timeoutInterval = 45
            (data, response) = try await session.data(for: stop)
        } catch {
            throw JarvisError.unreachable
        }
        return StopReply.read(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
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
    /// Sets how long a report is kept. A 400 for a span means the server
    /// doesn't take spans yet.
    public func setRetention(id: String, _ retention: Retention) async throws -> RetentionReply {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request("api/jarvis/reports", method: "POST", json: retention.body(id: id)))
        } catch {
            throw JarvisError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return .saved }
        if status == 400, case .days = retention { return .notYet }
        struct Body: Decodable { let message: String? }
        let message = (try? JSONDecoder().decode(Body.self, from: data))?.message
        return .failed(message ?? "Jarvis answered \(status)")
    }

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
        let request = request(path)
        let data = try await RetryPolicy.run { try await send(request) }
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

    /// Loads or unloads the local model; answers the server's words for it.
    public func setLocalModel(loaded: Bool) async throws -> String {
        let data = try await send(request("api/actions/" + (loaded ? "ollama-load" : "ollama-unload"), method: "POST", json: [:]))
        struct Answer: Decodable { let message: String? }
        return (try? JSONDecoder().decode(Answer.self, from: data))?.message ?? (loaded ? "Loaded" : "Unloaded")
    }

    /// Runs one home control command ("toggle", "power") on a device.
    public func homeControl(entity: String, command: String) async throws {
        try await post("api/home/control", ["entity": entity, "command": command])
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

    /// Where the app sends a night of sleep (the page server's route).
    public static let sleepPath = "api/jarvis/health/sleep"

    /// The last `days` nights (1 to 30), newest first; nil when Jarvis
    /// couldn't be asked.
    public func sleepNights(days: Int = 14) async throws -> [SleepDay]? {
        let data = try await send(request(Self.sleepPath, query: ["days": String(max(1, min(30, days)))]))
        return try JSONDecoder().decode(SleepNightsAnswer.self, from: data).nights
    }

    /// Sends one night of sleep (SleepWire.body); re-sending a night replaces it.
    public func sendSleep(_ body: [String: Any]) async throws {
        try await post(Self.sleepPath, body)
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
