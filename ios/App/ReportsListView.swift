// Jarvis's reports as their own screen, opened from the Reports tile on
// Home (Dylan, 2026-11-19: Reports, Diet and Playbooks "clear and isolated
// but not its own tab"). How long reports are kept and the room they take,
// then one row each: tap to read it in the app's reader; "…" for Keep and
// Delete (asked first).
import SwiftUI
import JarvisKit

struct ReportsListView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    /// The report waiting on "Delete this report?".
    @State private var deleting: Report?
    /// The report being read, in a reader over this list.
    @State private var reading: ReportPage?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.sky.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let shelf = app.reportShelf {
                            Text(Reports.rulesText(shelf))
                                .font(.footnote)
                                .foregroundStyle(Theme.frostDim)
                            if shelf.reports.isEmpty {
                                Text("None yet. Jarvis writes one when a long task ends.")
                                    .foregroundStyle(Theme.frostDim)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                            }
                            ForEach(shelf.reports) { report in
                                row(report)
                            }
                        } else {
                            Text("Jarvis hasn't said which reports he has. Pull down to try again.")
                                .foregroundStyle(Theme.frostDim)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await app.today.load(app: app) }
                // A Keep or Delete waiting on the PC: labelled and blocking.
                if let busy = app.reportBusy, reading == nil {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(Theme.frost)
                        Text(busy).font(.headline).foregroundStyle(Theme.frost)
                    }
                    .padding(28)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
                }
            }
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog("Delete this report?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { report in
                Button("Delete", role: .destructive) { Task { await app.deleteReport(report.id) } }
                Button("Close", role: .cancel) {}
            } message: { report in
                Text("“\(report.title)” goes for good, here and on the PC.")
            }
        }
        .sheet(item: $reading) { page in
            ReportReader(page: page).environmentObject(app)
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
    }

    /// One report: title, a line of summary, size and when it's deleted.
    private func row(_ report: Report) -> some View {
        HStack(spacing: 8) {
            Button {
                reading = ReportPage(id: report.id, title: report.title)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.frost)
                        .lineLimit(2)
                    if !report.summary.isEmpty {
                        Text(report.summary)
                            .font(.caption)
                            .foregroundStyle(Theme.frostDim)
                            .lineLimit(2)
                    }
                    Text("\(Reports.sizeText(report.bytes)) · \(Reports.endText(report))")
                        .font(.caption2)
                        .foregroundStyle(report.kept ? Theme.glacier : Theme.frostDim)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Toggle("Keep", isOn: Binding(get: { report.kept }, set: { keep in Task { await app.keepReport(report.id, keep: keep) } }))
                Button("Delete…", role: .destructive) { deleting = report }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.frostDim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Keep or delete \(report.title)")
        }
        .padding(12)
        .glassPanel()
    }
}
