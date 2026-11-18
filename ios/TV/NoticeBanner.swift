// The Apple TV's in-app banner (Dylan, 2026-11-18: "can there be
// notifications on my apple tv somehow? Or an in app banner at least").
// tvOS has no notification banners for apps, so new notices slide down from
// the top of the always-on screen for about 8 seconds: an orange dot, the
// title, a short body and "+N more". Guests see only "New notification".
// The night view dims it. A soft two-note chime plays with it (not at
// night; holding the moon button turns it off).
import AVFoundation
import SwiftUI
import JarvisKit

/// One banner showing: the newest new notice and how many more came with it.
struct BannerShow: Equatable, Identifiable {
    let id = UUID()
    let notice: Notice
    let more: Int
}

struct NoticeBanner: View {
    let show: BannerShow
    let guest: Bool
    let night: Bool
    let palette: LampPalette

    var body: some View {
        let words = TVBanner.words(show.notice, more: show.more, guest: guest)
        HStack(spacing: 24) {
            Circle()
                .fill(OrbView.noticeOrange(onLight: palette.darkInk))
                .frame(width: 20, height: 20)
                .shadow(color: OrbView.noticeOrange(onLight: false).opacity(0.6), radius: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(words.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.ink.color)
                    .lineLimit(1)
                if let body = words.body {
                    Text(body)
                        .font(.callout)
                        .foregroundStyle(palette.inkDim.color)
                        .lineLimit(1)
                }
            }
            if !guest {
                Image(systemName: Notices.symbol(show.notice.source))
                    .font(.title3)
                    .foregroundStyle(OrbView.noticeOrange(onLight: palette.darkInk))
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .frame(maxWidth: 1100)
        .background(Capsule().fill(palette.panel.color))
        .overlay(Capsule().strokeBorder(OrbView.noticeOrange(onLight: palette.darkInk).opacity(0.7), lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .opacity(night ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// A soft two-note chime, made on the spot so there's no sound file.
@MainActor
final class Chime {
    static let shared = Chime()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // E6 then B5, each fading out, quiet.
        let notes: [(Double, Double)] = [(1318.5, 0.0), (987.8, 0.16)]
        let length = 0.7
        let frames = AVAudioFrameCount(length * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / format.sampleRate
            var v = 0.0
            for (freq, start) in notes where t >= start {
                let local = t - start
                v += sin(2 * .pi * freq * local) * exp(-local * 7) * 0.12
            }
            out[i] = Float(v)
        }
        self.buffer = buffer
    }

    /// Plays it once; quietly does nothing if audio isn't available.
    func play() {
        guard let buffer else { return }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }
}
