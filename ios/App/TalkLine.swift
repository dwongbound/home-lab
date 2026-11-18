// The phone's end of the voice line: the microphone out, Jarvis's voice in,
// over the WebSocket at /api/jarvis/talk. The native twin of the page's
// openTalkLine (src/lib/talk.ts); the wire format lives in JarvisKit/Talk.
//
// Audio runs through one AVAudioEngine with Apple's voice processing on,
// which cancels his voice out of the microphone so he doesn't hear himself.
// The session is play-and-record with the background audio mode, so the
// line keeps going with the screen locked.
import AVFoundation
import JarvisKit

/// What the line tells the screen. Always called on the main thread.
struct TalkHandlers {
    var onEvent: @MainActor (TalkEvent) -> Void
    /// The voice that matters now (Dylan's while Jarvis listens, Jarvis's
    /// while he speaks): how loud it is and how bright it sounds, both 0..1.
    var onLevel: @MainActor (_ level: Float, _ tone: Float) -> Void
    /// The line dropped; the message says why, in words for the screen.
    var onClosed: @MainActor (String) -> Void
    /// True when the microphone stopped and couldn't be brought back (the
    /// screen says "Mic paused. Tap to resume."); false once it's back.
    var onMicStuck: @MainActor (Bool) -> Void = { _ in }
}

/// Runs `body` on the main thread, after anything already sent there, so
/// events reach the screen in the order they came off the line.
private func onMain(_ body: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated { body() }
    }
}

/// A line in the Xcode console for debug builds, so a dead microphone can
/// be traced on the phone; silent in release builds.
func talkLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[talk] \(message())")
    #endif
}

/// Why opening the line failed, worded for the screen.
enum TalkError: LocalizedError {
    case microphone
    case audio(String)
    case noAnswer

    var errorDescription: String? {
        switch self {
        case .microphone: return "Jarvis can’t hear you: allow the microphone in Settings › Jarvis."
        case .audio(let why): return "The phone’s audio wouldn’t start (\(why))."
        case .noAnswer: return "Jarvis didn’t pick up. Is Tailscale on and Jarvis running on the PC?"
        }
    }
}

// The engine, socket and counters are touched from the audio thread, the
// socket's callbacks and the main thread; `queue` keeps them in order.
final class TalkLine: @unchecked Sendable {
    private let handlers: TalkHandlers
    // Not constants: after "media services were reset" the old engine is
    // dead and a new one (with new players) takes its place.
    private var engine = AVAudioEngine()
    private var voice = AVAudioPlayerNode()
    private var chime = AVAudioPlayerNode()
    private let socket: URLSessionWebSocketTask
    private let queue = DispatchQueue(label: "jarvis.talk")
    private let capture = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    private var converter: AVAudioConverter?
    private var cutter = FrameCutter()
    private var voiceRate: Double = 22050
    private var voiceFormat: AVAudioFormat?
    private var state: TalkState = .listening
    /// Sentences scheduled and not yet heard.
    private var queued = 0
    /// Bumped on every "stop", so sentences dropped then don't count down later.
    private var generation = 0
    private var replyDone = false
    private var muted = false
    private var closed = false
    private(set) var canDoze = false
    private var observers: [NSObjectProtocol] = []
    /// True once startAudio has attached the players and installed taps.
    private var audioStarted = false
    /// Microphone frames sent so far, for the debug log.
    private var framesSent = 0
    /// Notices a microphone that has quietly stopped (JarvisKit MicWatchdog).
    private var watchdog = MicWatchdog()
    /// The once-a-second look at the watchdog.
    private var watchTimer: DispatchSourceTimer?
    /// When an audio interruption began, while one is under way.
    private var interruptedAt: Date?
    /// True while "Mic paused. Tap to resume." is on screen.
    private var stuckShown = false
    /// An interruption whose "ended" never comes (it happens) stops holding
    /// the watchdog back after this long.
    private static let interruptionPatience: TimeInterval = 15

    /// Builds the line; nothing starts until `open()`.
    init(request: URLRequest, handlers: TalkHandlers) {
        self.handlers = handlers
        socket = URLSession.shared.webSocketTask(with: request)
    }

    /// Asks for the microphone, starts the audio, dials Jarvis and waits for
    /// his hello. Throws a TalkError whose words can go straight on screen.
    func open() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            talkLog("microphone permission refused")
            throw TalkError.microphone
        }
        // Dial first and wait for his hello, so his voice's rate is known
        // before the speaker is wired and no microphone frame goes out on a
        // socket that isn't open yet.
        socket.resume()
        do {
            let first = try await socket.receive()
            queue.sync { handle(first) }
        } catch {
            talkLog("no hello: \(error)")
            shutDown(message: nil)
            throw TalkError.noAnswer
        }
        do {
            try startAudio()
        } catch {
            talkLog("audio failed: \(error)")
            shutDown(message: nil)
            throw error
        }
        send(text: TalkMessage.client(micRate: engine.inputNode.outputFormat(forBus: 0).sampleRate, audioRate: voiceRate))
        listen()
        watchAudio()
        startWatchdog()
    }

    /// Hangs up: microphone, voice and socket all stop.
    func close() {
        shutDown(message: nil)
    }

    /// Muted, he hears only silence; the line and his voice carry on.
    /// Going muted also tells him the turn is over, so he answers at once.
    func setMuted(_ value: Bool) {
        queue.async {
            let justMuted = value && !self.muted
            self.muted = value
            if justMuted { self.send(text: TalkMessage.endTurn) }
        }
    }

    /// Pause without hanging up: his voice stops and he listens only for "Hey Jarvis".
    func doze() {
        queue.async {
            self.silence()
            self.send(text: TalkMessage.doze)
            self.state = .dozing
        }
    }

    /// Talk again after dozing, same as saying "Hey Jarvis".
    func wake() {
        queue.async {
            self.send(text: TalkMessage.wake)
            self.state = .listening
        }
    }

    // MARK: Audio

    /// Play-and-record for a voice call, out of the loudspeaker unless
    /// AirPods or a car are connected, with echo cancelling on.
    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            try engine.inputNode.setVoiceProcessingEnabled(true)
        } catch {
            throw TalkError.audio(error.localizedDescription)
        }
        engine.attach(voice)
        engine.attach(chime)
        connectNodes()
        audioStarted = true
        do {
            try engine.start()
        } catch {
            throw TalkError.audio(error.localizedDescription)
        }
        voice.play()
        chime.play()
    }

    /// Wires the microphone tap and the two players. Called again when the
    /// route changes (AirPods in or out), since the formats change with it.
    private func connectNodes() {
        let input = engine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: micFormat, to: capture)
        talkLog("mic format \(micFormat), converter \(converter == nil ? "missing" : "ok")")
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: micFormat) { [weak self] buffer, _ in
            self?.heard(buffer)
        }
        let format = playFormat()
        engine.connect(voice, to: engine.mainMixerNode, format: format)
        engine.connect(chime, to: engine.mainMixerNode, format: format)
        tapVoice()
    }

    /// Listens to his voice as it actually plays, so the orb follows each
    /// word's loudness and pitch instead of one number per sentence.
    private func tapVoice() {
        voice.removeTap(onBus: 0)
        voice.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            let level = TalkAudio.loudness(samples)
            let tone = TalkAudio.brightness(samples, rate: buffer.format.sampleRate)
            self.queue.async {
                guard !self.closed, self.state == .speaking else { return }
                onMain { self.handlers.onLevel(level, tone) }
            }
        }
    }

    /// Mono floats at his voice's rate; the mixer converts to the speaker's.
    private func playFormat() -> AVAudioFormat {
        if let voiceFormat, voiceFormat.sampleRate == voiceRate { return voiceFormat }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: voiceRate, channels: 1, interleaved: false)!
        voiceFormat = format
        return format
    }

    /// One chunk from the microphone: down to 16 kHz, into 20 ms frames, out
    /// to Jarvis. Runs on the audio thread.
    private func heard(_ buffer: AVAudioPCMBuffer) {
        // Exact zeros mean a dead input, not a quiet room. While Jarvis
        // speaks the echo cancelling may flatten the input, so only buffers
        // arriving count then.
        let zeros = buffer.floatChannelData.map {
            MicWatchdog.isDigitalSilence(UnsafeBufferPointer(start: $0[0], count: Int(buffer.frameLength)))
        } ?? true
        queue.async {
            self.watchdog.heard(silent: zeros && self.state != .speaking)
            if self.stuckShown, !zeros {
                self.stuckShown = false
                talkLog("mic back")
                onMain { self.handlers.onMicStuck(false) }
            }
        }
        guard let converter else { return }
        let ratio = capture.sampleRate / buffer.format.sampleRate
        let room = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: capture, frameCapacity: room) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData?[0] else {
            talkLog("mic convert failed: \(String(describing: error))")
            return
        }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        let level = samples.withUnsafeBufferPointer { TalkAudio.loudness($0) }
        let tone = samples.withUnsafeBufferPointer { TalkAudio.brightness($0, rate: capture.sampleRate) }
        queue.async {
            guard !self.closed else { return }
            for frame in self.cutter.add(samples) {
                // Muted, a frame of silence goes instead, so his listening
                // clock keeps running and a half-finished turn still ends.
                let bytes = self.muted ? Data(count: frame.count) : frame
                self.socket.send(.data(bytes)) { error in
                    if let error { talkLog("mic frame not sent: \(error)") }
                }
                self.framesSent += 1
                if self.framesSent == 1 || self.framesSent % 500 == 0 {
                    talkLog("mic frames sent: \(self.framesSent), level \(level)")
                }
            }
            if self.state == .listening {
                let shown = self.muted ? 0 : level
                let shownTone = self.muted ? 0 : tone
                onMain { self.handlers.onLevel(shown, shownTone) }
            }
        }
    }

    /// Queues one sentence of his voice after the one before it.
    private func play(_ data: Data) {
        var floats = TalkAudio.floats(fromPCM16: data)
        guard !floats.isEmpty else { return }
        TalkAudio.softenEdges(&floats, rate: voiceRate)
        let format = playFormat()
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(floats.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(floats.count)
        floats.withUnsafeBufferPointer { source in
            buffer.floatChannelData?[0].update(from: source.baseAddress!, count: floats.count)
        }
        queued += 1
        let mine = generation
        voice.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                guard mine == self.generation else { return }
                self.queued -= 1
                self.maybeIdle()
            }
        }
        if !voice.isPlaying { voice.play() }
    }

    /// Tells Jarvis the speaker's quiet, once his whole reply has played.
    private func maybeIdle() {
        guard replyDone, queued <= 0 else { return }
        replyDone = false
        queued = 0
        send(text: TalkMessage.idle)
    }

    /// Drops whatever of his voice is still queued (Dylan talked over him).
    private func silence() {
        generation += 1
        queued = 0
        replyDone = false
        voice.stop()
        voice.play()
    }

    /// A very short, quiet two-note rise when he's heard Dylan out, so Dylan
    /// knows he can stop talking (the page's playGotIt).
    private func playGotIt() {
        let format = playFormat()
        let rate = format.sampleRate
        let noteLength = Int(rate * 0.07)
        let tail = Int(rate * 0.05)
        let total = noteLength * 2 + tail
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)) else { return }
        buffer.frameLength = AVAudioFrameCount(total)
        guard let out = buffer.floatChannelData?[0] else { return }
        for i in 0..<total { out[i] = 0 }
        for (index, hz) in [660.0, 990.0].enumerated() {
            let start = index * noteLength
            let length = min(noteLength + tail, total - start)
            for i in 0..<length {
                let t = Double(i) / rate
                // Swell over 12 ms, then fade, so no edge clicks.
                let swell = min(1, t / 0.012)
                let fade = exp(-t / 0.035)
                out[start + i] += Float(sin(2 * .pi * hz * t) * swell * fade * 0.07)
            }
        }
        chime.scheduleBuffer(buffer, completionHandler: nil)
    }

    // MARK: Socket

    /// Reads messages until the line drops.
    private func listen() {
        socket.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.queue.async {
                    self.handle(message)
                    self.listen()
                }
            case .failure(let error):
                talkLog("line dropped: \(error)")
                self.shutDown(message: "The line to Jarvis dropped. Tap Talk to call again.")
            }
        }
    }

    /// One message: his voice (binary) or an event (text).
    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            play(data)
        case .string(let text):
            guard let event = TalkEvent.parse(text) else {
                talkLog("unread event: \(text.prefix(200))")
                return
            }
            if case .transcript(let words, _) = event { talkLog("heard: \(words)") }
            apply(event)
            onMain { self.handlers.onEvent(event) }
        @unknown default:
            break
        }
    }

    /// What an event changes on the line itself (the screen gets it too).
    private func apply(_ event: TalkEvent) {
        switch event {
        case .hello(let rate, let wakeWord):
            voiceRate = rate
            canDoze = wakeWord
            if engine.isRunning, voiceFormat?.sampleRate != rate {
                let format = playFormat()
                engine.connect(voice, to: engine.mainMixerNode, format: format)
                engine.connect(chime, to: engine.mainMixerNode, format: format)
                tapVoice()
                voice.play()
                chime.play()
            }
        case .state(let next):
            talkLog("state \(next)")
            if TalkAudio.heardYouOut(before: state, after: next) { playGotIt() }
            state = next
        case .done:
            replyDone = true
            maybeIdle()
        case .stop:
            silence()
        case .bye:
            // He's said goodbye and is closing the line: hang up quietly
            // (no "line dropped" message), mic and audio off, no reconnect.
            shutDown(message: nil)
        case .noAudio(let seconds):
            // Jarvis has heard nothing from this line for a while: restart
            // the microphone, keeping the line open.
            talkLog("jarvis heard no audio for \(seconds)s")
            watchdog.restarting()
            recoverMic(reason: "jarvis heard nothing", rebuild: watchdog.tries > 1)
        default:
            break
        }
    }

    /// Sends one JSON message if the line's still open.
    private func send(text: String) {
        guard !closed else { return }
        socket.send(.string(text)) { _ in }
    }

    // MARK: Phone audio changes

    /// Keeps the microphone alive through whatever the phone does to its
    /// audio (Dylan, 2026-11-18: the line stayed open for eight minutes with
    /// no audio going out). The line itself is never dropped for these:
    /// - A call, Siri or another app interrupts: the watchdog holds off;
    ///   when it ends the engine restarts, whether or not iOS says "should
    ///   resume" (and if the "ended" never comes, the watchdog steps in).
    /// - AirPods in or out, or the engine's own setup changing: rewire.
    /// - Media services reset: a whole new engine.
    private func watchAudio() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            self?.queue.async {
                guard let self, !self.closed else { return }
                if raw == AVAudioSession.InterruptionType.began.rawValue {
                    talkLog("audio interrupted")
                    self.interruptedAt = Date()
                    self.watchdog.held = true
                } else {
                    talkLog("interruption ended")
                    self.interruptedAt = nil
                    self.watchdog.held = false
                    self.watchdog.reset()
                    self.recoverMic(reason: "interruption ended")
                }
            }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] note in
            self?.queue.async {
                guard let self, note.object as? AVAudioEngine === self.engine else { return }
                self.rewire()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            self?.queue.async {
                guard let self, !self.closed, self.audioStarted else { return }
                talkLog("route changed (\(String(describing: reason)))")
                // Usually the engine's own change notice rewires it; if the
                // route change left it stopped, start it again here.
                if !self.engine.isRunning, self.interruptedAt == nil { self.recoverMic(reason: "route change stopped the engine") }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async {
                guard let self, !self.closed else { return }
                self.watchdog.reset()
                self.recoverMic(reason: "media services reset", rebuild: true)
            }
        })
    }

    /// Restarts the engine on the new route. If it won't start, the
    /// watchdog sees no buffers and takes it from there.
    private func rewire() {
        guard !closed else { return }
        talkLog("audio route changed, rewiring")
        engine.stop()
        connectNodes()
        do {
            try engine.start()
            voice.play()
            chime.play()
        } catch {
            talkLog("rewire failed: \(error)")
        }
    }

    // MARK: The microphone watchdog

    /// Looks at the watchdog once a second while the line is open.
    private func startWatchdog() {
        queue.async {
            self.watchdog.reset()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in self?.checkMic() }
            timer.resume()
            self.watchTimer = timer
        }
    }

    /// One look: fine, restart (a full rebuild on the second try), or say
    /// it's stuck. Runs on `queue`.
    private func checkMic() {
        guard !closed, audioStarted else { return }
        if let interruptedAt, Date().timeIntervalSince(interruptedAt) > Self.interruptionPatience {
            talkLog("interruption never ended; checking the mic anyway")
            self.interruptedAt = nil
            watchdog.held = false
        }
        switch watchdog.check() {
        case .fine:
            break
        case .restart:
            watchdog.restarting()
            recoverMic(reason: "no microphone buffers", rebuild: watchdog.tries > 1)
        case .giveUp:
            guard !stuckShown else { return }
            stuckShown = true
            talkLog("mic would not come back")
            onMain { self.handlers.onMicStuck(true) }
        }
    }

    /// Tears the microphone down and starts it again, keeping the socket.
    /// `rebuild` swaps in a whole new engine (after a media reset, or when a
    /// plain restart didn't work). Runs on `queue`.
    private func recoverMic(reason: String, rebuild: Bool = false) {
        guard !closed, audioStarted else { return }
        talkLog("restarting mic: \(reason)\(rebuild ? " (new engine)" : "")")
        engine.inputNode.removeTap(onBus: 0)
        voice.removeTap(onBus: 0)
        engine.stop()
        if rebuild {
            engine = AVAudioEngine()
            voice = AVAudioPlayerNode()
            chime = AVAudioPlayerNode()
            engine.attach(voice)
            engine.attach(chime)
            // Whatever of his voice was queued went with the old engine.
            generation += 1
            queued = 0
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            try engine.inputNode.setVoiceProcessingEnabled(true)
        } catch {
            talkLog("session wouldn't come back: \(error)")
        }
        connectNodes()
        engine.prepare()
        do {
            try engine.start()
            voice.play()
            chime.play()
        } catch {
            talkLog("engine wouldn't start: \(error)")
        }
    }

    /// "Mic paused. Tap to resume.": a fresh engine and a fresh count.
    func restartMic(asked: Bool) {
        queue.async {
            guard !self.closed else { return }
            self.watchdog.reset()
            self.watchdog.held = false
            self.interruptedAt = nil
            if self.stuckShown {
                self.stuckShown = false
                onMain { self.handlers.onMicStuck(false) }
            }
            self.recoverMic(reason: asked ? "tapped resume" : "asked", rebuild: true)
        }
    }

    /// Stops everything once; the message goes to the screen unless Dylan hung up.
    private func shutDown(message: String?) {
        queue.async {
            guard !self.closed else { return }
            self.closed = true
            self.watchTimer?.cancel()
            self.watchTimer = nil
            for observer in self.observers { NotificationCenter.default.removeObserver(observer) }
            self.observers = []
            // Only an engine that started has taps to remove; removing one
            // from a player that was never attached throws (and crashed
            // the app when Talk couldn't reach Jarvis).
            if self.audioStarted {
                self.engine.inputNode.removeTap(onBus: 0)
                self.voice.removeTap(onBus: 0)
            }
            self.voice.stop()
            self.chime.stop()
            self.engine.stop()
            self.socket.cancel(with: .normalClosure, reason: nil)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            if let message {
                onMain { self.handlers.onClosed(message) }
            }
        }
    }
}
