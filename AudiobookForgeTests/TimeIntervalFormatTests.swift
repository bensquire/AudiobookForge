import XCTest
@testable import AudiobookForge

final class TimeIntervalFormatTests: XCTestCase {
    func test_positional_underAnHour_omitsHourComponent() {
        // Arrange
        let t: TimeInterval = 5 * 60 + 7 // 5:07

        // Act
        let formatted = t.positional

        // Assert
        XCTAssertEqual(formatted, "5:07")
    }

    func test_positional_overAnHour_includesHourComponent() {
        // Arrange — 1h 23m 45s
        let t: TimeInterval = 3600 + 23 * 60 + 45

        // Act
        let formatted = t.positional

        // Assert
        XCTAssertEqual(formatted, "1:23:45")
    }

    func test_positional_zero() {
        // Arrange / Act / Assert
        XCTAssertEqual(TimeInterval(0).positional, "0:00")
    }

    func test_abbreviated_underAnHour_minutesOnly() {
        // Arrange
        let t: TimeInterval = 17 * 60 + 30

        // Act
        let formatted = t.abbreviated

        // Assert
        XCTAssertEqual(formatted, "17m")
    }

    func test_abbreviated_overAnHour_hoursAndMinutes() {
        // Arrange — 2h 5m
        let t: TimeInterval = 2 * 3600 + 5 * 60

        // Act
        let formatted = t.abbreviated

        // Assert
        XCTAssertEqual(formatted, "2h 5m")
    }

    func test_abbreviated_secondsAlone_roundDownToZeroMinutes() {
        // Arrange — 30 seconds, no full minute
        let t: TimeInterval = 30

        // Act
        let formatted = t.abbreviated

        // Assert
        XCTAssertEqual(formatted, "0m")
    }
}
