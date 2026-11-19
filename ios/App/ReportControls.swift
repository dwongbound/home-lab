// The report's retention and sharing controls, shared by the Reports list
// and the reader (Dylan, 2026-11-19: "it should just say keep 2 weeks …
// when you tap that it can allow you to change the retention … and allow
// you to share the artifact like download to files or send to someone").
import SwiftUI
import UIKit
import JarvisKit

/// "Keep 2 weeks": a compact button; tapping it picks 2 weeks, 1 month,
/// 3 months or forever (the one in force ticked), with the delete date.
struct RetentionButton: View {
    @EnvironmentObject private var app: AppModel
    let report: Report

    var body: some View {
        let defaultDays = app.reportShelf?.keepDays ?? 14
        let current = Reports.retention(report, defaultDays: defaultDays)
        Menu {
            Section(Reports.deleteLine(report, retention: current)) {
                ForEach(Retention.choices, id: \.self) { choice in
                    Button {
                        guard choice != current else { return }
                        Task { await app.setRetention(report.id, choice) }
                    } label: {
                        if choice == current { Label(choice.label, systemImage: "checkmark") } else { Text(choice.label) }
                    }
                }
            }
        } label: {
            Text(current.label)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Capsule().fill(Color.white.opacity(0.08)))
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
