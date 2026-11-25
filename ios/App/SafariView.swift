// Web links from Jarvis's messages open in Safari inside the app (Dylan,
// 2026-11-25: "links should be clickable in chat on the app"), the way
// reports open in the app's own reader: Close (Done) and he's back in Chat.
import SafariServices
import SwiftUI

/// One web page to show in the in-app Safari view.
struct WebPage: Identifiable, Equatable {
    let url: URL
    var id: String { url.absoluteString }

    /// Only http and https open inside the app; mail, phone and the rest go
    /// to their own apps as before.
    static func opensInApp(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "https" || scheme == "http"
    }
}

/// Apple's Safari view, wrapped for SwiftUI.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    /// Makes the Safari view, tinted like the rest of the app.
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(Theme.glacier)
        return controller
    }

    /// A Safari view can't change page; a new link makes a new sheet.
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
