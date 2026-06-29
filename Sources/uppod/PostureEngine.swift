import Foundation
import Combine

/// UI-facing summary of a single day for the chart.
struct DayStat: Identifiable {
    let id: String
    let label: String       // e.g. "Mon"
    let goodMin: Double
    let slightMin: Double
    let poorMin: Double
    let score: Int?
    let isToday: Bool
}

/// Orchestrator that wires up the whole pipeline. SwiftUI + StatusBar observe this.
final class PostureEngine: ObservableObject {
    // Published UI state
    @Published var state: PostureState = .paused
    @Published var liveFlexionDeg: Double = 0      // gravity-fused, signed
    @Published var liveRollDeg: Double = 0
    @Published var loadKg: Double = CervicalLoad.neutralKg
    @Published var liveStrain: Double = 0          // 0..1
    @Published var connected: Bool = false
    @Published var motionAvailable: Bool = true
    @Published var authorization: MotionAuthorization = .notDetermined
    @Published var score: Int? = nil               // daily dose score
    @Published var goodSec: Double = 0
    @Published var slightSec: Double = 0
    @Published var poorSec: Double = 0
    @Published var calibratedAt: Date? = nil
    @Published var calibrating: Bool = false
    @Published var sensitivity: Double = 1.0       // personal sensitivity (0.7–1.6)
    @Published var history: [DayStat] = []         // last 7 days (chart)

    private(set) var currentTilt: Double = 0   // icon head tilt (degrees, 0..33)

    var onStateChange: ((PostureState) -> Void)?
    var onTilt: ((Double) -> Void)?

    // Exercise mode hook: while a session runs, forwards motion to ExerciseEngine and suspends posture accumulation
    var exerciseActive = false
    var onMotion: ((_ flexDeg: Double, _ rollDeg: Double, _ yaw: Double, _ sample: MotionSample) -> Void)?

    private let service: MotionProviding
    private let estimator = FlexionEstimator()
    private let flexEMA = ScalarEMA(tau: 0.4)
    private let rollEMA = ScalarEMA(tau: 0.4)
    private let strainEMA = ScalarEMA(tau: 0.3)   // light: flex is already smoothed, avoid double lag
    private let gate = MotionGate()
    private let classifier = PostureClassifier()
    private let machine = PostureStateMachine()
    private let calib = CalibrationManager()
    private let store = TimeInStateStore()
    private let dose = DoseAccumulator()

    private let persistence: SessionStore
    private var persisted = PersistedState()
    private var currentDay = ""
    private var lastPersist: TimeInterval = 0
    private static let weekdayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEE"; return f
    }()
    private func todayString() -> String { DayKey.string(from: Date()) }

    private func dailyScore(_ s: DailySummary) -> Int? {
        DoseAccumulator.score(doseSeconds: s.doseSeconds, validSeconds: s.validSeconds)
    }

    /// Convert the last n days (including today) into a DayStat array; missing days are zero.
    private func refreshHistory(_ n: Int = 7) {
        let cal = Calendar.current
        let now = Date()
        var out: [DayStat] = []
        for i in stride(from: n - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -i, to: now) else { continue }
            let key = DayKey.string(from: d)
            let s = persisted.days[key]
            out.append(DayStat(
                id: key,
                label: Self.weekdayFmt.string(from: d),
                goodMin: (s?.goodSec ?? 0) / 60,
                slightMin: (s?.slightSec ?? 0) / 60,
                poorMin: (s?.poorSec ?? 0) / 60,
                score: s.flatMap { dailyScore($0) },
                isToday: key == currentDay))
        }
        history = out
    }

    private var lastSampleT: TimeInterval = 0
    private var lastUIPublish: TimeInterval = 0
    private var lastHeartbeat: TimeInterval = 0
    private var wasValid = false
    private let debug = RuntimeFlags.enabled("UPPOD_DEBUG")
    private let autoCal = RuntimeFlags.enabled("UPPOD_AUTOCAL")
    private var autoCalDone = false
    private var firstSampleT: TimeInterval = 0

    init(service: MotionProviding, store persistence: SessionStore) {
        self.service = service
        self.persistence = persistence
        if let hs = service as? HeadphoneMotionService { motionAvailable = hs.isAvailable }
        if RuntimeFlags.enabled("UPPOD_FLIP_SIGN") { estimator.flexionSign = 1 }

        // Restore from disk: calibration, settings, today's accumulation
        persisted = persistence.load()
        sensitivity = persisted.settings.sensitivity
        currentDay = todayString()
        if let c = persisted.calibration {
            calib.restore(c)
            estimator.setBaseline(pitch: c.pitch0, roll: c.roll0, gx: c.g0x, gy: c.g0y, gz: c.g0z)
            calibratedAt = c.calibratedAt
        }
        if let d = persisted.days[currentDay] {
            self.store.seed(good: d.goodSec, slight: d.slightSec, poor: d.poorSec)
            dose.seed(dose: d.doseSeconds, valid: d.validSeconds)
            goodSec = d.goodSec; slightSec = d.slightSec; poorSec = d.poorSec
            score = dose.dailyScore
        }
        refreshHistory()

        calib.onComplete = { [weak self] in
            guard let self else { return }
            self.estimator.setBaseline(pitch: self.calib.pitch0, roll: self.calib.roll0,
                                       gx: self.calib.g0x, gy: self.calib.g0y, gz: self.calib.g0z)
            self.calibrating = false
            self.calibratedAt = self.calib.calibratedAt
            self.classifier.reset(); self.machine.noteGap()
            self.flexEMA.reset(); self.rollEMA.reset(); self.strainEMA.reset()
            self.persist()   // persist calibration immediately
            if self.debug { print("[uppod] calibration done: pitch0=\(self.calib.pitch0 * DEG)° g0=(\(self.calib.g0x),\(self.calib.g0y),\(self.calib.g0z))") }
        }
        service.onConnection = { [weak self] c in DispatchQueue.main.async { self?.handleConnection(c) } }
        service.onAuthorization = { [weak self] a in DispatchQueue.main.async { self?.handleAuthorization(a) } }
        service.onSample = { [weak self] s in DispatchQueue.main.async { self?.process(s) } }
    }

    /// Write the current state to disk (periodically + on calibration + on exit).
    func persist() {
        persisted.settings.sensitivity = sensitivity
        if calib.isCalibrated, let at = calib.calibratedAt {
            persisted.calibration = CalibrationData(pitch0: calib.pitch0, roll0: calib.roll0,
                                                    g0x: calib.g0x, g0y: calib.g0y, g0z: calib.g0z,
                                                    calibratedAt: at)
        }
        persisted.days[currentDay] = DailySummary(
            date: currentDay,
            goodSec: store.seconds[.good] ?? 0,
            slightSec: store.seconds[.slight] ?? 0,
            poorSec: store.seconds[.poor] ?? 0,
            doseSeconds: dose.doseSeconds,
            validSeconds: dose.validSeconds)
        persistence.save(persisted)
        refreshHistory()
    }

    func persistNow() { persist() }

    /// Append the exercise session via a single owner (this engine) — so the periodic posture write doesn't clobber it.
    func appendExerciseSession(_ rec: ExerciseSessionRecord) {
        persisted.exerciseSessions = (persisted.exerciseSessions ?? []) + [rec]
        persist()
    }

    func start() { service.start() }
    func stop() { service.stop() }

    func calibrate() {
        guard connected else { return }
        calibrating = true
        calib.begin(t: lastSampleT)
    }

    private func handleConnection(_ c: Bool) {
        connected = c
        if !c { machine.noteGap(); wasValid = false; setState(.paused) }
    }

    private func handleAuthorization(_ a: MotionAuthorization) {
        guard a != authorization else { return }
        authorization = a
        if a == .unavailable { motionAvailable = false }
        // Denied/restricted: no samples will ever arrive — keep the UI in a clear paused state.
        if a == .denied || a == .restricted { machine.noteGap(); wasValid = false; setState(.paused) }
        if debug { print("[uppod] motion authorization → \(a)") }
    }

    private func process(_ s: MotionSample) {
        lastSampleT = s.t
        if !connected { connected = true }

        // Day rollover: write the old day to disk, reset counters, history is preserved
        let today = todayString()
        if today != currentDay {
            persist()
            store.reset(); dose.reset()
            goodSec = 0; slightSec = 0; poorSec = 0; score = nil
            currentDay = today
        }

        if autoCal && !autoCalDone {
            if firstSampleT == 0 { firstSampleT = s.t }
            else if s.t - firstSampleT > 1.0 && !calib.isCapturing && !calib.isCalibrated {
                autoCalDone = true; calibrating = true; calib.begin(t: s.t)
            }
        }
        if calib.isCapturing {
            calib.feed(pitch: s.pitch, roll: s.roll, gx: s.gx, gy: s.gy, gz: s.gz, t: s.t)
        }

        // Gravity-fused absolute flexion + smoothing
        let est = estimator.estimate(pitch: s.pitch, roll: s.roll, gx: s.gx, gy: s.gy, gz: s.gz)
        let flex = flexEMA.update(est.flex, t: s.t)
        let rollD = rollEMA.update(est.roll, t: s.t)
        liveFlexionDeg = flex
        liveRollDeg = rollD
        loadKg = CervicalLoad.kg(flex)

        // Continuous strain (biomechanical) + sensitivity
        let rawStrain = CervicalLoad.strain(flex, sensitivity: sensitivity)
        liveStrain = strainEMA.update(rawStrain, t: s.t)

        // Exercise mode: forward the raw (no EMA, no lag) flex/roll + yaw to the exercise engine.
        // While a session runs, suspend posture accumulation (accumulate/dose/persist) — keep the daily score clean.
        onMotion?(est.flex, est.roll, s.yaw, s)
        if exerciseActive {
            machine.noteGap(); wasValid = false
            setState(.paused)
            return
        }

        // Validity
        let moving = gate.update(accelMag: s.accelMag, rotMag: s.rotMag, t: s.t)
        let lying = abs(s.gz) < cos(60 * .pi / 180)
        let valid = calib.isCalibrated && !moving && !lying && !calib.isCapturing

        let effective: PostureState
        if valid {
            if !wasValid { machine.noteGap() }
            let c = classifier.classify(strain: liveStrain, rollDeg: rollD)
            effective = machine.update(candidate: c, t: s.t)
        } else {
            machine.noteGap()
            effective = .paused
        }
        wasValid = valid

        store.accumulate(state: effective, t: s.t)
        dose.add(strain: liveStrain, valid: valid, t: s.t)
        setState(effective)

        if s.t - lastUIPublish > 0.25 {
            lastUIPublish = s.t
            goodSec = store.seconds[.good] ?? 0
            slightSec = store.seconds[.slight] ?? 0
            poorSec = store.seconds[.poor] ?? 0
            score = dose.dailyScore
            let t = (min(max(flex, 0), 33) / 3).rounded() * 3   // head tilt, 3° steps (no needless redraw)
            if t != currentTilt { currentTilt = t; onTilt?(t) }
        }

        if s.t - lastPersist > 10 { lastPersist = s.t; persist() }

        if debug, s.t - lastHeartbeat > 2 {
            lastHeartbeat = s.t
            print(String(format: "[uppod] %@ | flex=%.1f° roll=%.1f° | load=%.1fkg strain=%.2f | score=%@ | g=(%.2f,%.2f,%.2f) | valid=%@",
                         state.rawValue, flex, rollD, loadKg, liveStrain,
                         score.map(String.init) ?? "—", s.gx, s.gy, s.gz, valid ? "Y" : "N"))
        }
    }

    private func setState(_ s: PostureState) {
        guard s != state else { return }
        state = s
        onStateChange?(s)
        if debug { print("[uppod] state → \(s.rawValue)") }
    }

}
