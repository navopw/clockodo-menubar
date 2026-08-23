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
}

private extension String {
    var date: Date {
        ISO8601DateFormatter().date(from: self)!
    }
}
