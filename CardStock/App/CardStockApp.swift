import SwiftUI

/// Receives files opened from Finder (double-clicked .cardstock project
/// files and .cardstockstyle files), even before the window exists.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.saved.apply()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        model.handleOpen(urls)
    }
}

@main
struct CardStockApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private var model: AppModel { delegate.model }

    var body: some Scene {
        Window("CardStock", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1280, minHeight: 600)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.saveNow()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    model.saveNow()
                }
                // Coming back to CardStock: see if another Mac published meanwhile.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.checkGitHubForUpdates()
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Site…") { SitePanels.newSite(model) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Open Site…") { SitePanels.openSite(model) }
                    .keyboardShortcut("o")
                Button("Open from GitHub…") { model.isShowingOpenFromGitHub = true }
                    .keyboardShortcut("o", modifiers: [.command, .option])
                Divider()
                Button("Close Site") { model.close() }
                    .disabled(model.site == nil)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.saveNow() }
                    .keyboardShortcut("s")
                    .disabled(model.site == nil)
            }
            CommandGroup(replacing: .help) {
                Button("CardStock Help Center") { model.showHelp() }
                    .keyboardShortcut("?", modifiers: .command)
                    .disabled(model.site == nil)
            }
            CommandMenu("Site") {
                Group {
                    Button("Generate Flat HTML") { model.build() }
                        .keyboardShortcut("b", modifiers: [.command, .shift])
                    Button("Open Website in Browser") { model.openWebsite() }
                        .keyboardShortcut("o", modifiers: [.command, .shift])
                    Divider()
                    Button("Reload from Disk") { model.reload() }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                    Divider()
                    Button("Show in Finder") {
                        if let root = model.site?.root { NSWorkspace.shared.open(root) }
                    }
                }
                .disabled(model.site == nil)
            }
        }

        // CardStock → Settings… (⌘,)
        Settings {
            AppSettingsView()
                .environment(model)
        }
    }
}
