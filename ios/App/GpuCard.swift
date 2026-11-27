// The graphics card as a pie on Home (Dylan, 2026-11-18: "a pie chart of
// instantaneous use of gpu and who's using it"): a slice per model holding
// memory, Free in quiet grey, and a legend with each one's job and size.
// The slices come from JarvisKit's GpuShare.
import Charts
import SwiftUI
import JarvisKit

struct GpuCard: View {
    let share: GpuShare

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "cpu").font(.footnote.weight(.semibold)).foregroundStyle(Theme.glacier)
                Text("Graphics card").font(.subheadline.weight(.semibold))
                Spacer()
                Text(share.summary).font(.caption).foregroundStyle(Theme.frostDim)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) { pie.frame(width: 140, height: 140); legend }
                VStack(alignment: .leading, spacing: 14) { pie.frame(width: 160, height: 160).frame(maxWidth: .infinity); legend }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
        .accessibilityElement(children: .combine)
    }

    /// The ring, one sector per slice, with the GB in use in the middle.
    private var pie: some View {
        Chart(share.slices) { slice in
            SectorMark(angle: .value("GB", slice.gb), innerRadius: .ratio(0.62), angularInset: 1.5)
                .cornerRadius(3)
                .foregroundStyle(GpuCard.color(slice, in: share))
        }
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: 0) {
                Text(String(format: "%.1f", share.usedGb)).font(.title3.weight(.semibold)).foregroundStyle(Theme.frost)
                Text("GB used").font(.caption2).foregroundStyle(Theme.frostDim)
            }
        }
        .accessibilityHidden(true)
    }

    /// Name, its job and its size, a row each.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(share.slices) { slice in
                HStack(spacing: 10) {
                    Circle().fill(GpuCard.color(slice, in: share)).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(slice.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.frost)
                        if let role = slice.role {
                            Text(role).font(.caption).foregroundStyle(Theme.frostDim)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(slice.sizeText).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.frostDim)
                }
            }
        }
    }

    /// Matching the web page: local models a warm ember, speech models cool
    /// (glacier blue, then moss green, then lighter again), the rest grey,
    /// free a faint white.
    static func color(_ slice: GpuSlice, in share: GpuShare) -> Color {
        let step = share.shade(of: slice)
        switch slice.kind {
        case .local: return Theme.ember.opacity(max(0.5, 1 - Double(step) * 0.2))
        case .speech:
            let cool = [Theme.glacier, Theme.moss]
            return cool[step % 2].opacity(step < 2 ? 1 : 0.6)
        case .other: return Color.gray.opacity(0.7)
        case .free: return Color.white.opacity(0.12)
        }
    }
}
