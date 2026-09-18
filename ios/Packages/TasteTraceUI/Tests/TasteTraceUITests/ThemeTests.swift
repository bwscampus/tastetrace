import XCTest
import SwiftUI
@testable import TasteTraceUI

final class ThemeTests: XCTestCase {
    func testHexColorsResolve() {
        XCTAssertNotNil(TTColor.primary.cgColor ?? Color(hex: 0x2563EB).cgColor)
        XCTAssertEqual(TTRadius.card, 20)
    }
}
