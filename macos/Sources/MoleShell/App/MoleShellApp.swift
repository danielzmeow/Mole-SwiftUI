import SwiftUI

@main
struct MoleShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Mole SwiftUI") {
            ContentView(model: model)
                .frame(minWidth: 1000, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Mole") {
                Button("重新检测 CLI") { model.connect() }
                    .disabled(model.busy)
                Button("取消读取") { model.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.busy)
            }
        }
        Settings { ConnectionView(model: model).frame(width: 560) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
