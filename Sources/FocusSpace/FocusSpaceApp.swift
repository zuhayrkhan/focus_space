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
        let windowSize = ReleaseWindowConfiguration.requestedSize
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 650)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: windowSize.width, height: windowSize.height)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Focus Space") {
                    store.saveImmediately()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo", action: store.undo)
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!store.canUndo)
                Button("Redo", action: store.redo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!store.canRedo)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find in Focus Space…", action: store.requestSearch)
                    .keyboardShortcut("f", modifiers: .command)
            }
            FocusSpaceViewCommands(store: store)
            ExperiencePreviewCommands(store: store)
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

private struct FocusSpaceViewCommands: Commands {
    @ObservedObject var store: FocusSpaceStore
    @FocusedValue(\.workspaceViewActions) private var workspaceActions

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Arrange Mind Map", action: store.arrangeMindMap)
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!store.canArrange)
            Button("Frame Selected Branch", action: store.frameSelection)
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!store.canFrameSelection)
            Divider()
            Button("Zoom In") { store.zoomCamera(by: 1.18, animated: true) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { store.zoomCamera(by: 0.84, animated: true) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Reset to Canonical Universe") { store.resetCamera() }
                .keyboardShortcut("0", modifiers: .command)
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
            Button(
                workspaceActions?.isInspectorVisible == true ? "Hide Inspector" : "Show Inspector"
            ) {
                workspaceActions?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(workspaceActions == nil)
            Button(
                workspaceActions?.isColourKeyVisible == true ? "Hide Colour Key" : "Show Colour Key"
            ) {
                workspaceActions?.toggleColourKey()
            }
            .disabled(workspaceActions == nil)
            Button(
                workspaceActions?.isDistractionFree == true
                    ? "Restore Workspace Chrome"
                    : "Distraction-Free Workspace"
            ) {
                workspaceActions?.toggleDistractionFree()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(workspaceActions == nil)
        }
    }
}

private struct ExperiencePreviewCommands: Commands {
    @ObservedObject var store: FocusSpaceStore

    var body: some Commands {
        CommandGroup(before: .help) {
            Menu("Experience Previews") {
                Button {
                    store.preview(nil)
                } label: {
                    previewLabel("Personal Space", isSelected: store.demoScene == nil)
                }
                Divider()
                ForEach(DemoScene.allCases) { scene in
                    Button {
                        store.preview(scene)
                    } label: {
                        previewLabel(scene.rawValue, isSelected: store.demoScene == scene)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func previewLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

enum ReleaseWindowConfiguration {
    static var requestedSize: (width: CGFloat, height: CGFloat) {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--window-size"),
              arguments.indices.contains(index + 1) else { return (1240, 780) }
        return switch arguments[index + 1] {
        case "compact": (980, 650)
        case "large": (1600, 1000)
        default: (1240, 780)
        }
    }
}
