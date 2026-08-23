import Foundation
import Testing
@testable import ClockodoMenubar

@Test
func decodesRunningClockResponse() throws {
    let data = Data(
        """
        {
          "running": {
            "id": 123,
            "customers_id": 10,
            "projects_id": 20,
            "services_id": 30,
            "customers_name": "Acme",
            "projects_name": "Website",
            "services_name": "Development",
            "text": "Implement menubar app",
            "time_since": "2026-08-23T10:00:00Z",
            "time_until": null,
            "duration": null,
            "billable": 1,
            "clocked": true
          },
          "current_time": "2026-08-23T10:30:00Z"
        }
        """.utf8
    )

    let response = try JSONDecoder().decode(ClockResponse.self, from: data)

    #expect(response.running?.id == 123)
    #expect(response.running?.displayName == "Acme / Website / Development")
    #expect(response.running?.customerDisplayName == "Acme")
    #expect(response.running?.projectDisplayName == "Website")
    #expect(response.running?.serviceDisplayName == "Development")
    #expect(response.running?.timeUntil == nil)
    #expect(response.currentTime == "2026-08-23T10:30:00Z")
}

@Test
func runningEntryUsesReadableFallbacks() throws {
    let data = Data("{\"id\": 123}".utf8)
    let entry = try JSONDecoder().decode(ClockodoEntry.self, from: data)

    #expect(entry.customerDisplayName == "Unknown customer")
    #expect(entry.projectDisplayName == "No project")
    #expect(entry.serviceDisplayName == nil)
}

@Test
func formatsElapsedTime() {
    #expect(elapsedText(since: "2026-08-23T10:00:00Z", now: "2026-08-23T10:02:07Z".date) == "02:07")
    #expect(elapsedText(since: "2026-08-23T10:00:00Z", now: "2026-08-23T12:02:07Z".date) == "2:02:07")
    #expect(elapsedText(since: nil) == "--:--")
    #expect(elapsedText(since: "2026-08-23T10:01:00Z", now: "2026-08-23T10:00:00Z".date) == "00:00")
}

@Suite(.serialized)
struct ClockodoClientTests {
    @Test
    func sendsClockRequestWithHeadersAndTrimmedNote() async throws {
        let recorder = RequestRecorder()
        let client = makeClient { request in
            recorder.request = request
            return Self.successResponse
        }

        _ = try await client.startClock(
            customerID: 10,
            serviceID: 30,
            projectID: 20,
            text: "  Implement feature  "
        )

        let request = try #require(recorder.request)
        #expect(request.url?.path == "/api/v2/clock")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-ClockodoApiUser") == "person@example.com")
        #expect(request.value(forHTTPHeaderField: "X-ClockodoApiKey") == "secret")
        #expect(request.value(forHTTPHeaderField: "X-Clockodo-External-Application") == "Clockodo Menubar;person@example.com")

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["customers_id"] as? Int == 10)
        #expect(json["services_id"] as? Int == 30)
        #expect(json["projects_id"] as? Int == 20)
        #expect(json["text"] as? String == "Implement feature")
    }

    @Test
    func filtersInactiveAndCompletedCatalogEntries() async throws {
        let client = makeClient { request in
            let body: String
            switch request.url?.path {
            case "/api/v3/customers":
                body = #"{"data":[{"id":1,"name":"Active","active":true},{"id":2,"name":"Inactive","active":false}]}"#
            case "/api/v4/projects":
                body = #"{"data":[{"id":1,"name":"Open","customers_id":1,"active":true,"completed":false},{"id":2,"name":"Done","customers_id":1,"active":true,"completed":true},{"id":3,"name":"Inactive","customers_id":1,"active":false,"completed":false}]}"#
            default:
                body = #"{"data":[{"id":1,"name":"Service","active":true}]}"#
            }
            return (Self.response(status: 200), Data(body.utf8))
        }

        #expect(try await client.getCustomers().map(\.id) == [1])
        #expect(try await client.getProjects().map(\.id) == [1])
        #expect(try await client.getServices().map(\.id) == [1])
    }

    @Test
    func doesNotExposeUnexpectedErrorBodies() async throws {
        let client = makeClient { _ in
            (Self.response(status: 500), Data("private server details".utf8))
        }

        do {
            _ = try await client.getClock()
            Issue.record("Expected getClock to fail")
        } catch let error as ClockodoAPIError {
            let message = error.localizedDescription
            #expect(!message.contains("private server details"))
            #expect(message.contains("internal server error"))
        }
    }

    @Test
    func reportsDecodingFailuresSeparately() async throws {
        let client = makeClient { _ in
            (Self.response(status: 200), Data("{}".utf8))
        }

        do {
            _ = try await client.getCustomers()
            Issue.record("Expected getCustomers to fail")
        } catch let error as ClockodoAPIError {
            guard case .decoding = error else {
                Issue.record("Expected a decoding error")
                return
            }
        }
    }

    @Test
    func rejectsAnOverlongExternalApplicationBeforeNetworking() async throws {
        let client = ClockodoClient(
            credentials: ClockodoCredentials(email: String(repeating: "a", count: 40), apiKey: "secret"),
            session: URLSession(configuration: .ephemeral)
        )

        do {
            _ = try await client.getClock()
            Issue.record("Expected an invalid external application error")
        } catch let error as ClockodoAPIError {
            guard case .invalidExternalApplication = error else {
                Issue.record("Expected invalidExternalApplication")
                return
            }
        }
    }

    private static let successResponse = (
        response(status: 200),
        Data(#"{"running":null,"current_time":"2026-08-23T10:00:00Z"}"#.utf8)
    )

    private static func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://my.clockodo.com/api")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

@Test
@MainActor
func clearsAProjectWhenTheCustomerChanges() async {
    let store = TestCredentialStore(email: "person@example.com", apiKey: "secret")
    let client = TestClockodoClient()
    let suiteName = "ClockodoMenubarTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let model = AppModel(
        keychain: store,
        clientFactory: { _ in client },
        userDefaults: defaults
    )
    await model.bootstrap()

    model.selectedProjectID = 10
    model.selectedCustomerID = 2
    model.customerSelectionChanged()

    #expect(model.selectedProjectID == nil)
}

private func makeClient(
    handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
) -> ClockodoClient {
    MockURLProtocol.setHandler(handler)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return ClockodoClient(
        credentials: ClockodoCredentials(email: "person@example.com", apiKey: "secret"),
        session: URLSession(configuration: configuration)
    )
}

private final class RequestRecorder: @unchecked Sendable {
    var request: URLRequest?
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?

    static func setHandler(_ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            let bufferSize = 4_096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: bufferSize)
                guard count > 0 else { break }
                body.append(buffer, count: count)
            }
            request.httpBody = body
        }

        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class TestCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [String: String]

    init(email: String? = nil, apiKey: String? = nil) {
        values = [:]
        if let email { values["email"] = email }
        if let apiKey { values["apiKey"] = apiKey }
    }

    func read(account: String) throws -> String? { values[account] }

    func save(_ value: String, account: String) throws { values[account] = value }

    func delete(account: String) throws { values.removeValue(forKey: account) }
}

private final class TestClockodoClient: ClockodoAPIClient, @unchecked Sendable {
    func getClock() async throws -> ClockResponse {
        ClockResponse(running: nil, currentTime: "2026-08-23T10:00:00Z")
    }

    func getCustomers() async throws -> [Customer] {
        [Customer(id: 1, name: "Customer A", active: true), Customer(id: 2, name: "Customer B", active: true)]
    }

    func getProjects() async throws -> [Project] {
        [Project(id: 10, name: "Project A", customersID: 1, active: true, completed: false)]
    }

    func getServices() async throws -> [Service] {
        [Service(id: 20, name: "Service", active: true)]
    }

    func startClock(customerID: Int, serviceID: Int, projectID: Int?, text: String?) async throws -> ClockResponse {
        ClockResponse(running: nil, currentTime: "2026-08-23T10:00:00Z")
    }

    func stopClock(entryID: Int) async throws -> ClockResponse {
        ClockResponse(running: nil, currentTime: "2026-08-23T10:00:00Z")
    }
}

private extension String {
    var date: Date {
        ClockodoDate.date(from: self)!
    }
}
