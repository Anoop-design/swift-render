import AppKit
import SwiftUI
import StudioCore

@main
struct SwiftRenderStudioApp: App {
    @State private var store = StudioStore()

    var body: some Scene {
        Window("SwiftRender Studio", id: "studio") {
            StudioView(store: store)
                .frame(minWidth: 1000, minHeight: 680)
                .onChange(of: store.settings) { _, _ in store.saveSettings() }
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1240, height: 820)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose App Folder…", action: store.chooseSource)
                    .keyboardShortcut("n").disabled(store.isBusy)
                Button("Open Film Project…", action: store.openProject)
                    .keyboardShortcut("o").disabled(store.isBusy)
                Divider()
                Button("Try Sample…", action: store.createSample).disabled(store.isBusy)
            }
            CommandMenu("Film") {
                Button("Copy Codex Brief", action: store.copyCodexBrief).disabled(!store.hasComposer || store.isBusy)
                Button("Render Preview", action: store.renderPreview).keyboardShortcut("r").disabled(!store.canRender)
                Button("Export Film", action: store.renderFinal).keyboardShortcut("e", modifiers: [.command, .shift]).disabled(!store.canRender)
                Button("Cancel", action: store.cancel).disabled(!store.isBusy)
            }
        }
    }
}
