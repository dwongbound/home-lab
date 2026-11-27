// The iPhone's half of Talk on the Watch (Watch/WatchTalk.swift): the Watch
// can't reach the PC, so the phone holds the voice line and passes it
// through. Jarvis's events go to the Watch as ["talk": json] and his voice
// as message data; the Watch's microphone comes back as data, cut here into
// the 20 ms frames Jarvis expects.
import Foundation
import UIKit
import WatchConnectivity
import JarvisKit

final class WatchTalkRelay {
    static let shared = WatchTalkRelay()

    private let queue = DispatchQueue(label: "watch.talk")
    private var socket: URLSessionWebSocketTask?
    /// Asks iOS for time to keep the line up while the phone app is in the background.
    private var background: UIBackgroundTaskIdentifier = .invalid

    /// A message from the Watch: "start", "stop", or JSON for Jarvis.
    func handle(_ talk: String, client: JarvisClient) {
        queue.async {
            switch talk {
            case "start": self.open(client)
            case "stop": self.close()
            default: self.socket?.send(.string(talk)) { _ in }
            }
        }
    }

    /// The Watch's microphone, 16 kHz 16-bit, sent on as 640-byte frames.
    func audio(_ data: Data) {
        queue.async {
            guard let socket = self.socket else { return }
            for start in stride(from: 0, to: data.count, by: 640) {
                socket.send(.data(data.subdata(in: start..<min(start + 640, data.count)))) { _ in }
            }
        }
    }

    private func open(_ client: JarvisClient) {
        close()
        let task = URLSession.shared.webSocketTask(with: client.talkRequest)
        socket = task
        task.resume()
        receive(task)
        DispatchQueue.main.async {
            if self.background == .invalid {
                self.background = UIApplication.shared.beginBackgroundTask { self.handle("stop", client: client) }
            }
        }
        talkLog("watch talk: line opened")
    }

    private func close() {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        DispatchQueue.main.async {
            if self.background != .invalid {
                UIApplication.shared.endBackgroundTask(self.background)
                self.background = .invalid
            }
        }
    }

    /// Passes everything Jarvis sends to the Watch until the line closes.
    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { result in
            self.queue.async {
                guard task === self.socket else { return }
                switch result {
                case .success(.string(let text)):
                    WCSession.default.sendMessage(["talk": text], replyHandler: nil, errorHandler: nil)
                case .success(.data(let data)):
                    // WatchConnectivity messages top out near 64 KB.
                    for start in stride(from: 0, to: data.count, by: 32000) {
                        WCSession.default.sendMessageData(data.subdata(in: start..<min(start + 32000, data.count)), replyHandler: nil, errorHandler: nil)
                    }
                case .failure(let error):
                    talkLog("watch talk: line closed \(error.localizedDescription)")
                    self.close()
                    WCSession.default.sendMessage(["talkClosed": true], replyHandler: nil, errorHandler: nil)
                    return
                default:
                    break
                }
                self.receive(task)
            }
        }
    }
}
