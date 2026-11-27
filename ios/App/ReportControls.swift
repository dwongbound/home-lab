// The report's retention and sharing controls, shared by the Reports list
// and the reader (Dylan, 2026-11-19: "it should just say keep 2 weeks …
// when you tap that it can allow you to change the retention … and allow
// you to share the artifact like download to files or send to someone").
import SwiftUI
import UIKit
import JarvisKit

/// "Keep 2 weeks ⌄": a small plain menu at the card's bottom left (Dylan,
/// 2026-11-19: "just be a very simple selector"). It drops down the four
/// choices in place, the one in force ticked; picking one saves at once.
struct RetentionButton: View {
    @EnvironmentObject private var app: AppModel
    let report: Report

    var body: some View {
        let defaultDays = app.reportShelf?.keepDays ?? 14
        let current = Reports.retention(report, defaultDays: defaultDays)
        Menu {
            ForEach(Retention.choices, id: \.self) { choice in
                Button {
                    guard choice != current else { return }
                    Task { await app.setRetention(report.id, choice) }
                } label: {
                    if choice == current { Label(choice.label, systemImage: "checkmark") } else { Text(choice.label) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current.label)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .font(.footnote.weight(.semibold))
            .frame(minHeight: 44)
        }
        .tint(Theme.glacier)
        .accessibilityHint("Changes how long the report is kept")
    }
}

/// A file to hand to the share sheet.
struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// The system share sheet for a file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

