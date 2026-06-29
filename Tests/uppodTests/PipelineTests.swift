import XCTest
@testable import uppod

final class ScalarEMATests: XCTestCase {
    func testFirstUpdateReturnsInputUnchanged() {
        let ema = ScalarEMA(tau: 0.4)
        XCTAssertEqual(ema.update(3.0, t: 0), 3.0, accuracy: 1e-12)
    }

    func testStepResponseAtOneTau() {
        // After one tau, an EMA jumps ~63.2% of the way to the new value.
        let ema = ScalarEMA(tau: 0.4)
        _ = ema.update(0, t: 0)
        let v = ema.update(1, t: 0.4)
        XCTAssertEqual(v, 1 - exp(-1.0), accuracy: 1e-3)   // ≈ 0.6321
    }

    func testConvergesMonotonicallyToConstant() {
        let ema = ScalarEMA(tau: 0.4)
        _ = ema.update(0, t: 0)
        var last = 0.0
        var t = 0.1
        for _ in 0..<200 {
            let v = ema.update(1, t: t)
            XCTAssertGreaterThanOrEqual(v, last)   // monotonic non-decreasing
            XCTAssertLessThanOrEqual(v, 1.0 + 1e-9) // never overshoots
            last = v
            t += 0.1
        }
        XCTAssertEqual(last, 1.0, accuracy: 1e-2)
    }

    func testResetMakesNextSampleBehaveAsFirst() {
        let ema = ScalarEMA(tau: 0.4)
        _ = ema.update(0, t: 0)
        _ = ema.update(1, t: 0.4)
        ema.reset()
        XCTAssertEqual(ema.update(5, t: 10), 5.0, accuracy: 1e-12)
    }

    func testZeroDtIsClampedAndFinite() {
        let ema = ScalarEMA(tau: 0.4)
        _ = ema.update(0, t: 0)
        let v = ema.update(1, t: 0)   // dt == 0 → clamped to 1e-3, no NaN / div-by-zero
        XCTAssertTrue(v.isFinite)
        XCTAssertGreaterThanOrEqual(v, 0)
    }
}

final class FlexionEstimatorTests: XCTestCase {
    /// Gravity rotated by angle θ (radians) about the X axis away from the baseline (0,0,-1).
    private func gravity(tiltedBy theta: Double) -> (Double, Double, Double) {
        (0, sin(theta), -cos(theta))
    }

    func testZeroAtBaseline() {
        let est = FlexionEstimator()
        est.setBaseline(pitch: 0, roll: 0, gx: 0, gy: 0, gz: -1)
        let r = est.estimate(pitch: 0, roll: 0, gx: 0, gy: 0, gz: -1)
        XCTAssertEqual(r.flex, 0, accuracy: 1e-6)
        XCTAssertEqual(r.roll, 0, accuracy: 1e-6)
    }

    func testForwardFlexionIsPositive() {
        let est = FlexionEstimator()   // default flexionSign = -1
        est.setBaseline(pitch: 0, roll: 0, gx: 0, gy: 0, gz: -1)
        let g = gravity(tiltedBy: 0.2)
        // pitch < p0 with a forward-tilted gravity ⇒ positive flexion.
        let r = est.estimate(pitch: -0.2, roll: 0, gx: g.0, gy: g.1, gz: g.2)
        XCTAssertGreaterThan(r.flex, 0)
        XCTAssertEqual(r.flex, 0.2 * DEG, accuracy: 0.5)
    }

    func testMagnitudeIsDriftFreeRegardlessOfAttitudeDeltas() {
        // The combined magnitude must equal the gravity tilt angle for ANY pitch/roll deltas.
        let est = FlexionEstimator()
        est.setBaseline(pitch: 0, roll: 0, gx: 0, gy: 0, gz: -1)
        let theta = 0.3
        let g = gravity(tiltedBy: theta)
        for (p, rl) in [(0.1, 0.05), (-0.4, 0.6), (0.9, -0.2)] {
            let r = est.estimate(pitch: p, roll: rl, gx: g.0, gy: g.1, gz: g.2)
            let mag = (r.flex * r.flex + r.roll * r.roll).squareRoot()
            XCTAssertEqual(mag, theta * DEG, accuracy: 1e-3)
        }
    }

    func testPureSideTiltGoesToRollNotFlexion() {
        let est = FlexionEstimator()
        est.setBaseline(pitch: 0, roll: 0, gx: 0, gy: 0, gz: -1)
        let g = gravity(tiltedBy: 0.25)
        // No pitch delta, only roll delta ⇒ the tilt is attributed to roll.
        let r = est.estimate(pitch: 0, roll: 0.3, gx: g.0, gy: g.1, gz: g.2)
        XCTAssertEqual(r.flex, 0, accuracy: 1e-6)
        XCTAssertGreaterThan(abs(r.roll), 1.0)
    }
}

final class MotionGateTests: XCTestCase {
    func testCalmIsNotMoving() {
        let gate = MotionGate()
        XCTAssertFalse(gate.update(accelMag: 0.01, rotMag: 0.1, t: 0))
    }

    func testHighRotationTripsImmediately() {
        let gate = MotionGate()
        XCTAssertTrue(gate.update(accelMag: 0.0, rotMag: 2.0, t: 0))   // rotMag > 1.5
    }

    func testSustainedAccelerationTripsAfterRamp() {
        let gate = MotionGate()
        XCTAssertFalse(gate.update(accelMag: 0.2, rotMag: 0, t: 0))   // EMA still ramping
        var moving = false
        var t = 0.1
        for _ in 0..<30 {
            moving = gate.update(accelMag: 0.2, rotMag: 0, t: t)
            t += 0.1
        }
        XCTAssertTrue(moving)   // EMA RMS now exceeds 0.10 g
    }
}

final class PostureClassifierTests: XCTestCase {
    func testGoodToSlightToPoorByStrain() {
        let c = PostureClassifier()
        XCTAssertEqual(c.classify(strain: 0.10, rollDeg: 0), .good)
        XCTAssertEqual(c.classify(strain: 0.25, rollDeg: 0), .slight)   // > goodMax 0.20
        XCTAssertEqual(c.classify(strain: 0.60, rollDeg: 0), .poor)     // > slightMax 0.50
    }

    func testRollAloneTriggersSlight() {
        let c = PostureClassifier()
        XCTAssertEqual(c.classify(strain: 0.05, rollDeg: 20), .slight)  // roll > rollWarnDeg 15
    }

    func testPoorHysteresis() {
        let c = PostureClassifier()
        XCTAssertEqual(c.classify(strain: 0.60, rollDeg: 0), .poor)
        XCTAssertEqual(c.classify(strain: 0.48, rollDeg: 0), .poor)     // > slightMax - hyst (0.45) → sticky
        XCTAssertEqual(c.classify(strain: 0.44, rollDeg: 0), .slight)   // ≤ 0.45 → releases
    }

    func testSlightToGoodNeedsLowStrainAndLowRoll() {
        let c = PostureClassifier()
        XCTAssertEqual(c.classify(strain: 0.25, rollDeg: 0), .slight)
        XCTAssertEqual(c.classify(strain: 0.10, rollDeg: 14), .slight)  // roll 14 > rollGoodDeg 12 → stays
        XCTAssertEqual(c.classify(strain: 0.10, rollDeg: 5), .good)     // both low → good
    }

    func testResetReturnsToGood() {
        let c = PostureClassifier()
        _ = c.classify(strain: 0.60, rollDeg: 0)
        c.reset()
        XCTAssertEqual(c.current, .good)
    }
}

final class PostureStateMachineTests: XCTestCase {
    func testFirstUpdatePrimesImmediately() {
        let m = PostureStateMachine()
        XCTAssertEqual(m.update(candidate: .good, t: 0), .good)
    }

    func testCandidateCommitsOnlyAfterDwell() {
        let m = PostureStateMachine()
        _ = m.update(candidate: .good, t: 0)
        XCTAssertEqual(m.update(candidate: .poor, t: 0.1), .good)   // candidate registered, dwell not met
        XCTAssertEqual(m.update(candidate: .poor, t: 0.5), .good)   // 0.4s < 0.7s
        XCTAssertEqual(m.update(candidate: .poor, t: 0.9), .poor)   // 0.8s ≥ 0.7s → commit
    }

    func testFlickerIsAbsorbed() {
        let m = PostureStateMachine()
        _ = m.update(candidate: .good, t: 0)
        _ = m.update(candidate: .poor, t: 0.1)
        XCTAssertEqual(m.update(candidate: .good, t: 0.4), .good)   // flips back before dwell → never commits poor
        XCTAssertEqual(m.update(candidate: .good, t: 2.0), .good)
    }

    func testNoteGapRePrimes() {
        let m = PostureStateMachine()
        _ = m.update(candidate: .good, t: 0)
        m.noteGap()
        XCTAssertEqual(m.update(candidate: .poor, t: 10), .poor)   // re-primed → immediate commit, no dwell
    }
}
