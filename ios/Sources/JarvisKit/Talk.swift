// Talk: the voice line to Jarvis's own voice pipeline on the PC, the same
// one the web page's Talk uses (src/lib/talk.ts, server/talk.mjs). Keep the
// two in step.
//
// The app sends the microphone as 16 kHz 16-bit mono audio in 20 ms frames
// (640 bytes), and keeps sending while Jarvis speaks so Dylan can talk over
// him. Jarvis sends JSON events as text messages and his voice as 16-bit
// audio (one binary message per sentence) at the rate his hello names. When
// his voice has finished playing the app says {"type":"idle"}.
import Foundation

/// Jarvis's side of the line.
public enum TalkState: String, Equatable, Sendable {
    case listening, thinking, speaking, dozing
}

/// One JSON event from the voice line.
public enum TalkEvent: Equatable, Sendable {
    /// First thing on the line: his voice's sample rate, and whether he can
    /// doze and wake on "Hey Jarvis" (older ones can only hang up).
    case hello(rate: Double, wakeWord: Bool)
    case state(TalkState)
    /// What Whisper has heard so far while Dylan is still talking. `stable`
    /// is how many leading words are settled and won't change again (nil
    /// from an older Jarvis: all tentative).
    case partial(String, joined: Bool, stable: Int? = nil)
    /// One whole turn heard. joined: carries on the question he was
    /// answering. same: the final says what the live words already said, so
    /// the shown words stay as they are.
    case transcript(String, joined: Bool, same: Bool = false)
    /// More of his reply's text.
    case reply(String)
    case working(String)
    case workingDone
    case model(String)
    /// He finished this reply.
    case done
    /// Dylan talked over him: drop the rest of his voice.
    case stop
    /// He said goodbye (Dylan said "talk to you later"): his goodbye has
    /// played and he's hanging up for good, not dozing. Even "Hey Jarvis"
    /// won't wake him; only a tap on Talk starts a new call.
    case bye
    case approval(Approval)
    case approvalDone(id: String, ok: Bool, by: String, later: Bool)
    /// The line has carried no audio for `seconds` (Jarvis noticed): the
    /// app restarts its microphone without hanging up.
    case noAudio(seconds: Double)

    /// Reads one text message. Unknown or broken ones come back nil, so a
    /// newer Jarvis never breaks an older app.
    public static func parse(_ text: String) -> TalkEvent? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let type = object["type"] as? String else { return nil }
        let words = object["text"] as? String ?? ""
        let joined = object["joined"] as? Bool ?? false

        switch type {
        case "hello":
            let rate = (object["rate"] as? NSNumber)?.doubleValue ?? 22050
            return .hello(rate: rate, wakeWord: object["wake_word"] as? Bool ?? false)
        case "state":
            guard let raw = object["state"] as? String, let state = TalkState(rawValue: raw) else { return nil }
            return .state(state)
        case "partial":
            if words.isEmpty { return nil }
            let stable = (object["stable"] as? NSNumber).map { max(0, $0.intValue) }
            return .partial(words, joined: joined, stable: stable)
        case "transcript":
            if words.isEmpty { return nil }
            return .transcript(words, joined: joined, same: object["same"] as? Bool ?? false)
        case "reply":
            if words.isEmpty { return nil }
            return .reply(words)
        case "working":
            return .working(object["label"] as? String ?? "")
        case "working_done":
            return .workingDone
        case "model":
            guard let model = object["model"] as? String else { return nil }
            return .model(model)
        case "done":
            return .done
        case "stop":
            return .stop
        case "bye":
            return .bye
        case "approval":
            // On the talk line the approval's fields sit on the event itself.
            guard let id = object["id"] as? String, let summary = object["summary"] as? String else { return nil }
            let tool = object["tool"] as? String ?? ""
            let expires = object["expires"] as? String ?? ""
            return .approval(Approval(id: id, tool: tool, summary: summary, expires: expires))
        case "approval_done":
            guard let id = object["id"] as? String else { return nil }
            return .approvalDone(
                id: id,
                ok: object["ok"] as? Bool ?? false,
                by: object["by"] as? String ?? "timeout",
                later: object["later"] as? Bool ?? false
            )
        case "no_audio":
            return .noAudio(seconds: (object["seconds"] as? NSNumber)?.doubleValue ?? 0)
        default:
            return nil
        }
    }
}

/// What the app tells Jarvis about the line.
public enum TalkMessage {
    /// His whole reply has played; the speaker is quiet.
    public static let idle = #"{"type":"idle"}"#
    /// Pause without hanging up: he listens only for "Hey Jarvis".
    public static let doze = #"{"type":"doze"}"#
    /// Talk again after dozing.
    public static let wake = #"{"type":"wake"}"#
    /// Mute tapped: "I'm finished talking", so he answers what he has heard at once.
    public static let endTurn = #"{"type":"end_turn"}"#

    /// For Jarvis's log, so a crackle report can be matched to the phone's audio.
    public static func client(micRate: Double, audioRate: Double) -> String {
        let object: [String: Any] = ["type": "client", "mic_rate": micRate, "audio_rate": audioRate, "agent": "Jarvis iOS"]
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Sound helpers for the line, kept free of AVFoundation so they're tested
/// on any Mac.
public enum TalkAudio {
    /// Samples per 20 ms frame at 16 kHz.
    public static let frameSamples = 320

    /// True when Jarvis just decided Dylan's done talking (listening to
    /// thinking): that's when the soft "got it" plays.
    public static func heardYouOut(before: TalkState, after: TalkState) -> Bool {
        before == .listening && after == .thinking
    }

    /// 16-bit little-endian samples as the -1..1 floats the speaker plays.
    public static func floats(fromPCM16 data: Data) -> [Float] {
        let count = data.count / 2
        var out = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            for i in 0..<count {
                let lo = UInt16(raw[i * 2])
                let hi = UInt16(raw[i * 2 + 1])
                out[i] = Float(Int16(bitPattern: lo | hi << 8)) / 32768
            }
        }
        return out
    }

    /// -1..1 floats as 16-bit little-endian bytes (clipped).
    public static func pcm16(fromFloats floats: [Float]) -> Data {
        var data = Data(capacity: floats.count * 2)
        for sample in floats {
            let clipped = max(-1, min(1, sample))
            let value = UInt16(bitPattern: Int16((clipped * 32767).rounded()))
            data.append(UInt8(value & 0xff))
            data.append(UInt8(value >> 8))
        }
        return data
    }

    /// Fades the first and last 4 ms of a sentence, so its edges don't click.
    public static func softenEdges(_ floats: inout [Float], rate: Double) {
        let n = min(Int(rate * 0.004), floats.count / 2)
        guard n > 0 else { return }
        for i in 0..<n {
            let gain = Float(i) / Float(n)
            floats[i] *= gain
            floats[floats.count - 1 - i] *= gain
        }
    }

    /// How bright (high) a voice sounds right now, 0..1, from how often the
    /// wave crosses zero: about 300 crossings a second reads as low, 3000 as
    /// high. A cheap stand-in for intonation that drives the orb's ripples.
    /// Near-silence comes back 0, so room hiss doesn't read as a high voice.
    public static func brightness(_ samples: UnsafeBufferPointer<Float>, rate: Double) -> Float {
        guard samples.count > 1, rate > 0 else { return 0 }
        guard loudness(samples) > 0.05 else { return 0 }
        var crossings = 0
        for i in 1..<samples.count where (samples[i - 1] < 0) != (samples[i] < 0) {
            crossings += 1
        }
        let perSecond = Double(crossings) * rate / Double(samples.count)
        return Float(min(1, max(0, (perSecond - 300) / 2700)))
    }

    /// Root-mean-square loudness, scaled so speech lands around 0.5-1 (like the page's orb).
    public static func loudness(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return min(1, (sum / Float(samples.count)).squareRoot() * 9)
    }
}

/// Cuts a stream of 16 kHz samples into 20 ms frames of 16-bit bytes.
/// Feed it chunks in order; it hands back each frame as it fills.
public struct FrameCutter {
    private var pending: [Float] = []

    public init() {}

    /// Adds samples; returns the whole 640-byte frames finished so far.
    public mutating func add(_ samples: [Float]) -> [Data] {
        pending += samples
        var frames: [Data] = []
        while pending.count >= TalkAudio.frameSamples {
            frames.append(TalkAudio.pcm16(fromFloats: Array(pending.prefix(TalkAudio.frameSamples))))
            pending.removeFirst(TalkAudio.frameSamples)
        }
        return frames
    }
}

extension JarvisClient {
    /// The voice line's address: wss on the server's own host.
    public var talkURL: URL {
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.scheme = base.scheme == "http" ? "ws" : "wss"
        parts.path = "/api/jarvis/talk"
        parts.query = nil
        return parts.url ?? base
    }

    /// The upgrade request, with the same-origin Origin the server insists on
    /// (server/talk.mjs talkRefusal).
    public var talkRequest: URLRequest {
        var request = URLRequest(url: talkURL)
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("1", forHTTPHeaderField: "x-home-lab")
        return request
    }
}

/// Where the words Jarvis just heard go on the Talk screen (Dylan,
/// 2026-11-18: "it didnt print what i said at all, and it was doing it out
/// of order"). The native twin of the page's canJoin (src/lib/heard.ts):
/// keep the two in step. Partials are sparse or absent, so nothing here
/// depends on them: a transcript alone opens or fills an exchange.
public enum HeardPlacement: Equatable, Sendable {
    /// Into the open exchange, replacing what was heard so far.
    case same
    /// The open exchange moves up into the transcript; these words start a new one.
    case new

    /// Where words go, given the open exchange. Joined words (Jarvis carried
    /// on the question he was answering) stay in it only while he hasn't
    /// answered and it isn't done: canJoin. Words that aren't joined are the
    /// same turn still being heard (a partial, then its transcript) under
    /// the same condition. Once there's an answer, or the exchange is done,
    /// any words start a new one, so the last question and its answer stay
    /// where they were.
    public static func of(openReply: String, openDone: Bool, joined: Bool) -> HeardPlacement {
        let stillOpen = openReply.isEmpty && !openDone
        if joined { return stillOpen ? .same : .new }
        return stillOpen ? .same : .new
    }
}

/// The live words on the Talk screen (Dylan, 2026-11-18: the live words got
/// rewritten a lot). Jarvis marks how many leading words are settled; those
/// show solid and only the tail is light. When the final transcript says
/// the same as what's shown, the shown words stay put instead of being
/// swapped. The native twin of src/lib/heard.ts; keep the two in step.
public enum HeardWords {
    /// How light the tentative tail is (the page's 55%).
    public static let tailOpacity = 0.55

    /// The settled words and the tentative tail. `stable` nil (an older
    /// Jarvis) means nothing is settled; more than there are means all is.
    public static func split(_ text: String, stable: Int?) -> (settled: String, tail: String) {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let n = min(max(stable ?? 0, 0), words.count)
        return (words[..<n].joined(separator: " "), words[n...].joined(separator: " "))
    }

    /// What the bubble says once the final transcript arrives: the shown
    /// words when Jarvis says they match (`same`) and something was shown,
    /// otherwise the final.
    public static func afterFinal(shown: String, final: String, same: Bool) -> String {
        same && !shown.trimmingCharacters(in: .whitespaces).isEmpty ? shown : final
    }
}
