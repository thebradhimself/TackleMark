import AppKit
import Combine
import SwiftUI

@main
struct TackleMarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Tackle Mark", id: "main") {
            ContentView(tabStore: appDelegate.tabStore)
        }
        .defaultSize(width: 880, height: 620)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let tabStore = DocumentTabStore()

    func application(_ application: NSApplication, open urls: [URL]) {
        tabStore.open(urls: urls)
    }
}

@MainActor
final class DocumentTabStore: ObservableObject {
    @Published private(set) var tabs: [DocumentTab] = []
    @Published private(set) var selectedTabID: URL?
    @Published var errorMessage: String?

    func open(urls: [URL]) {
        for url in urls where url.isFileURL {
            let identifier = DocumentTab.identifier(for: url)

            if let existingTab = tabs.first(where: { $0.id == identifier }) {
                selectedTabID = existingTab.id
                continue
            }

            do {
                // Keep the Finder-supplied URL for reading. Its security scope is
                // preserved while the normalized path is used only for deduplication.
                let document = try MarkdownDocument(url: url)
                let tab = DocumentTab(document: document, id: identifier)
                tabs.append(tab)
                selectedTabID = tab.id
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func closeSelectedTab() {
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID })
        else { return }

        tabs.remove(at: index)
        self.selectedTabID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
    }

    func select(tabID: URL?) {
        selectedTabID = tabID
    }

    func dismissError() {
        errorMessage = nil
    }
}

struct DocumentTab: Identifiable {
    let document: MarkdownDocument
    let id: URL

    init(document: MarkdownDocument, id: URL? = nil) {
        self.document = document
        self.id = id ?? Self.identifier(for: document.url)
    }

    var title: String { document.url.deletingPathExtension().lastPathComponent }

    static func identifier(for url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
}
