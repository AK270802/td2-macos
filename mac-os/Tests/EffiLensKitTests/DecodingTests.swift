import XCTest
@testable import EffiLensKit

final class DecodingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testLeaveApplicationDecodesDecimalStringsAndMicrosecondDates() throws {
        let app = try JSONCoding.makeDecoder().decode(LeaveApplication.self, from: fixture("leave_application"))
        XCTAssertEqual(app.durationDays.value, Decimal(string: "1.5"))
        XCTAssertEqual(app.startDate, CalendarDate(year: 2026, month: 11, day: 10))
        XCTAssertEqual(app.statusValue, .pendingManager)
        XCTAssertTrue(app.isWithdrawable)
        // Offset-aware and naive datetimes must resolve to the same instant (naive = UTC).
        XCTAssertEqual(app.createdAt.timeIntervalSince1970, app.updatedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testLeaveBalanceUsesServerComputedRemaining() throws {
        let balance = try JSONCoding.makeDecoder().decode(LeaveBalance.self, from: fixture("leave_balance"))
        XCTAssertEqual(balance.paidRemaining?.doubleValue, 13.5)
        XCTAssertEqual(balance.compOffRemaining?.doubleValue, 1)
    }

    func testAgentStateEnvelope() throws {
        let envelope = try JSONCoding.makeDecoder().decode(AgentResponse<AgentTimerState>.self, from: fixture("agent_state"))
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.data?.state, .running)
        XCTAssertEqual(envelope.data?.elapsedSecs, 3725)
        XCTAssertEqual(envelope.data?.task?.taskName, "Design review")
        XCTAssertEqual(envelope.data?.inMeeting, true)
    }

    func testFlexibleDecimalAcceptsNumbers() throws {
        let value = try JSONCoding.makeDecoder().decode([FlexibleDecimal].self, from: Data("[2.5, \"3.25\"]".utf8))
        XCTAssertEqual(value.map(\.doubleValue), [2.5, 3.25])
    }

    func testCalendarDateRejectsGarbage() {
        XCTAssertNil(CalendarDate(iso: "2026-13-01"))
        XCTAssertNil(CalendarDate(iso: "not-a-date"))
        XCTAssertEqual(CalendarDate(iso: "2026-02-03")?.description, "2026-02-03")
    }

    func testEncoderUsesSnakeCase() throws {
        let body = LeaveApplicationCreate(startDate: CalendarDate(year: 2026, month: 1, day: 2),
                                          endDate: CalendarDate(year: 2026, month: 1, day: 2),
                                          halfDay: true, reason: "x")
        let json = try XCTUnwrap(String(data: JSONCoding.makeEncoder().encode(body), encoding: .utf8))
        XCTAssertTrue(json.contains("\"half_day\":true"))
        XCTAssertTrue(json.contains("\"start_date\":\"2026-01-02\""))
        XCTAssertFalse(json.contains("user_id"), "nil user_id must be omitted so the server applies the caller's id")
    }

    func testAgentRecentEventIgnoresPayloadContent() throws {
        let json = Data("""
        [{"event_uuid":"6f1c1d2e-0000-4000-8000-000000000001","user_id":"6f1c1d2e-0000-4000-8000-000000000002",
          "tenant_id":"6f1c1d2e-0000-4000-8000-000000000003","event_type":"idle","ts":1793000000,"duration_sec":240,
          "payload":{"app_name":"Secret App","window_title":"Private"}}]
        """.utf8)
        let events = try JSONCoding.makeDecoder().decode([AgentRecentEvent].self, from: json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].eventType, "idle")
        XCTAssertEqual(events[0].durationSec, 240)
        XCTAssertEqual(events[0].date, Date(timeIntervalSince1970: 1_793_000_000))
    }
}
