import Foundation

struct ClockodoCredentials: Sendable, Equatable {
    let email: String
    let apiKey: String

    var externalApplication: String {
        "Clockodo Menubar;\(email)"
    }
}

protocol ClockodoAPIClient: Sendable {
    func getClock() async throws -> ClockResponse
    func getCurrentUser() async throws -> ClockodoUser
    func getCustomers() async throws -> [Customer]
    func getProjects() async throws -> [Project]
    func getServices() async throws -> [Service]
    func getEntries(from: Date, until: Date, userID: Int) async throws -> [ClockodoEntry]
    func startClock(
        customerID: Int,
        serviceID: Int,
        projectID: Int?,
        text: String?
    ) async throws -> ClockResponse
    func stopClock(entryID: Int) async throws -> ClockResponse
}

struct ClockodoEntry: Codable, Identifiable, Sendable {
    let id: Int
    let usersID: Int?
    let customersID: Int?
    let projectsID: Int?
    let servicesID: Int?
    let customersName: String?
    let projectsName: String?
    let servicesName: String?
    let text: String?
    let timeSince: String?
    let timeUntil: String?
    let duration: Int?
    let billable: Int?
    let clocked: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case usersID = "users_id"
        case customersID = "customers_id"
        case projectsID = "projects_id"
        case servicesID = "services_id"
        case customersName = "customers_name"
        case projectsName = "projects_name"
        case servicesName = "services_name"
        case text
        case timeSince = "time_since"
        case timeUntil = "time_until"
        case duration
        case billable
        case clocked
    }

    var displayName: String {
        [customersName, projectsName, servicesName]
            .compactMap { $0 }
            .joined(separator: " / ")
    }

    var customerDisplayName: String {
        customersName ?? "Unknown customer"
    }

    var projectDisplayName: String {
        projectsName ?? "No project"
    }

    var serviceDisplayName: String? {
        servicesName
    }
}

struct ClockodoUser: Codable, Sendable, Equatable {
    let id: Int
    let timezone: String?
}

struct ClockResponse: Codable, Sendable {
    let running: ClockodoEntry?
    let currentTime: String?

    enum CodingKeys: String, CodingKey {
        case running
        case currentTime = "current_time"
    }
}

struct Customer: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let active: Bool?
}

struct Project: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let customersID: Int?
    let active: Bool?
    let completed: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case customersID = "customers_id"
        case active
        case completed
    }
}

struct Service: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let active: Bool?
}

private struct CollectionResponse<Value: Decodable>: Decodable {
    let data: [Value]
    let paging: Paging?
}

private struct EntriesResponse: Decodable {
    let entries: [ClockodoEntry]
    let paging: Paging?
}

private struct UserResponse: Decodable {
    let data: ClockodoUser
}

private struct Paging: Decodable {
    let currentPage: Int
    let countPages: Int

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case countPages = "count_pages"
    }
}

private struct StartClockRequest: Encodable {
    let customersID: Int
    let servicesID: Int
    let projectsID: Int?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case customersID = "customers_id"
        case servicesID = "services_id"
        case projectsID = "projects_id"
        case text
    }
}

enum ClockodoAPIError: LocalizedError {
    case invalidExternalApplication
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)
    case encoding(Error)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidExternalApplication:
            return "The Clockodo application identifier is too long. Use a shorter email address."
        case .invalidURL:
            return "Clockodo returned an invalid API URL."
        case .invalidResponse:
            return "Clockodo returned an unreadable response."
        case let .httpStatus(status, message):
            switch status {
            case 401:
                return "Clockodo rejected the credentials. Check the email address and API key."
            case 403:
                return "Clockodo denied access. Check the API key permissions."
            case 429:
                return "Clockodo rate limit reached. Wait a moment and try again."
            default:
                return "Clockodo returned HTTP \(status): \(message)"
            }
        case let .encoding(error), let .decoding(error):
            return "Clockodo returned data the app could not process: \(error.localizedDescription)"
        case let .transport(error):
            return error.localizedDescription
        }
    }
}

final class ClockodoClient: ClockodoAPIClient, Sendable {
    private let credentials: ClockodoCredentials
    private let session: URLSession
    private let baseURL = URL(string: "https://my.clockodo.com/api")!

    init(credentials: ClockodoCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    func getClock() async throws -> ClockResponse {
        try await send(path: "/v2/clock")
    }

    func getCurrentUser() async throws -> ClockodoUser {
        let response: UserResponse = try await send(path: "/v4/users/me")
        return response.data
    }

    func getCustomers() async throws -> [Customer] {
        let data = try await getAllCollectionPages(
            path: "/v3/customers",
            itemsPerPage: 1000,
            as: Customer.self
        )
        return data.filter { $0.active != false }
    }

    func getProjects() async throws -> [Project] {
        let data = try await getAllCollectionPages(
            path: "/v4/projects",
            itemsPerPage: 5000,
            as: Project.self
        )
        return data.filter { $0.active != false && $0.completed != true }
    }

    func getServices() async throws -> [Service] {
        let data = try await getAllCollectionPages(
            path: "/v4/services",
            itemsPerPage: 1000,
            as: Service.self
        )
        return data.filter { $0.active != false }
    }

    func getEntries(from: Date, until: Date, userID: Int) async throws -> [ClockodoEntry] {
        let entries = try await getAllEntryPages(
            path: "/v2/entries",
            queryItems: [
                URLQueryItem(name: "time_since", value: ClockodoDate.string(from: from)),
                URLQueryItem(name: "time_until", value: ClockodoDate.string(from: until)),
                URLQueryItem(name: "filter[users_id]", value: String(userID)),
            ],
            itemsPerPage: 1000
        )
        return entries.filter { $0.usersID == userID }
    }

    func startClock(
        customerID: Int,
        serviceID: Int,
        projectID: Int?,
        text: String?
    ) async throws -> ClockResponse {
        let request = StartClockRequest(
            customersID: customerID,
            servicesID: serviceID,
            projectsID: projectID,
            text: text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        return try await send(path: "/v2/clock", method: "POST", body: request)
    }

    func stopClock(entryID: Int) async throws -> ClockResponse {
        try await send(path: "/v2/clock/\(entryID)", method: "DELETE")
    }

    private func getAllCollectionPages<Value: Decodable>(
        path: String,
        itemsPerPage: Int,
        as: Value.Type
    ) async throws -> [Value] {
        var values: [Value] = []
        var page = 1

        while true {
            let response: CollectionResponse<Value> = try await send(
                path: path,
                queryItems: [
                    URLQueryItem(name: "items_per_page", value: String(itemsPerPage)),
                    URLQueryItem(name: "page", value: String(page)),
                ]
            )
            values.append(contentsOf: response.data)

            guard let paging = response.paging, paging.currentPage < paging.countPages else {
                return values
            }
            page = paging.currentPage + 1
        }
    }

    private func getAllEntryPages(
        path: String,
        queryItems: [URLQueryItem],
        itemsPerPage: Int
    ) async throws -> [ClockodoEntry] {
        var entries: [ClockodoEntry] = []
        var page = 1

        while true {
            let response: EntriesResponse = try await send(
                path: path,
                queryItems: queryItems + [
                    URLQueryItem(name: "items_per_page", value: String(itemsPerPage)),
                    URLQueryItem(name: "page", value: String(page)),
                ]
            )
            entries.append(contentsOf: response.entries)

            guard let paging = response.paging, paging.currentPage < paging.countPages else {
                return entries
            }
            page = paging.currentPage + 1
        }
    }

    private func send<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Encodable? = nil
    ) async throws -> Response {
        guard credentials.externalApplication.utf8.count <= 50 else {
            throw ClockodoAPIError.invalidExternalApplication
        }

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw ClockodoAPIError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw ClockodoAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(credentials.email, forHTTPHeaderField: "X-ClockodoApiUser")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-ClockodoApiKey")
        request.setValue(credentials.externalApplication, forHTTPHeaderField: "X-Clockodo-External-Application")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            } catch {
                throw ClockodoAPIError.encoding(error)
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClockodoAPIError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClockodoAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ClockodoAPIError.httpStatus(
                httpResponse.statusCode,
                Self.errorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ClockodoAPIError.decoding(error)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            struct Detail: Decodable {
                let message: String?
            }

            let errors: [Detail]?
        }

        guard let response = try? JSONDecoder().decode(ErrorResponse.self, from: data) else { return nil }
        return response.errors?.compactMap(\.message).joined(separator: "; ")
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ value: Encodable) {
        encodeValue = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

enum ClockodoDate {
    private static let formatStyle = Date.ISO8601FormatStyle()

    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return try? formatStyle.parse(value)
    }

    static func string(from value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: value)
    }
}

func elapsedText(since value: String?, now: Date = Date()) -> String {
    guard let start = ClockodoDate.date(from: value) else { return "--:--" }
    let elapsed = max(0, Int(now.timeIntervalSince(start)))
    let hours = elapsed / 3600
    let minutes = (elapsed % 3600) / 60
    let seconds = elapsed % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
        : String(format: "%02d:%02d", minutes, seconds)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
