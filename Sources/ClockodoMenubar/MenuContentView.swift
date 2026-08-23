import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !model.isConfigured {
                CredentialsView(title: "Connect Clockodo")
            } else if showingSettings {
                CredentialsView(title: "Clockodo settings", allowForget: true)
            } else {
                timerContent
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Clockodo")
                    .font(.headline)
                Text(model.isRunning ? model.runningTargetTitle : "Time tracker")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isConfigured {
                Button {
                    showingSettings.toggle()
                } label: {
                    Image(systemName: showingSettings ? "xmark" : "gearshape")
                }
                .buttonStyle(.plain)
                .help(showingSettings ? "Close settings" : "Settings")
            }
        }
    }

    private var timerContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            connectionStatus

            todaySummary

            if model.isRunning {
                runningTimer
            } else {
                startTimerForm
            }

            Divider()

            HStack {
                Button {
                    Task { await model.retryConnection() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoading || model.isPerformingAction || model.isConnecting)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: model.connectionState.systemImage)
                .foregroundStyle(model.connectionState.isHealthy ? .green : .secondary)
            Text(model.connectionState.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if !model.connectionState.isHealthy && model.connectionState != .connecting {
                Button("Retry") {
                    Task { await model.retryConnection() }
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoading || model.isConnecting)
            }
        }
    }

    private var todaySummary: some View {
        HStack {
            Label("Today", systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(model.todayTotalText)
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
    }

    private var runningTimer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(elapsedText(since: model.runningEntry?.timeSince, now: model.now))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()

            if model.runningEntry != nil {
                VStack(alignment: .leading, spacing: 8) {
                    contextRow("Customer", value: model.runningCustomerName, systemImage: "person.2")
                    contextRow("Project", value: model.runningProjectName, systemImage: "folder")
                    if let service = model.runningServiceName {
                        contextRow("Service", value: service, systemImage: "wrench.and.screwdriver")
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            }

            if let note = model.runningEntry?.text, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button {
                Task { await model.stopClock() }
            } label: {
                Label(model.isPerformingAction ? "Stopping..." : "Stop timer", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(model.isPerformingAction)
        }
    }

    private func contextRow(_ label: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
    }

    private var startTimerForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isLoading && model.customers.isEmpty {
                ProgressView("Loading Clockodo data...")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Customer", selection: $model.selectedCustomerID) {
                    Text("Choose customer").tag(nil as Int?)
                    ForEach(model.customers) { customer in
                        Text(customer.name).tag(Optional(customer.id))
                    }
                }

                Picker("Project", selection: $model.selectedProjectID) {
                    Text("No project").tag(nil as Int?)
                    ForEach(filteredProjects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }

                Picker("Service", selection: $model.selectedServiceID) {
                    Text("Choose service").tag(nil as Int?)
                    ForEach(model.services) { service in
                        Text(service.name).tag(Optional(service.id))
                    }
                }

                TextField("Note (optional)", text: $model.note)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task {
                        if model.canStartLastConfiguration {
                            await model.startLastConfiguration()
                        } else {
                            await model.startClock()
                        }
                    }
                } label: {
                    Label(
                        model.isPerformingAction
                            ? "Starting..."
                            : (model.canStartLastConfiguration ? "Start last setup" : "Start timer"),
                        systemImage: "play.fill"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStartLastConfiguration || model.isPerformingAction)
            }
        }
        .onChange(of: model.selectedCustomerID) { _ in
            model.customerSelectionChanged()
        }
        .onChange(of: model.selectedProjectID) { _ in
            model.persistSelections()
        }
        .onChange(of: model.selectedServiceID) { _ in
            model.persistSelections()
        }
    }

    private var filteredProjects: [Project] {
        guard let customerID = model.selectedCustomerID else { return [] }
        return model.projects.filter { $0.customersID == customerID }
    }
}

struct CredentialsView: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    var allowForget = false

    @State private var email: String
    @State private var apiKey = ""

    init(title: String, allowForget: Bool = false) {
        self.title = title
        self.allowForget = allowForget
        _email = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if !allowForget {
                Text("Your API key is stored only in the macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Clockodo email", text: $email)
                .textFieldStyle(.roundedBorder)

            SecureField(allowForget ? "New API key" : "API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await model.saveCredentials(email: email, apiKey: apiKey) }
            } label: {
                Text(model.isConnecting ? "Checking connection..." : "Save and connect")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || apiKey.isEmpty
                    || model.isConnecting
            )

            if allowForget {
                Toggle(
                    "Start at login",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )

                Button("Forget credentials") {
                    model.forgetCredentials()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
        }
        .onAppear {
            email = model.credentials?.email ?? ""
        }
    }
}
