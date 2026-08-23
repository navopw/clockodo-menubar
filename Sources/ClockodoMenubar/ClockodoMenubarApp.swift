import SwiftUI

@main
struct ClockodoMenubarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(model)
        } label: {
            Label(model.menuBarTitle, systemImage: model.isRunning ? "stopwatch.fill" : "stopwatch")
        }
        .menuBarExtraStyle(.window)
    }
}
