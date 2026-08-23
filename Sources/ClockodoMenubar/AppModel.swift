import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var credentials: ClockodoCredentials?
    @Published private(set) var runningEntry: ClockodoEntry?
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var projects: [Project] = []
    @Published private(set) var services: [Service] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPerformingAction = false
    @Published private(set) var lastUpdated: Date?
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
            var lastClockRefresh = Date()

            while !Task.isCancelled {
                if isRunning {
                    now = Date().addingTimeInterval(clockOffset)
                }
                if !isPerformingAction && Date().timeIntervalSince(lastClockRefresh) >= 60 {
                    await refreshClock()
                    lastClockRefresh = Date()
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
            errorMessage = nil
        } catch {
            guard generation == credentialsGeneration,
                  requestVersion == stateVersion,
                  !isPerformingAction else { return }
            errorMessage = error.localizedDescription
        }
    }

    func bootstrap() async {
        guard let client else { return }
        guard !isBootstrapping else {
            bootstrapRequested = true
            return
        }

        isLoading = true
        isBootstrapping = true
        let generation = credentialsGeneration

        async let clockResponse: ClockResponse? = try? client.getClock()
        async let customerResponse: [Customer]? = customers.isEmpty ? try? client.getCustomers() : customers
        async let projectResponse: [Project]? = projects.isEmpty ? try? client.getProjects() : projects
        async let serviceResponse: [Service]? = services.isEmpty ? try? client.getServices() : services

        let loadedClock = await clockResponse
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
                errorMessage = nil
            } else {
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
            errorMessage = nil
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

        do {
            try keychain.save(email, account: "email")
            try keychain.save(apiKey, account: "apiKey")
            let newCredentials = ClockodoCredentials(email: email, apiKey: apiKey)
            credentials = newCredentials
            client = clientFactory(newCredentials)
            credentialsGeneration += 1
            stateVersion += 1
            runningEntry = nil
            customers = []
            projects = []
            services = []
            clockOffset = 0
            now = Date()
            errorMessage = nil
            await bootstrap()
        } catch {
            errorMessage = error.localizedDescription
        }
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
}
