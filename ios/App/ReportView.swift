// A report from Jarvis, read inside the app (Dylan, 2026-11-18: "the reports
// should open from within the jarvis app and not link somewhere"). The page
// is fetched through JarvisClient and shown in a WKWebView with JavaScript
// off; it can scale and scroll, but never navigates away: a link to another
// /reports/{id} opens in this same reader, any other link does nothing.
// Close, a Keep switch and Delete (asked first) sit in the bar.
import SwiftUI
import WebKit
import JarvisKit

/// The report showing in the reader, as a sheet's item.
struct ReportPage: Identifiable, Equatable {
    let id: String
    /// The title, when the opener knows it (the list, a notice).
    var title: String?
}

/// The reader: the report's own page in the app's style.
struct ReportReader: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    /// The report showing; a link to another report changes it.
    @State var page: ReportPage
    @State private var fetch: ReportFetch?
    @State private var confirmingDelete = false
    /// The file in the share sheet.
    @State private var sharing: SharedFile?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.sky.ignoresSafeArea()
                switch fetch {
                case .none:
                    waiting("Opening the report…")
                case .page(let html):
                    ReportWeb(html: html, base: Reports.url(id: page.id, base: app.client.base) ?? app.client.base) { next in
                        page = ReportPage(id: next, title: app.reportShelf?.reports.first { $0.id == next }?.title)
                    }
                    .ignoresSafeArea(edges: .bottom)
                case .gone:
                    message(ReportFetch.goneWords, retry: false)
                case .failed(let words):
                    message(words, retry: true)
                }
                // Keep and Delete wait on the PC: a labelled, blocking wait.
                if let busy = app.reportBusy {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    waiting(busy)
                        .padding(28)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
                // Like the page: retention and Share at the bottom left.
                ToolbarItemGroup(placement: .bottomBar) {
                    if let report {
                        RetentionButton(report: report)
                    }
                    Button {
                        Task { if let url = await app.reportFile(id: page.id, title: title) { sharing = SharedFile(url: url) } }
                    } label: {
                        Image(systemName: "square.and.arrow.up").imageScale(.large)
                    }
                    .accessibilityLabel("Share")
                    .disabled(fetch == .gone)
                    Spacer()
                    if fetch != .gone {
                        Button("Delete", role: .destructive) { confirmingDelete = true }
                            .frame(minHeight: 44)
                    }
                }
            }
            .confirmationDialog("Delete this report?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        if await app.deleteReport(page.id) { dismiss() }
                    }
                }
                Button("Close", role: .cancel) {}
            } message: {
                Text("It's gone for good, here and on the PC.")
            }
        }
        .sheet(item: $sharing) { file in
            ShareSheet(url: file.url)
        }
        .alert("Report", isPresented: Binding(get: { app.reportMessage != nil }, set: { if !$0 { app.reportMessage = nil } })) {
            Button("Close", role: .cancel) {}
        } message: {
            Text(app.reportMessage ?? "")
        }
        .task(id: page.id) { await load() }
        .preferredColorScheme(.dark)
    }

    /// The report as the list knows it (size, Keep, when it's deleted).
    private var report: Report? {
        app.reportShelf?.reports.first { $0.id == page.id }
    }

    /// The bar's title: the report's, else a plain "Report".
    private var title: String {
        page.title ?? report?.title ?? "Report"
    }

    /// Fetches the page.
    private func load() async {
        fetch = nil
        fetch = await app.client.report(id: page.id)
    }

    /// A spinner with words.
    private func waiting(_ words: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(Theme.frost)
            Text(words).font(.headline).foregroundStyle(Theme.frost)
        }
    }

    /// A gone or failed report, plainly; a failed one can be tried again.
    private func message(_ words: String, retry: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: retry ? "wifi.exclamationmark" : "doc.questionmark")
                .font(.system(size: 34))
                .foregroundStyle(Theme.frostDim)
            Text(words)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.frost)
            if retry {
                Button("Try again") { Task { await load() } }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
        .padding(32)
    }
}

/// The report's HTML in a web view: no JavaScript, no leaving the page.
struct ReportWeb: UIViewRepresentable {
    let html: String
    /// The report's own address, so relative links resolve to /reports/.
    let base: URL
    /// A link to another report: open it in this reader.
    let onReport: (String) -> Void

    /// Builds the web view with scripts off.
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.loadHTMLString(html, baseURL: base)
        context.coordinator.shown = html
        return web
    }

    /// Loads new HTML when the reader moved to another report.
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onReport = onReport
        context.coordinator.base = base
        guard context.coordinator.shown != html else { return }
        context.coordinator.shown = html
        web.loadHTMLString(html, baseURL: base)
    }

    /// The navigation rules.
    func makeCoordinator() -> Rules { Rules(base: base, onReport: onReport) }

    /// Lets the page itself load and nothing else.
    final class Rules: NSObject, WKNavigationDelegate {
        var base: URL
        var onReport: (String) -> Void
        /// The HTML on screen, so an update only reloads for a new report.
        var shown: String?

        init(base: URL, onReport: @escaping (String) -> Void) {
            self.base = base
            self.onReport = onReport
        }

        /// The page's own load goes ahead; a tapped link to another report
        /// opens it here; every other navigation is refused.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .other, let url = action.request.url,
               url == base || url.absoluteString == "about:blank" {
                // loadHTMLString itself; a redirect elsewhere is refused below.
                decisionHandler(.allow)
                return
            }
            if let url = action.request.url {
                if url.fragment != nil, url.path == base.path {
                    // A jump within the report.
                    decisionHandler(.allow)
                    return
                }
                if let id = Reports.id(in: url, base: base) {
                    onReport(id)
                }
            }
            decisionHandler(.cancel)
        }
    }
}
