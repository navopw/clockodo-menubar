import Foundation
import ServiceManagement
import SwiftUI

enum ConnectionState: Equatable, Sendable {
    case unknown
    case connecting
    case connected
    case offline
    case unauthorized
    case forbidden
    case rateLimited

    var title: String {
        switch self {
        case .unknown:
            return "Connection not checked"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .offline:
            return "Offline"
        case .unauthorized:
            return "Credentials rejected"
        case .forbidden:
            return "Access denied"
        case .rateLimited:
            return "Rate limited"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown:
            return "questionmark.circle"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .connected:
            return "checkmark.circle.fill"
        case .offline:
            return "wifi.slash"
        case .unauthorized, .forbidden:
            return "exclamationmark.shield"
        case .rateLimited:
            return "clock.badge.exclamationmark"
        }
    }

    var isHealthy: Bool {
        self == .connected
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var credentials: ClockodoCredentials?
    @Published private(set) var runningEntry: ClockodoEntry?
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var projects: [Project] = []
    @Published private(set) var services: [Service] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPerformingAction = false
    @Published private(set) var isConnecting = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var todayTotalSeconds = 0
    @Published private(set) var todayTotalUpdated: Date?
    @Published private(set) var connectionState = ConnectionState.unknown
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published var selectedCustomerID: Int?
    @Published var selectedProjectID: Int?
    @Published var selectedServiceID: Int?
    @Published var note = ""
    @Published var errorMessage: String?
    @Published private(set) var now = Date()

    private let keychain: any CredentialStore
    private let clientFactory: @Sendable (ClockodoCredentials) -> any ClockodoAPIClient
    private let userDefaults: UserDefaults
    private var client: (any ClockodoAPIClient)?
    private var backgroundTask: Task<Void, Never>?
    private var isBootstrapping = false
    private var bootstrapRequested = false
    private var credentialsGeneration = 0
    private var stateVersion = 0
    private var clockOffset: TimeInterval = 0

    init(
        keychain: any CredentialStore = KeychainStore(),
        clientFactory: @escaping @Sendable (ClockodoCredentials) -> any ClockodoAPIClient = {
            ClockodoClient(credentials: $0)
        },
        userDefaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.clientFactory = clientFactory
        self.userDefaults = userDefaults
        launchAtLoginEnabled = Self.isLaunchAtLoginEnabled
        loadStoredCredentials()
        selectedCustomerID = userDefaults.object(forKey: "selectedCustomerID") as? Int
        selectedProjectID = userDefaults.object(forKey: "selectedProjectID") as? Int
        selectedServiceID = userDefaults.object(forKey: "selectedServiceID") as? Int
    }

    deinit {
        backgroundTask?.cancel()
    }

    var isConfigured: Bool {
        credentials != nil
    }

    var isRunning: Bool {
        runningEntry != nil
    }

    var todayTotalText: String {
        durationText(seconds: todayTotalSeconds)
    }

    var canStartLastConfiguration: Bool {
        guard let selectedCustomerID,
              let selectedServiceID,
              customers.contains(where: { $0.id == selectedCustomerID }),
              services.contains(where: { $0.id == selectedServiceID }) else {
            return false
        }

        guard let selectedProjectID else { return true }
        return projects.contains {
            $0.id == selectedProjectID && $0.customersID == selectedCustomerID
        }
    }

    var menuBarTitle: String {
        guard let runningEntry else { return "Clockodo" }
        return elapsedText(since: runningEntry.timeSince, now: now)
    }

    var runningTargetTitle: String {
        guard runningEntry != nil else { return "Running" }
        let names = [runningCustomerName, runningProjectName]
            .filter { $0 != "No project" && $0 != "Unknown customer" }
        return names.isEmpty ? "Running timer" : names.joined(separator: " / ")
    }

    var runningCustomerName: String {
        guard let entry = runningEntry else { return "Unknown customer" }
        if let name = entry.customersName, !name.isEmpty {
            return name
        }
        if let id = entry.customersID {
            return customers.first(where: { $0.id == id })?.name ?? "Customer #\(id)"
        }
        return "Unknown customer"
    }

    var runningProjectName: String {
        guard let entry = runningEntry else { return "No project" }
        if let name = entry.projectsName, !name.isEmpty {
            return name
        }
        guard let id = entry.projectsID else { return "No project" }
        return projects.first(where: { $0.id == id })?.name ?? "Project #\(id)"
    }

    var runningServiceName: String? {
        guard let entry = runningEntry else { return nil }
        if let name = entry.servicesName, !name.isEmpty {
            return name
        }
        guard let id = entry.servicesID else { return nil }
        return services.first(where: { $0.id == id })?.name ?? "Service #\(id)"
    }

    func startBackgroundUpdates() {
        guard backgroundTask == nil else { return }

        backgroundTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await bootstrap()
            await refreshTodayTotal()
            var lastClockRefresh = Date()
            var lastTodayTotalRefresh = Date()

            while !Task.isCancelled {
                if isRunning {
                    now = Date().addingTimeInterval(clockOffset)
                }
                if !isPerformingAction && Date().timeIntervalSince(lastClockRefresh) >= 60 {
                    await refreshClock()
                    lastClockRefresh = Date()
                }
                if !isPerformingAction && Date().timeIntervalSince(lastTodayTotalRefresh) >= 300 {
                    await refreshTodayTotal()
                    lastTodayTotalRefresh = Date()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func refreshClock() async {
        guard !isPerformingAction, let client else { return }
        let generation = credentialsGeneration
        let requestVersion = stateVersion

        do {
            let response = try await client.getClock()
            guard generation == credentialsGeneration,
                  requestVersion == stateVersion,
                  !isPerformingAction else { return }
            applyClockResponse(response)
            lastUpdated = Date()
            connectionState = .connected
            errorMessage = nil
        } catch {
            guard generation == credentialsGeneration,
                  requestVersion == stateVersion,
                  !isPerformingAction else { return }
            record(error: error)
        }
    }

    func bootstrap(initialClock: ClockResponse? = nil) async {
        guard let client else { return }
        guard !isBootstrapping else {
            bootstrapRequested = true
            return
        }

        isLoading = true
        isBootstrapping = true
        connectionState = .connecting
        let generation = credentialsGeneration

        var loadedClock: ClockResponse?
        var clockError: Error?
        if let initialClock {
            loadedClock = initialClock
        } else {
            do {
                loadedClock = try await client.getClock()
            } catch {
                clockError = error
            }
        }

        async let customerResponse: [Customer]? = customers.isEmpty ? try? client.getCustomers() : customers
        async let projectResponse: [Project]? = projects.isEmpty ? try? client.getProjects() : projects
        async let serviceResponse: [Service]? = services.isEmpty ? try? client.getServices() : services

        let loadedCustomers = await customerResponse
        let loadedProjects = await projectResponse
        let loadedServices = await serviceResponse

        if generation == credentialsGeneration {
            if let loadedClock {
                applyClockResponse(loadedClock)
            }
            if let loadedCustomers {
                customers = loadedCustomers
            }
            if let loadedProjects {
                projects = loadedProjects
            }
            if let loadedServices {
                services = loadedServices
            }

            if loadedClock != nil || loadedCustomers != nil || loadedProjects != nil || loadedServices != nil {
                lastUpdated = Date()
            }

            if loadedClock != nil && loadedCustomers != nil && loadedProjects != nil && loadedServices != nil {
                connectionState = .connected
                errorMessage = nil
            } else if let clockError {
                record(error: clockError)
            } else {
                connectionState = .offline
                errorMessage = "Clockodo data could not be fully loaded. Use Refresh to try again."
            }
            if loadedCustomers != nil && loadedProjects != nil && loadedServices != nil {
                selectFirstAvailableValuesIfNeeded()
            }
        }

        isBootstrapping = false
        isLoading = false

        if bootstrapRequested {
            bootstrapRequested = false
            await bootstrap()
        }
    }

    func refreshTodayTotal() async {
        guard let client else { return }
        let generation = credentialsGeneration
        let range = todayRange()

        do {
            let entries = try await client.getEntries(from: range.start, until: range.end)
            guard generation == credentialsGeneration else { return }
            todayTotalSeconds = entries.reduce(into: 0) { total, entry in
                total += duration(for: entry, within: range, now: now)
            }
            todayTotalUpdated = Date()
            if connectionState != .unauthorized,
               connectionState != .forbidden,
               connectionState != .rateLimited {
                connectionState = .connected
            }
        } catch {
            guard generation == credentialsGeneration else { return }
            record(error: error)
        }
    }

    func retryConnection() async {
        await bootstrap()
        await refreshTodayTotal()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = Self.isLaunchAtLoginEnabled
            if enabled && !launchAtLoginEnabled {
                errorMessage = "Open System Settings to approve starting Clockodo at login."
            } else {
                errorMessage = nil
            }
        } catch {
            launchAtLoginEnabled = Self.isLaunchAtLoginEnabled
            errorMessage = error.localizedDescription
        }
    }

    private func applyClockResponse(_ response: ClockResponse) {
        runningEntry = response.running
        if let serverNow = ClockodoDate.date(from: response.currentTime) {
            clockOffset = serverNow.timeIntervalSince(Date())
        } else {
            clockOffset = 0
        }
        now = Date().addingTimeInterval(clockOffset)
    }

    func startClock() async {
        guard let client else {
            errorMessage = "Connect to Clockodo before starting the timer."
            return
        }
        guard let selectedCustomerID, let selectedServiceID else {
            errorMessage = "Choose a customer and service before starting the timer."
            return
        }
        guard !isPerformingAction else { return }

        let projectID = validProjectID
        if projectID != selectedProjectID {
            selectedProjectID = projectID
            persistSelections()
        }

        isPerformingAction = true
        stateVersion += 1
        let generation = credentialsGeneration
        let actionVersion = stateVersion
        defer { isPerformingAction = false }

        do {
            let response = try await client.startClock(
                customerID: selectedCustomerID,
                serviceID: selectedServiceID,
                projectID: projectID,
                text: note
            )
            guard generation == credentialsGeneration, actionVersion == stateVersion else { return }
            applyClockResponse(response)
            note = ""
            lastUpdated = Date()
            connectionState = .connected
            errorMessage = nil
            await refreshTodayTotal()
        } catch {
            guard generation == credentialsGeneration, actionVersion == stateVersion else { return }
            errorMessage = error.localizedDescription
        }
    }

    func stopClock() async {
        guard let client, let entryID = runningEntry?.id else { return }
        guard !isPerformingAction else { return }

        isPerformingAction = true
        stateVersion += 1
        let generation = credentialsGeneration
        let actionVersion = stateVersion
        defer { isPerformingAction = false }

        do {
            let response = try await client.stopClock(entryID: entryID)
            guard generation == credentialsGeneration, actionVersion == stateVersion else { return }
            applyClockResponse(response)
            errorMessage = nil
            lastUpdated = Date()
            connectionState = .connected
            await refreshTodayTotal()
        } catch {
            guard generation == credentialsGeneration, actionVersion == stateVersion else { return }
            errorMessage = error.localizedDescription
        }
    }

    func saveCredentials(email: String, apiKey: String) async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !email.isEmpty, !apiKey.isEmpty else {
            errorMessage = "Enter both your Clockodo email address and API key."
            return
        }
        guard !isConnecting else { return }

        isConnecting = true
        connectionState = .connecting
        do {
            let newCredentials = ClockodoCredentials(email: email, apiKey: apiKey)
            let newClient = clientFactory(newCredentials)
            let initialClock = try await newClient.getClock()
            try keychain.save(email, account: "email")
            try keychain.save(apiKey, account: "apiKey")
            credentials = newCredentials
            client = newClient
            credentialsGeneration += 1
            stateVersion += 1
            runningEntry = nil
            customers = []
            projects = []
            services = []
            clockOffset = 0
            now = Date()
            errorMessage = nil
            await bootstrap(initialClock: initialClock)
            await refreshTodayTotal()
        } catch {
            record(error: error)
        }
        isConnecting = false
    }

    func forgetCredentials() {
        do {
            try keychain.delete(account: "email")
            try keychain.delete(account: "apiKey")
            credentialsGeneration += 1
            stateVersion += 1
            backgroundTask?.cancel()
            backgroundTask = nil
            credentials = nil
            client = nil
            runningEntry = nil
            customers = []
            projects = []
            services = []
            clockOffset = 0
            now = Date()
            todayTotalSeconds = 0
            todayTotalUpdated = nil
            connectionState = .unknown
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func persistSelections() {
        userDefaults.set(selectedCustomerID, forKey: "selectedCustomerID")
        userDefaults.set(selectedProjectID, forKey: "selectedProjectID")
        userDefaults.set(selectedServiceID, forKey: "selectedServiceID")
    }

    func customerSelectionChanged() {
        selectedProjectID = validProjectID
        persistSelections()
    }

    func startLastConfiguration() async {
        guard canStartLastConfiguration else {
            errorMessage = "The saved timer setup is no longer available. Choose a customer and service."
            return
        }
        await startClock()
    }

    private func loadStoredCredentials() {
        do {
            guard let email = try keychain.read(account: "email"),
                  let apiKey = try keychain.read(account: "apiKey") else { return }
            let storedCredentials = ClockodoCredentials(email: email, apiKey: apiKey)
            credentials = storedCredentials
            client = clientFactory(storedCredentials)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectFirstAvailableValuesIfNeeded() {
        if selectedCustomerID == nil || !customers.contains(where: { $0.id == selectedCustomerID }) {
            selectedCustomerID = customers.first?.id
        }
        if selectedServiceID == nil || !services.contains(where: { $0.id == selectedServiceID }) {
            selectedServiceID = services.first?.id
        }
        selectedProjectID = validProjectID
        persistSelections()
    }

    private var validProjectID: Int? {
        guard let selectedCustomerID, let selectedProjectID else { return nil }
        return projects.contains {
            $0.id == selectedProjectID && $0.customersID == selectedCustomerID
        } ? selectedProjectID : nil
    }

    private static var isLaunchAtLoginEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    private func todayRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    private func duration(
        for entry: ClockodoEntry,
        within range: (start: Date, end: Date),
        now: Date
    ) -> Int {
        guard let start = ClockodoDate.date(from: entry.timeSince) else {
            return max(0, entry.duration ?? 0)
        }

        let end: Date?
        if let timeUntil = ClockodoDate.date(from: entry.timeUntil) {
            end = timeUntil
        } else if entry.id == runningEntry?.id {
            end = now
        } else {
            end = nil
        }

        guard let end else { return max(0, entry.duration ?? 0) }

        let overlapStart = max(start, range.start)
        let overlapEnd = min(end, range.end)
        guard overlapEnd > overlapStart else { return 0 }

        if start >= range.start, end <= range.end, let duration = entry.duration {
            return max(0, duration)
        }
        return max(0, Int(overlapEnd.timeIntervalSince(overlapStart)))
    }

    private func record(error: Error) {
        connectionState = connectionState(for: error)
        errorMessage = error.localizedDescription
    }

    private func connectionState(for error: Error) -> ConnectionState {
        guard let apiError = error as? ClockodoAPIError else {
            return .offline
        }

        switch apiError {
        case let .httpStatus(status, _):
            switch status {
            case 401:
                return .unauthorized
            case 403:
                return .forbidden
            case 429:
                return .rateLimited
            default:
                return .offline
            }
        case .transport:
            return .offline
        case .invalidExternalApplication, .invalidURL, .invalidResponse, .encoding, .decoding:
            return .unknown
        }
    }
}

private func durationText(seconds: Int) -> String {
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    let remainingSeconds = seconds % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        : String(format: "%02d:%02d", minutes, remainingSeconds)
}
