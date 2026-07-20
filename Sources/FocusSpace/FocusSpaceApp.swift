import AppKit
import SwiftUI

final class FocusSpaceAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else { return }
        NSApplication.shared.applicationIconImage = icon
    }
}

@main
struct FocusSpaceApp: App {
    @NSApplicationDelegateAdaptor(FocusSpaceAppDelegate.self) private var appDelegate
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
                Button("Arrange Mind Map", action: store.arrangeMindMap)
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(!store.canArrange)
                Divider()
                Button("Frame Selected Branch", action: store.frameSelection)
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(!store.canFrameSelection)
                Divider()
                Button("Zoom In") { store.zoomCamera(by: 1.18, animated: true) }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { store.zoomCamera(by: 0.84, animated: true) }
                    .keyboardShortcut("-", modifiers: .command)
                Divider()
                Button("Move Universe Left") { store.orbitCamera(horizontal: -36, vertical: 0) }
                    .keyboardShortcut(.leftArrow, modifiers: .option)
                Button("Move Universe Right") { store.orbitCamera(horizontal: 36, vertical: 0) }
                    .keyboardShortcut(.rightArrow, modifiers: .option)
                Button("Move Universe Up") { store.orbitCamera(horizontal: 0, vertical: -36) }
                    .keyboardShortcut(.upArrow, modifiers: .option)
                Button("Move Universe Down") { store.orbitCamera(horizontal: 0, vertical: 36) }
                    .keyboardShortcut(.downArrow, modifiers: .option)
                Divider()
                Button("Reset View") { store.resetCamera() }
                    .keyboardShortcut("0", modifiers: .command)
            }
            CommandMenu("Navigate") {
                Button("Previous Thought", action: store.selectPreviousThought)
                    .keyboardShortcut(.upArrow, modifiers: .control)
                Button("Next Thought", action: store.selectNextThought)
                    .keyboardShortcut(.downArrow, modifiers: .control)
                Button("Parent Thought", action: store.selectParentThought)
                    .keyboardShortcut(.leftArrow, modifiers: .control)
                    .disabled(store.selection == nil)
                Button("First Child Thought", action: store.selectFirstChildThought)
                    .keyboardShortcut(.rightArrow, modifiers: .control)
                    .disabled(store.selection == nil)
                Divider()
                Button("Move Thought Left") { store.moveSelection(horizontal: -0.25, vertical: 0) }
                    .keyboardShortcut(.leftArrow, modifiers: [.control, .command])
                    .disabled(store.selection == nil)
                Button("Move Thought Right") { store.moveSelection(horizontal: 0.25, vertical: 0) }
                    .keyboardShortcut(.rightArrow, modifiers: [.control, .command])
                    .disabled(store.selection == nil)
                Button("Move Thought Up") { store.moveSelection(horizontal: 0, vertical: 0.25) }
                    .keyboardShortcut(.upArrow, modifiers: [.control, .command])
                    .disabled(store.selection == nil)
                Button("Move Thought Down") { store.moveSelection(horizontal: 0, vertical: -0.25) }
                    .keyboardShortcut(.downArrow, modifiers: [.control, .command])
                    .disabled(store.selection == nil)
                Divider()
                Button("Pull Thought Forward") {
                    if let id = store.selection { store.shiftAttention(id, by: 0.08) }
                }
                .keyboardShortcut(.upArrow, modifiers: [.option, .command])
                .disabled(store.selection == nil)
                Button("Push Thought Back") {
                    if let id = store.selection { store.shiftAttention(id, by: -0.08) }
                }
                .keyboardShortcut(.downArrow, modifiers: [.option, .command])
                .disabled(store.selection == nil)
            }
        }
    }
}
