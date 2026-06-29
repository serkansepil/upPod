import XCTest
@testable import uppod

final class CervicalLoadTests: XCTestCase {
    func testCurveNodeValues() {
        XCTAssertEqual(CervicalLoad.kg(0), 5, accuracy: 1e-9)
        XCTAssertEqual(CervicalLoad.kg(15), 12, accuracy: 1e-9)
        XCTAssertEqual(CervicalLoad.kg(30), 18, accuracy: 1e-9)
        XCTAssertEqual(CervicalLoad.kg(45), 22, accuracy: 1e-9)
        XCTAssertEqual(CervicalLoad.kg(60), 27, accuracy: 1e-9)
    }

    func testLinearInterpolationMidpoints() {
        XCTAssertEqual(CervicalLoad.kg(7.5), 8.5, accuracy: 1e-9)   // between (0,5) and (15,12)
        XCTAssertEqual(CervicalLoad.kg(22.5), 15, accuracy: 1e-9)   // between (15,12) and (30,18)
    }

    func testClampOutsideRange() {
        XCTAssertEqual(CervicalLoad.kg(-10), 5, accuracy: 1e-9)     // negative → neutral
        XCTAssertEqual(CervicalLoad.kg(90), 27, accuracy: 1e-9)     // beyond last node → max
    }

    func testMonotonicNonDecreasing() {
        var prev = CervicalLoad.kg(0)
        var deg = 0.0
        while deg <= 60 {
            let v = CervicalLoad.kg(deg)
            XCTAssertGreaterThanOrEqual(v, prev - 1e-12)
            prev = v
            deg += 0.5
        }
    }

    func testStrainEndpointsAndMidpoint() {
        XCTAssertEqual(CervicalLoad.strain(0), 0, accuracy: 1e-9)
        XCTAssertEqual(CervicalLoad.strain(60), 1, accuracy: 1e-9)
        XCTAssertEqual(CervicalLoad.strain(30), 13.0 / 22.0, accuracy: 1e-6)   // ≈ 0.5909
    }

    func testSensitivityScalesExcessThenClamps() {
        // strain(15) excess = (12-5)/22 = 7/22 ≈ 0.318; sensitivity 2 doubles it.
        XCTAssertEqual(CervicalLoad.strain(15, sensitivity: 2), 14.0 / 22.0, accuracy: 1e-6)
        XCTAssertEqual(CervicalLoad.strain(60, sensitivity: 5), 1, accuracy: 1e-9)   // clamped to 1
        XCTAssertEqual(CervicalLoad.strain(-5, sensitivity: 2), 0, accuracy: 1e-9)   // negative → 0
    }
}
