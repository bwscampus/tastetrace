import XCTest
@testable import TasteTraceCore
import TasteTraceAPI

final class DateMathTests: XCTestCase {
    let math = DateMath(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    func testDayStringUsesTheGivenZone() {
        let instant = Date(timeIntervalSince1970: 1_789_680_983) // 2026-09-17 21:36 UTC
        XCTAssertEqual(math.dayString(instant), "2026-09-17")
        XCTAssertEqual(DateMath(timeZone: TimeZone(identifier: "Asia/Tokyo")!).dayString(instant), "2026-09-18")
    }

    func testWeekStartsOnMonday() {
        let thursday = math.date(fromDay: "2026-09-17")!
        let week = math.week(containing: thursday).map(math.dayString)
        XCTAssertEqual(week.first, "2026-09-14")
        XCTAssertEqual(week.last, "2026-09-20")
        XCTAssertEqual(math.trailingWeek(endingOn: thursday).map(math.dayString).first, "2026-09-11")
    }

    func testCombineDayAndTime() {
        let day = math.date(fromDay: "2026-09-11")!
        let time = math.calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: 12, minute: 45))!
        XCTAssertEqual(math.dayString(math.combine(day: day, time: time)), "2026-09-11")
        XCTAssertEqual(math.calendar.component(.hour, from: math.combine(day: day, time: time)), 12)
    }
}

final class SeverityMappingTests: XCTestCase {
    func testRoundTrip() {
        for severity in ["Mild", "Moderate", "Severe"] {
            XCTAssertEqual(SeverityMapping.severity(forIntensity: SeverityMapping.intensity(forSeverity: severity)), severity)
        }
        XCTAssertEqual(SeverityMapping.discomfortScore(intensity: 3), 6)
    }
}

final class JSONFileStoreTests: XCTestCase {
    func testSaveLoadClear() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = JSONFileStore<Settings>(name: "settings", directory: dir)
        XCTAssertNil(store.load())
        try store.save(Settings(timezone: "America/Los_Angeles"))
        XCTAssertEqual(store.load()?.timezone, "America/Los_Angeles")
        store.clear()
        XCTAssertNil(store.load())
    }
}
