import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @ObservedObject var tabStore: DocumentTabStore

    var body: some View {
        Group {
            if tabStore.tabs.isEmpty {
                ContentUnavailableView(
                    "Open a Markdown file",
                    systemImage: "doc.text",
                    description: Text("Choose one or more .md files to read them as rendered documents in tabs.")
                )
            } else {
                TabView(selection: tabSelection) {
                    ForEach(tabStore.tabs) { tab in
                        HTMLDocumentView(html: MarkdownRenderer.render(document: tab.document))
                            .tabItem { Text(tab.title) }
                            .tag(tab.id)
                    }
                }
            }
        }
        .navigationTitle(selectedTab?.document.url.lastPathComponent ?? "Tackle Mark")
        .toolbar {
            Button("Open Markdown…", action: chooseDocument)
            Button("Close Tab", systemImage: "xmark", action: tabStore.closeSelectedTab)
                .keyboardShortcut("w", modifiers: .command)
                .disabled(tabStore.selectedTabID == nil)
        }
        .alert("Couldn’t Open File", isPresented: Binding(
            get: { tabStore.errorMessage != nil },
            set: { if !$0 { tabStore.dismissError() } }
        )) {
            Button("OK", role: .cancel, action: tabStore.dismissError)
        } message: {
            Text(tabStore.errorMessage ?? "")
        }
    }

    private func chooseDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md") ?? .plainText
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }

        tabStore.open(urls: panel.urls)
    }

    private var selectedTab: DocumentTab? {
        tabStore.tabs.first { $0.id == tabStore.selectedTabID }
    }

    private var tabSelection: Binding<URL?> {
        Binding(
            get: { tabStore.selectedTabID },
            set: { tabStore.select(tabID: $0) }
        )
    }
}

private struct HTMLDocumentView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}
