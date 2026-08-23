import SwiftUI

@main
struct ClockodoMenubarApp: App {
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        model.startBackgroundUpdates()
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(model)
        } label: {
            Label(model.menuBarTitle, systemImage: model.isRunning ? "stopwatch.fill" : "stopwatch")
                .task {
                    model.startBackgroundUpdates()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
