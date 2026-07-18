import SwiftUI

@main
struct FocusSpaceApp: App {
    @StateObject private var store: FocusSpaceStore

    init() {
        let store = FocusSpaceStore()
        let arguments = CommandLine.arguments
        if let flagIndex = arguments.firstIndex(of: "--demo"),
           arguments.indices.contains(flagIndex + 1),
           let scene = DemoScene(slug: arguments[flagIndex + 1]) {
            store.preview(scene)
        }
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 650)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo", action: store.undo)
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!store.canUndo)
                Button("Redo", action: store.redo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!store.canRedo)
            }
        }
    }
}
