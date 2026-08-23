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

    private let keychain = KeychainStore()
    private var client: ClockodoClient?
    private var backgroundTask: Task<Void, Never>?

    init() {
        loadStoredCredentials()
        selectedCustomerID = UserDefaults.standard.object(forKey: "selectedCustomerID") as? Int
        selectedProjectID = UserDefaults.standard.object(forKey: "selectedProjectID") as? Int
        selectedServiceID = UserDefaults.standard.object(forKey: "selectedServiceID") as? Int
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
        guard let runningEntry else { return "Running" }
        return runningEntry.displayName.isEmpty ? "Running timer" : runningEntry.displayName
    }

    func startBackgroundUpdates() {
        guard backgroundTask == nil else { return }

        backgroundTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await bootstrap()
            var lastClockRefresh = Date.distantPast

            while !Task.isCancelled {
                now = Date()
                if Date().timeIntervalSince(lastClockRefresh) >= 60 {
                    await refreshClock()
                    lastClockRefresh = Date()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func refreshClock() async {
        guard let client else { return }
        do {
            runningEntry = try await client.getClock().running
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func bootstrap() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let clockResponse = client.getClock()
            async let customerResponse = customers.isEmpty ? client.getCustomers() : customers
            async let projectResponse = projects.isEmpty ? client.getProjects() : projects
            async let serviceResponse = services.isEmpty ? client.getServices() : services

            runningEntry = try await clockResponse.running
            customers = try await customerResponse
            projects = try await projectResponse
            services = try await serviceResponse
            lastUpdated = Date()
            errorMessage = nil
            selectFirstAvailableValuesIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startClock() async {
        guard let client, let selectedCustomerID, let selectedServiceID else {
            errorMessage = "Choose a customer and service before starting the timer."
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let response = try await client.startClock(
                customerID: selectedCustomerID,
                serviceID: selectedServiceID,
                projectID: selectedProjectID,
                text: note
            )
            runningEntry = response.running
            note = ""
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopClock() async {
        guard let client, let entryID = runningEntry?.id else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let response = try await client.stopClock(entryID: entryID)
            runningEntry = response.running
            errorMessage = nil
            lastUpdated = Date()
        } catch {
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
            credentials = ClockodoCredentials(email: email, apiKey: apiKey)
            client = ClockodoClient(credentials: credentials!)
            runningEntry = nil
            customers = []
            projects = []
            services = []
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
            credentials = nil
            client = nil
            runningEntry = nil
            customers = []
            projects = []
            services = []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func persistSelections() {
        UserDefaults.standard.set(selectedCustomerID, forKey: "selectedCustomerID")
        UserDefaults.standard.set(selectedProjectID, forKey: "selectedProjectID")
        UserDefaults.standard.set(selectedServiceID, forKey: "selectedServiceID")
    }

    private func loadStoredCredentials() {
        do {
            guard let email = try keychain.read(account: "email"),
                  let apiKey = try keychain.read(account: "apiKey") else { return }
            credentials = ClockodoCredentials(email: email, apiKey: apiKey)
            client = ClockodoClient(credentials: credentials!)
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
        if let selectedCustomerID,
           let selectedProjectID,
           projects.contains(where: { $0.id == selectedProjectID && $0.customersID == selectedCustomerID }) == false {
            self.selectedProjectID = nil
        }
        persistSelections()
    }
}
