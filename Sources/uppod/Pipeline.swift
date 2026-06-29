import Foundation

let DEG = 180.0 / Double.pi

/// Displayed posture states (3+1) — plan §3.3.
enum PostureState: String {
    case good, slight, poor, paused
}

/// Scalar EMA smoother (tau-based → independent of effective Hz).
final class ScalarEMA {
    var tau: Double
    private var v: Double?
    private var lastT: TimeInterval?
    init(tau: Double = 0.4) { self.tau = tau }
    func reset() { v = nil; lastT = nil }
    func update(_ x: Double, t: TimeInterval) -> Double {
        defer { lastT = t }
        guard let pv = v, let lt = lastT else { v = x; return x }
        let a = 1 - exp(-max(1e-3, t - lt) / tau)
        let nv = pv + a * (x - pv); v = nv; return nv
    }
}

/// DRIFT-FREE absolute flexion magnitude from the gravity vector + direction/roll separation from attitude (fusion).
/// Magnitude from gravity (absolute, no drift); sign and the flexion/roll share from attitude pitch/roll
/// (these drift only a little individually). No axis-convention GUESSING needed.
final class FlexionEstimator {
    var flexionSign = -1.0   // Phase 0b MEASURED: on AirPods, looking forward/down DECREASES raw pitch

    private var p0 = 0.0, r0 = 0.0
    private var g0x = 0.0, g0y = 0.0, g0z = -1.0

    func setBaseline(pitch: Double, roll: Double, gx: Double, gy: Double, gz: Double) {
        p0 = pitch; r0 = roll
        let n = max(1e-9, (gx * gx + gy * gy + gz * gz).squareRoot())
        g0x = gx / n; g0y = gy / n; g0z = gz / n
    }

    /// (signed flexion°, signed roll°). flexion>0 = forward/down.
    func estimate(pitch: Double, roll: Double, gx: Double, gy: Double, gz: Double) -> (flex: Double, roll: Double) {
        let n = max(1e-9, (gx * gx + gy * gy + gz * gz).squareRoot())
        let dot = max(-1, min(1, (gx * g0x + gy * g0y + gz * g0z) / n))
        let totalTilt = acos(dot) * DEG                      // drift-free absolute magnitude
        let dPitch = (pitch - p0) * flexionSign * DEG        // direction + flexion share
        let dRoll = (roll - r0) * DEG
        let mag = max(1e-6, (dPitch * dPitch + dRoll * dRoll).squareRoot())
        return (totalTilt * dPitch / mag, totalTilt * dRoll / mag)
    }
}

/// Motion gate — walking/running/vigorous movement halts classification (plan §3.5).
final class MotionGate {
    var accelThreshold: Double = 0.10   // g RMS
    var rotThreshold: Double = 1.5      // rad/s
    var tau: Double = 1.0
    private var emaAccelSq: Double = 0
    private var lastT: TimeInterval?

    func update(accelMag: Double, rotMag: Double, t: TimeInterval) -> Bool {
        let dt = lastT.map { max(1e-3, t - $0) } ?? 0.02
        lastT = t
        let alpha = 1 - exp(-dt / tau)
        emaAccelSq += alpha * (accelMag * accelMag - emaAccelSq)
        return emaAccelSq.squareRoot() > accelThreshold || rotMag > rotThreshold
    }
}

/// Continuous strain (0..1) + side tilt → 3+1 raw state, with hysteresis (plan §3.3–3.4).
/// Uses biomechanical strain bands instead of a fixed angle threshold.
final class PostureClassifier {
    var goodMax = 0.20      // strain upper bound: below this is "upright"
    var slightMax = 0.50    // above this is "poor"
    var hyst = 0.05         // strain hysteresis
    var rollWarnDeg = 15.0
    var rollGoodDeg = 12.0

    private(set) var current: PostureState = .good
    func reset() { current = .good }

    func classify(strain: Double, rollDeg: Double) -> PostureState {
        current = next(strain: strain, dRoll: abs(rollDeg))
        return current
    }

    private func next(strain s: Double, dRoll: Double) -> PostureState {
        switch current {
        case .poor:
            if s <= slightMax - hyst { return (s > goodMax || dRoll > rollWarnDeg) ? .slight : .good }
            return .poor
        case .slight:
            if s > slightMax { return .poor }
            if s <= goodMax - hyst && dRoll <= rollGoodDeg { return .good }
            return .slight
        case .good, .paused:
            if s > slightMax { return .poor }
            if s > goodMax || dRoll > rollWarnDeg { return .slight }
            return .good
        }
    }
}

/// Debounce/commit — a candidate state isn't committed until it lasts ≥dwell sec (plan §3.4).
final class PostureStateMachine {
    var dwell: Double = 0.7   // short debounce: fast response but absorbs momentary flicker
    private(set) var committed: PostureState = .good
    private var candidate: PostureState = .good
    private var candidateSince: TimeInterval = 0
    private var primed = false

    func update(candidate c: PostureState, t: TimeInterval) -> PostureState {
        if !primed {
            committed = c; candidate = c; candidateSince = t; primed = true
            return committed
        }
        if c != candidate { candidate = c; candidateSince = t }
        if candidate != committed && (t - candidateSince) >= dwell { committed = candidate }
        return committed
    }

    func noteGap() { primed = false }
}
