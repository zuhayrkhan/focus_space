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
            CommandMenu("View") {
                Button("Frame Selected Branch", action: store.frameSelection)
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(!store.canFrameSelection)
                Divider()
                Button("Zoom In") { store.zoomCamera(by: 1.18, animated: true) }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { store.zoomCamera(by: 0.84, animated: true) }
                    .keyboardShortcut("-", modifiers: .command)
                Divider()
                Button("Pan Left") { store.panCamera(horizontal: 36, vertical: 0) }
                    .keyboardShortcut(.leftArrow, modifiers: .option)
                Button("Pan Right") { store.panCamera(horizontal: -36, vertical: 0) }
                    .keyboardShortcut(.rightArrow, modifiers: .option)
                Button("Pan Up") { store.panCamera(horizontal: 0, vertical: 36) }
                    .keyboardShortcut(.upArrow, modifiers: .option)
                Button("Pan Down") { store.panCamera(horizontal: 0, vertical: -36) }
                    .keyboardShortcut(.downArrow, modifiers: .option)
                Divider()
                Button("Reset View") { store.resetCamera() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
