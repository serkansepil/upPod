import Foundation

/// Today's per-state durations (in memory; persistence = next iteration, GRDB).
final class TimeInStateStore {
    private(set) var seconds: [PostureState: Double] = [.good: 0, .slight: 0, .poor: 0]
    private var lastT: TimeInterval?
    private var lastState: PostureState?

    func accumulate(state: PostureState, t: TimeInterval) {
        defer { lastT = t; lastState = state }
        guard let lt = lastT, let ls = lastState else { return }
        let dt = t - lt
        guard dt > 0, dt < 5 else { return }
        if ls == .good || ls == .slight || ls == .poor {
            seconds[ls, default: 0] += dt
        }
    }

    func reset() { seconds = [.good: 0, .slight: 0, .poor: 0]; lastT = nil; lastState = nil }

    func seed(good: Double, slight: Double, poor: Double) {
        seconds[.good] = good; seconds[.slight] = slight; seconds[.poor] = poor
    }
}

/// DOSE model (plan §4.2): the score comes not from the instantaneous angle but from the time integral of strain.
/// 2 hours at 10° is worse than 30 sec at 30° — this captures that.
final class DoseAccumulator {
    private(set) var validSeconds = 0.0
    private(set) var doseSeconds = 0.0   // ∫ strain dt  ("strain-seconds")
    private var lastT: TimeInterval?

    func add(strain: Double, valid: Bool, t: TimeInterval) {
        defer { lastT = t }
        guard let lt = lastT else { return }
        let dt = t - lt
        guard dt > 0, dt < 5, valid else { return }
        validSeconds += dt
        doseSeconds += strain * dt
    }

    /// Daily score: the inverse of average strain. strain=0 the whole time → 100; strain=1 → 0.
    var dailyScore: Int? { Self.score(doseSeconds: doseSeconds, validSeconds: validSeconds) }

    /// Single source of truth for the dose→score formula (also used for stored historical days).
    /// Returns nil until past the cold-start window (> 60 valid seconds).
    static func score(doseSeconds: Double, validSeconds: Double) -> Int? {
        guard validSeconds > 60 else { return nil }
        return Int((100 * (1 - doseSeconds / validSeconds)).rounded())
    }

    func reset() { validSeconds = 0; doseSeconds = 0; lastT = nil }

    func seed(dose: Double, valid: Double) { doseSeconds = dose; validSeconds = valid }
}

/// Manual calibration: takes the user's actual upright sitting as baseline (~2 sec average, gravity included). Plan §3.2.
final class CalibrationManager {
    var duration: Double = 2.0
    private(set) var pitch0 = 0.0, roll0 = 0.0
    private(set) var g0x = 0.0, g0y = 0.0, g0z = -1.0
    private(set) var calibratedAt: Date?

    private var capturing = false
    private var sp = 0.0, sr = 0.0, sgx = 0.0, sgy = 0.0, sgz = 0.0, n = 0
    private var startT: TimeInterval = 0
    var onComplete: (() -> Void)?

    var isCalibrated: Bool { calibratedAt != nil }
    var isCapturing: Bool { capturing }

    func begin(t: TimeInterval) {
        capturing = true; sp = 0; sr = 0; sgx = 0; sgy = 0; sgz = 0; n = 0; startT = t
    }

    /// Restore the saved calibration from disk (no need to recalibrate).
    func restore(_ d: CalibrationData) {
        pitch0 = d.pitch0; roll0 = d.roll0
        g0x = d.g0x; g0y = d.g0y; g0z = d.g0z
        calibratedAt = d.calibratedAt
    }

    func feed(pitch: Double, roll: Double, gx: Double, gy: Double, gz: Double, t: TimeInterval) {
        guard capturing else { return }
        sp += pitch; sr += roll; sgx += gx; sgy += gy; sgz += gz; n += 1
        if t - startT >= duration && n > 0 {
            let d = Double(n)
            pitch0 = sp / d; roll0 = sr / d
            g0x = sgx / d; g0y = sgy / d; g0z = sgz / d
            calibratedAt = Date()
            capturing = false
            onComplete?()
        }
    }
}
