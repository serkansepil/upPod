import XCTest
@testable import uppod

final class TimeInStateStoreTests: XCTestCase {
    func testFirstAccumulateOnlySeedsLastSample() {
        let s = TimeInStateStore()
        s.accumulate(state: .good, t: 0)
        XCTAssertEqual(s.seconds[.good], 0)
    }

    func testAccumulatesDtToPreviousState() {
        let s = TimeInStateStore()
        s.accumulate(state: .good, t: 0)
        s.accumulate(state: .good, t: 1)
        XCTAssertEqual(s.seconds[.good] ?? .nan, 1, accuracy: 1e-9)
    }

    func testGapLongerThan5SecondsIsIgnored() {
        let s = TimeInStateStore()
        s.accumulate(state: .good, t: 0)
        s.accumulate(state: .good, t: 10)   // dt = 10 ≥ 5 → dropped
        XCTAssertEqual(s.seconds[.good], 0)
    }

    func testNonIncreasingTimeIsIgnored() {
        let s = TimeInStateStore()
        s.accumulate(state: .good, t: 5)
        s.accumulate(state: .good, t: 5)    // dt = 0 → dropped
        XCTAssertEqual(s.seconds[.good], 0)
    }

    func testPausedPreviousStateConsumesDtButRecordsNothing() {
        let s = TimeInStateStore()
        s.accumulate(state: .paused, t: 0)
        s.accumulate(state: .good, t: 1)    // dt attributed to previous (.paused) → not tracked
        XCTAssertEqual(s.seconds[.good], 0)
        XCTAssertNil(s.seconds[.paused])
    }

    func testSeedAndReset() {
        let s = TimeInStateStore()
        s.seed(good: 10, slight: 5, poor: 2)
        XCTAssertEqual(s.seconds[.good], 10)
        XCTAssertEqual(s.seconds[.slight], 5)
        XCTAssertEqual(s.seconds[.poor], 2)
        s.reset()
        XCTAssertEqual(s.seconds[.good], 0)
        XCTAssertEqual(s.seconds[.slight], 0)
        XCTAssertEqual(s.seconds[.poor], 0)
    }
}

final class DoseAccumulatorTests: XCTestCase {
    func testColdStartReturnsNilUntilOverThreshold() {
        let d = DoseAccumulator()
        d.seed(dose: 0, valid: 60)          // 60 is not > 60
        XCTAssertNil(d.dailyScore)
        d.seed(dose: 0, valid: 61)
        XCTAssertEqual(d.dailyScore, 100)
    }

    func testScoreFormula() {
        let d = DoseAccumulator()
        d.seed(dose: 0, valid: 70)
        XCTAssertEqual(d.dailyScore, 100)   // zero strain the whole time
        d.seed(dose: 70, valid: 70)
        XCTAssertEqual(d.dailyScore, 0)     // max strain the whole time
        d.seed(dose: 35, valid: 70)
        XCTAssertEqual(d.dailyScore, 50)    // half
    }

    func testFirstAddIsNoOp() {
        let d = DoseAccumulator()
        d.add(strain: 0.5, valid: true, t: 0)
        XCTAssertEqual(d.validSeconds, 0)
        XCTAssertEqual(d.doseSeconds, 0)
    }

    func testValidAddIntegrates() {
        let d = DoseAccumulator()
        d.add(strain: 0.5, valid: true, t: 0)   // primes lastT
        d.add(strain: 0.5, valid: true, t: 1)
        XCTAssertEqual(d.validSeconds, 1, accuracy: 1e-9)
        XCTAssertEqual(d.doseSeconds, 0.5, accuracy: 1e-9)
    }

    func testGapsInvalidAndZeroDtAreSkipped() {
        let d = DoseAccumulator()
        d.add(strain: 0.5, valid: true, t: 0)
        d.add(strain: 0.5, valid: true, t: 1)    // counts: valid=1
        d.add(strain: 0.5, valid: true, t: 7)    // dt = 6 ≥ 5 → skipped
        d.add(strain: 0.5, valid: false, t: 8)   // invalid → skipped
        d.add(strain: 0.5, valid: true, t: 8)    // dt = 0 → skipped
        XCTAssertEqual(d.validSeconds, 1, accuracy: 1e-9)
    }

    func testReset() {
        let d = DoseAccumulator()
        d.seed(dose: 5, valid: 100)
        d.reset()
        XCTAssertEqual(d.validSeconds, 0)
        XCTAssertEqual(d.doseSeconds, 0)
        XCTAssertNil(d.dailyScore)
    }
}

final class CalibrationManagerTests: XCTestCase {
    func testFeedBeforeBeginIsIgnored() {
        let c = CalibrationManager()
        c.feed(pitch: 0.1, roll: 0.1, gx: 0, gy: 0, gz: -1, t: 0)
        XCTAssertFalse(c.isCalibrated)
        XCTAssertFalse(c.isCapturing)
    }

    func testAveragesSamplesAndCompletesAfterDuration() {
        let c = CalibrationManager()
        var fired = false
        c.onComplete = { fired = true }
        c.begin(t: 0)
        XCTAssertTrue(c.isCapturing)
        for t in stride(from: 0.0, through: 2.0, by: 0.5) {
            c.feed(pitch: 0.1, roll: 0.2, gx: 0, gy: 0, gz: -1, t: t)
        }
        XCTAssertTrue(c.isCalibrated)
        XCTAssertFalse(c.isCapturing)
        XCTAssertTrue(fired)
        XCTAssertEqual(c.pitch0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(c.roll0, 0.2, accuracy: 1e-9)
        XCTAssertEqual(c.g0z, -1, accuracy: 1e-9)
        XCTAssertNotNil(c.calibratedAt)
    }

    func testRestorePopulatesFields() {
        let c = CalibrationManager()
        let when = Date(timeIntervalSinceReferenceDate: 1000)
        c.restore(CalibrationData(pitch0: 0.3, roll0: -0.1, g0x: 0.1, g0y: 0.2, g0z: -0.97, calibratedAt: when))
        XCTAssertEqual(c.pitch0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(c.roll0, -0.1, accuracy: 1e-9)
        XCTAssertEqual(c.g0x, 0.1, accuracy: 1e-9)
        XCTAssertTrue(c.isCalibrated)
        XCTAssertEqual(c.calibratedAt, when)
    }
}
