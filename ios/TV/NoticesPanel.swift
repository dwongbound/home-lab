// The Apple TV's notices (Dylan, 2026-11-18: the "pips on the orb"
// design). Unread notices circle the orb as pips; the "3 new" button by the
// status chips slides this list into the right side, like the chat. Need
// rows carry Approve and Deny; Clear all at the bottom; Menu slides it away.
// Clearing goes to the page server, so it clears on every device. Guest view
// never gets here: guests see only the pips and the count.
import SwiftUI
import JarvisKit

struct NoticesPanel: View {
    let notices: [Notice]
    let palette: LampPalette
    /// Approve or Deny an approval notice.
    let answer: (Notice, Bool) -> Void
    /// Clear these notices (empty = all).
    let clear: ([String]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("Notices", systemImage: "bell.fill")
                .font(.callout.weight(.bold))
                .foregroundStyle(palette.inkDim.color)
                .labelStyle(TintedIconLabel(icon: palette.accent.color))
            if notices.isEmpty {
                Text("All caught up. Nothing new from Jarvis.")
                    .font(.callout)
                    .foregroundStyle(palette.inkDim.color)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(notices.prefix(6).enumerated()), id: \.element.id) { index, notice in
                        row(notice).staggered(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 560)
            if !notices.isEmpty {
                Button("Clear all") { clear([]) }
                    .buttonStyle(SoftFocusButtonStyle(palette: palette))
            }
        }
        .padding(34)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(palette.panel.color))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(palette.accent.color, lineWidth: 3))
    }

    /// One notice: pip colour, icon, title, a line of body, when; Approve
    /// and Deny for one that needs Dylan.
    private func row(_ notice: Notice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Image(systemName: Notices.symbol(notice.source))
                    .foregroundStyle(color(notice.kind))
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.title).font(.callout.weight(.semibold)).foregroundStyle(palette.ink.color).lineLimit(2)
                    if !notice.body.isEmpty {
                        Text(notice.body).font(.caption).foregroundStyle(palette.inkDim.color).lineLimit(2)
                    }
                }
                Spacer(minLength: 20)
                Text(Notices.when(notice.created)).font(.caption).foregroundStyle(palette.inkDim.color)
            }
            if notice.isApproval {
                HStack(spacing: 20) {
                    Button("Deny") { answer(notice, false) }
                        .buttonStyle(SoftFocusButtonStyle(palette: palette))
                    Button("Approve") { answer(notice, true) }
                        .buttonStyle(SoftFocusButtonStyle(palette: palette))
                }
                .padding(.leading, 58)
            }
        }
    }

    /// Orange needs Dylan, blue heads-up, dim for FYI, from the palette so
    /// they read on the day sky too.
    private func color(_ kind: NoticeKind) -> Color {
        switch kind {
        case .need: return palette.alert.color
        case .heads: return palette.accent.color
        case .fyi: return palette.inkDim.color
        }
    }
}
