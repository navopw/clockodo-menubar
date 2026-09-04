import AppKit
import SwiftUI

private enum Layout {
    static let panelWidth: CGFloat = 320
    static let horizontalInset: CGFloat = 14
    static let rowSpacing: CGFloat = 6
    static let labelColumnWidth: CGFloat = 58
    static let labelColumnSpacing: CGFloat = 10
    static var controlColumnWidth: CGFloat {
        panelWidth - 2 * horizontalInset - labelColumnWidth - labelColumnSpacing
    }
}

private let timeOfDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
}()

struct MenuContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
                .padding(.horizontal, Layout.horizontalInset)
                .padding(.vertical, 12)

            if let errorMessage = model.errorMessage {
                Divider()
                errorBanner(errorMessage)
            }

            Divider()

            footer
        }
        .frame(width: Layout.panelWidth)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: model.isRunning ? "stopwatch.fill" : "stopwatch")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(model.isRunning ? Color.green : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("Clockodo")
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            if model.isConfigured {
                Button {
                    showingSettings.toggle()
                } label: {
                    Image(systemName: showingSettings ? "xmark.circle.fill" : "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showingSettings ? "Close settings" : "Settings")
                .accessibilityLabel(showingSettings ? "Close settings" : "Settings")
            }
        }
        .padding(.horizontal, Layout.horizontalInset)
        .padding(.vertical, 10)
    }

    private var headerSubtitle: String {
        if !model.isConfigured {
            return "Not connected"
        }
        if showingSettings {
            return model.credentials?.email ?? "Settings"
        }
        return model.isRunning ? model.runningTargetTitle : "No timer running"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !model.isConfigured {
            CredentialsView(title: "Connect Clockodo")
        } else if showingSettings {
            CredentialsView(title: "Clockodo settings", allowForget: true)
        } else if model.isRunning {
            runningContent
        } else {
            idleContent
        }
    }

    // MARK: - Running

    private var runningContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        StatusDot(color: .green)
                        captionLabel("Running")
                    }
                    Text(elapsedText(since: model.runningEntry?.timeSince, now: model.now))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    captionLabel("Today")
                    Text(model.todayTotalText)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            detailCard

            Button {
                Task { await model.stopClock() }
            } label: {
                Label(model.isPerformingAction ? "Stopping…" : "Stop timer", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.stopRed)
            .disabled(model.isPerformingAction)
        }
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            detailRow("Customer", value: model.runningCustomerName, systemImage: "person.2")
            detailRow("Project", value: model.runningProjectName, systemImage: "folder")
            if let service = model.runningServiceName {
                detailRow("Service", value: service, systemImage: "wrench.and.screwdriver")
            }
            if let note = model.runningEntry?.text, !note.isEmpty {
                detailRow("Note", value: note, systemImage: "text.alignleft")
            }
            if let start = ClockodoDate.date(from: model.runningEntry?.timeSince) {
                detailRow("Started", value: timeOfDayFormatter.string(from: start), systemImage: "clock")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func detailRow(_ label: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .center)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: Layout.labelColumnWidth, alignment: .leading)

            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(value)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    captionLabel("Today")
                    Text(model.todayTotalText)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                if let updated = model.todayTotalUpdated {
                    Text("Updated \(timeOfDayFormatter.string(from: updated))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if model.isLoading && model.customers.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading Clockodo data…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
            } else {
                startTimerForm
            }
        }
    }

    private var startTimerForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                fieldRow("Customer") {
                    Picker("Customer", selection: $model.selectedCustomerID) {
                        Text("Choose customer").tag(nil as Int?)
                        ForEach(model.customers) { customer in
                            Text(customer.name).tag(Optional(customer.id))
                        }
                    }
                    .labelsHidden()
                }

                fieldRow("Project") {
                    Picker("Project", selection: $model.selectedProjectID) {
                        Text("No project").tag(nil as Int?)
                        ForEach(filteredProjects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    .labelsHidden()
                    .disabled(filteredProjects.isEmpty)
                }

                fieldRow("Service") {
                    Picker("Service", selection: $model.selectedServiceID) {
                        Text("Choose service").tag(nil as Int?)
                        ForEach(model.services) { service in
                            Text(service.name).tag(Optional(service.id))
                        }
                    }
                    .labelsHidden()
                }

                fieldRow("Note") {
                    TextField("Optional", text: $model.note)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Button {
                Task { await model.startLastConfiguration() }
            } label: {
                Label(model.isPerformingAction ? "Starting…" : "Start timer", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canStartLastConfiguration || model.isPerformingAction)
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

    private func fieldRow(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: Layout.labelColumnSpacing) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Layout.labelColumnWidth, alignment: .trailing)

            control()
                .frame(width: Layout.controlColumnWidth, alignment: .leading)
        }
    }

    private var filteredProjects: [Project] {
        guard let customerID = model.selectedCustomerID else { return [] }
        return model.projects.filter { $0.customersID == customerID }
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)

            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Layout.horizontalInset)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.10))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if model.isConfigured {
                HStack(spacing: 5) {
                    StatusDot(color: model.connectionState.isHealthy ? .green : .secondary)
                    Text(model.connectionState.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .help(lastUpdateText)
            }

            Spacer(minLength: 0)

            if model.isConfigured {
                Button {
                    Task { await model.retryConnection() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh")
                .accessibilityLabel("Refresh")
                .disabled(model.isLoading || model.isPerformingAction || model.isConnecting)
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit Clockodo")
        }
        .padding(.horizontal, Layout.horizontalInset)
        .padding(.vertical, 7)
    }

    // MARK: - Shared pieces

    private var lastUpdateText: String {
        guard let lastUpdated = model.lastUpdated else { return "Not updated yet" }
        return "Last update \(timeOfDayFormatter.string(from: lastUpdated))"
    }

    private func captionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func formLabel(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

private extension Color {
    /// A saturated, unmistakably red tint for the stop action, instead of the
    /// slightly orange system red. Darkened in light mode and lifted in dark
    /// mode so the white button label stays legible in both appearances.
    static let stopRed = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 1.0, green: 0.16, blue: 0.16, alpha: 1)
            : NSColor(srgbRed: 0.84, green: 0.0, blue: 0.0, alpha: 1)
    })
}

private struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("Create an API key in Clockodo under Personal settings. It is stored only in the macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Clockodo email", text: $email)
                    .textFieldStyle(.roundedBorder)

                SecureField(allowForget ? "New API key" : "API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await model.saveCredentials(email: email, apiKey: apiKey) }
                } label: {
                    Text(model.isConnecting ? "Checking connection…" : "Save and connect")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || apiKey.isEmpty
                        || model.isConnecting
                )
            }

            if allowForget {
                Divider()

                HStack(spacing: 8) {
                    Text("Start at login")
                        .font(.callout)

                    Spacer(minLength: 8)

                    Toggle("Start at login", isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                Button("Forget credentials") {
                    model.forgetCredentials()
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            email = model.credentials?.email ?? ""
        }
    }
}
