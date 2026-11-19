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
    /// The file in the share sheet.
    @State private var sharing: SharedFile?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.sky.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let shelf = app.reportShelf {
                            Text(Reports.shortRulesText(shelf))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .font(.footnote)
                                .foregroundStyle(Theme.frostDim)
                            if shelf.reports.isEmpty {
                                Text("None yet. Jarvis writes one when a long task ends.")
                                    .foregroundStyle(Theme.frostDim)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                            }
                            ForEach(Self.withFixture(shelf.reports)) { report in
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
        .sheet(item: $sharing) { file in
            ShareSheet(url: file.url)
        }
        .alert("Report", isPresented: Binding(get: { app.reportMessage != nil && reading == nil }, set: { if !$0 { app.reportMessage = nil } })) {
            Button("Close", role: .cancel) {}
        } message: {
            Text(app.reportMessage ?? "")
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
    }

    /// One report: its title and summary (two lines each at most), a short
    /// "Nov 18 · 240 KB · Deletes Dec 3" line, and Share and Delete icons.
    /// Tapping the words opens the reader, where its retention is set.
    private func row(_ report: Report) -> some View {
        HStack(alignment: .top, spacing: 4) {
            words(report)
            // Share and Delete as the standard icons; no picker here (the
            // reader has the retention menu).
            Button {
                Task { if let url = await app.reportFile(id: report.id, title: report.title) { sharing = SharedFile(url: url) } }
            } label: {
                Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.glacier)
            .accessibilityLabel("Share")
            Button {
                deleting = report
            } label: {
                Image(systemName: "trash").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.rose)
            .accessibilityLabel("Delete")
        }
        .padding(12)
        .glassPanel()
    }

    /// The tappable words: title, summary, and the date and size.
    private func words(_ report: Report) -> some View {
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
                        .truncationMode(.tail)
                }
                Text(Reports.metaLine(report) + " · " + Reports.retentionWords(report, defaultDays: app.reportShelf?.keepDays ?? 14))
                    .font(.caption2)
                    .foregroundStyle(Theme.frostDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// `-longReport` adds a report with a very long title and summary
    /// (simulator layout checks); otherwise the list as it is.
    private static func withFixture(_ reports: [Report]) -> [Report] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-longReport") {
            let long = Report(id: "fedcba9876543210", title: "A very long report title that goes on and on about the weekly grocery budget and meal plan", summary: String(repeating: "This summary is far longer than it should be and keeps going. ", count: 8), created: "2026-11-18T20:00:00Z", expires: "2026-12-02T20:00:00Z", kept: false, bytes: 240_000)
            return [long] + reports
        }
        #endif
        return reports
    }
}
