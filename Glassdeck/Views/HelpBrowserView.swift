import SwiftUI
import WebKit

/// In-app documentation browser using iOS 26 native SwiftUI WebView.
///
/// Provides SSH command reference and man pages without leaving the app.
struct HelpBrowserView: View {
    @State private var urlString = "https://man.openbsd.org/ssh"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebViewWrapper(urlString: urlString)
                .navigationTitle("SSH Reference")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("SSH Man Page") {
                                urlString = "https://man.openbsd.org/ssh"
                            }
                            Button("SSH Config") {
                                urlString = "https://man.openbsd.org/ssh_config"
                            }
                            Button("SSHD Config") {
                                urlString = "https://man.openbsd.org/sshd_config"
                            }
                        } label: {
                            Image(systemName: "book")
                        }
                    }
                }
        }
    }
}

struct WebViewWrapper: UIViewRepresentable {
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }
}
