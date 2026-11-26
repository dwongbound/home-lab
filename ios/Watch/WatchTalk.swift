// Talk on the Watch. The Watch can't reach the PC, so the iPhone holds the
// voice line (App/WatchTalkRelay.swift) and passes everything through:
// Jarvis's events as ["talk": json], his voice as message data, and the
// Watch's microphone back the same way. The Watch has no echo cancelling,
// so its microphone sends silence while Jarvis speaks.
import AVFoundation
import Foundation
import WatchConnectivity
import JarvisKit

@MainActor
final class WatchTalk: ObservableObject {
    enum Phase { case off, calling, on }

    @Published private(set) var phase: Phase = .off
    @Published private(set) var state: TalkState = .listening
    @Published private(set) var working: String?
    @Published private(set) var muted = false
    @Published var problem: String?
    /// The orb is being held: let go mutes and says "I'm finished talking".
    private var holding = false

    private let engine = AVAudioEngine()
    private let voice = AVAudioPlayerNode()
    private var voiceFormat: AVAudioFormat?
    private var pending = Data()
    private var playback = PlaybackTracker()
    private var idleTimer: Timer?

    /// The words under the orb, as on the phone's Talk screen.
    var status: String {
        if let problem { return problem }
        switch phase {
        case .off: return "Hold the orb to talk"
        case .calling: return "Calling Jarvis…"
        case .on:
            if let working { return working }
            switch state {
            case .speaking: return "Speaking"
            case .thinking: return "Jarvis is thinking…"
            case .listening, .dozing: return muted ? "Muted" : "Listening"
            }
        }
    }

    /// Calls Jarvis through the phone; his hello starts the audio.
    func start() async {
        guard phase == .off else { return }
        problem = nil
        muted = false
        phase = .calling
        guard await AVAudioApplication.requestRecordPermission() else {
            fail("Allow the microphone for Jarvis in Settings")
            return
        }
        guard WCSession.default.isReachable else {
            fail("iPhone not reachable")
            return
        }
        WCSession.default.sendMessage(["talk": "start"], replyHandler: nil) { [weak self] error in
            Task { @MainActor in self?.fail(error.localizedDescription) }
        }
    }

    /// Orb held: open the line (or unmute it) while the finger is down.
    func hold() {
        holding = true
        muted = false
        if phase == .off { Task { await start() } }
    }

    /// Orb let go: mute and tell Jarvis the turn is over, so he answers now.
    func release() {
        guard holding else { return }
        holding = false
        muted = true
        send(TalkMessage.endTurn)
    }

    /// The Mute button.
    func toggleMute() {
        muted.toggle()
        if muted { send(TalkMessage.endTurn) }
    }

    /// End: hangs up on both sides.
    func hangUp() {
        if phase != .off { WCSession.default.sendMessage(["talk": "stop"], replyHandler: nil, errorHandler: nil) }
        tearDown()
    }

    /// The phone's line closed by itself.
    func lineClosed() {
        guard phase != .off else { return }
        tearDown()
        problem = "The line to Jarvis dropped"
    }

    /// One event from Jarvis, passed on by the phone.
    func event(_ text: String) {
        guard phase != .off, let event = TalkEvent.parse(text) else { return }
        switch event {
        case .hello(let rate, _): startAudio(rate: rate)
        case .state(let next): state = next
        case .working(let label): working = label.isEmpty ? nil : label
        case .workingDone: working = nil
        case .done:
            playback.done()
            checkIdle()
        case .stop:
            voice.stop()
            voice.play()
            playback.reset()
        case .bye: tearDown()
        default: break
        }
    }

    /// A piece of his voice: 16-bit samples at the hello's rate.
    func play(_ data: Data) {
        guard let format = voiceFormat, engine.isRunning else { return }
        var floats = TalkAudio.floats(fromPCM16: data)
        guard !floats.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(floats.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(floats.count)
        floats.withUnsafeMutableBufferPointer { buffer.floatChannelData?[0].update(from: $0.baseAddress!, count: $0.count) }
        playback.scheduled(seconds: Double(floats.count) / format.sampleRate, now: Date())
        voice.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                self?.playback.played()
                self?.checkIdle()
            }
        }
    }

    /// Microphone and speaker on, once his hello says his voice's rate.
    private func startAudio(rate: Double) {
        let session = AVAudioSession.sharedInstance()
        let capture = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false) else { return }
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            if voice.engine == nil { engine.attach(voice) }
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            let input = engine.inputNode
            let micFormat = input.outputFormat(forBus: 0)
            guard let converter = AVAudioConverter(from: micFormat, to: capture) else { throw WatchMicError.noConverter }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1600, format: micFormat) { [weak self] buffer, _ in
                guard let data = WatchTalk.convert(buffer, with: converter, to: capture) else { return }
                Task { @MainActor in self?.heard(data) }
            }
            try engine.start()
        } catch {
            hangUp()
            problem = "The Watch's microphone didn't start"
            return
        }
        voiceFormat = format
        voice.play()
        phase = .on
        send(TalkMessage.client(micRate: 16000, audioRate: rate, agent: "Jarvis Watch", pause: false))
    }

    /// The microphone's buffer as 16 kHz 16-bit bytes (runs on the audio thread).
    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to capture: AVAudioFormat) -> Data? {
        let room = AVAudioFrameCount(Double(buffer.frameLength) * capture.sampleRate / buffer.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: capture, frameCapacity: room) else { return nil }
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
        guard error == nil, let channel = out.floatChannelData?[0] else { return nil }
        return TalkAudio.pcm16(fromFloats: Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength))))
    }

    /// Sends the microphone in 100 ms pieces; silence while muted or while he speaks.
    private func heard(_ data: Data) {
        guard phase == .on else { return }
        pending += (muted || state == .speaking) ? Data(count: data.count) : data
        if pending.count >= 3200 {
            WCSession.default.sendMessageData(pending, replyHandler: nil, errorHandler: nil)
            pending = Data()
        }
    }

    /// Says "idle" once his reply has played (the phone's PlaybackTracker rules).
    private func checkIdle() {
        idleTimer?.invalidate()
        let now = Date()
        if playback.takeIdle(now: now) {
            send(TalkMessage.idle)
            return
        }
        if let next = playback.nextCheck(now: now) {
            idleTimer = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSince(now), repeats: false) { [weak self] _ in
                Task { @MainActor in self?.checkIdle() }
            }
        }
    }

    /// A JSON message to Jarvis, through the phone.
    private func send(_ json: String) {
        guard phase == .on else { return }
        WCSession.default.sendMessage(["talk": json], replyHandler: nil, errorHandler: nil)
    }

    private func fail(_ words: String) {
        tearDown()
        problem = words
    }

    /// Everything off and back to the start.
    private func tearDown() {
        idleTimer?.invalidate()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        voice.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        playback.reset()
        pending = Data()
        phase = .off
        state = .listening
        working = nil
        muted = false
        holding = false
    }
}

enum WatchMicError: Error { case noConverter }
