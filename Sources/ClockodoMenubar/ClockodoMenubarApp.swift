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
            menuBarLabel
                .task {
                    model.startBackgroundUpdates()
                }
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        if model.isRunning {
            Label {
                Text(model.menuBarTitle)
                    .monospacedDigit()
            } icon: {
                Image(systemName: "stopwatch.fill")
            }
            .accessibilityLabel("Clockodo timer running, \(model.menuBarTitle)")
        } else {
            Image(systemName: "stopwatch")
                .accessibilityLabel("Clockodo, no timer running")
        }
    }
}
