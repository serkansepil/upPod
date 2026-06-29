import Foundation

/// Cervical load model (based on the Hansraj 2014 curve): head forward-flexion angle → load on the neck (kg).
/// At 0° the head's own weight (~5 kg); as the angle grows the moment arm grows and the load rises rapidly.
enum CervicalLoad {
    // (degree, kg) nodes — linear interpolation in between
    private static let pts: [(deg: Double, kg: Double)] = [
        (0, 5), (15, 12), (30, 18), (45, 22), (60, 27)
    ]
    static let neutralKg = 5.0
    static let maxKg = 27.0

    /// Estimated neck load (kg) for a given flexion angle. Negative (back/up) = neutral.
    static func kg(_ flexionDeg: Double) -> Double {
        let f = max(0, flexionDeg)
        if f >= pts.last!.deg { return pts.last!.kg }
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            if f <= b.deg { return a.kg + (b.kg - a.kg) * (f - a.deg) / (b.deg - a.deg) }
        }
        return pts.last!.kg
    }

    /// 0..1 strain: the normalized excess above the neutral load, scaled by sensitivity.
    /// sensitivity > 1 → low angles count more (if the user says "10° is already leaning").
    static func strain(_ flexionDeg: Double, sensitivity: Double = 1.0) -> Double {
        let excess = (kg(flexionDeg) - neutralKg) / (maxKg - neutralKg)   // 0..1
        return min(1, max(0, excess * sensitivity))
    }
}
