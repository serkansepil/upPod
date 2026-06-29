import Foundation
import Combine

/// Engine that runs the exercise session. Fed from PostureEngine.onMotion (main thread).
final class ExerciseEngine: ObservableObject {
    // UI state
    @Published var phase: SessionPhase = .ready
    @Published var currentIndex: Int = 0
    @Published var currentExercise: Exercise?
    @Published var repCount: Int = 0
    @Published var targetReps: Int = 0
    @Published var holdProgress: Double = 0     // 0..1 (chin tuck)
    @Published var isInRange: Bool = false
    @Published var liveSignalDeg: Double = 0
    @Published var feedbackText: String = ""
    @Published var restRemaining: Double = 0
    @Published var summaryItems: [ExerciseResult] = []   // end screen
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var sessionExercises: [Exercise] = ExerciseLibrary.all

    private let posture: PostureEngine
    private let debug = RuntimeFlags.enabled("UPPOD_DEBUG")

    private var plan: [Exercise] = []
    private var results: [ExerciseResult] = []
    private var startedAt = Date()

    // detector state
    private var engaged = false
    private var lastT: TimeInterval = 0
    private var yawBaseline = 0.0
    private var yawBaselineSet = false
    private var holdActive = false
    private var holdElapsed = 0.0
    private var holdCooldownUntil: TimeInterval = 0

    private var restTimer: Timer?
    private var sessionTimer: Timer?

    init(posture: PostureEngine) {
        self.posture = posture
    }

    var motionConnected: Bool { posture.connected }
    var isCalibrated: Bool { posture.calibratedAt != nil }

    // MARK: - Session control

    /// For a fresh start screen when the window opens.
    func reset() {
        guard phase == .done || phase == .ready else { return }
        restTimer?.invalidate(); restTimer = nil
        phase = .ready
        currentExercise = nil
        repCount = 0; targetReps = 0; holdProgress = 0; restRemaining = 0
        feedbackText = ""
        elapsedSeconds = 0
        sessionExercises = ExerciseLibrary.all
    }

    func start(_ exercises: [Exercise] = ExerciseLibrary.all) {
        guard phase == .ready || phase == .done else { return }
        plan = exercises
        sessionExercises = exercises
        results = []
        startedAt = Date()
        elapsedSeconds = 0
        startSessionTimer()
        posture.exerciseActive = true
        posture.onMotion = { [weak self] flex, roll, yaw, sample in
            self?.handle(flex: flex, roll: roll, yaw: yaw, sample: sample)
        }
        beginExercise(0)
    }

    func skip() {
        switch phase {
        case .active:
            recordCurrent()
            advance()
        case .resting:
            restTimer?.invalidate(); restTimer = nil
            let next = currentIndex + 1
            if next >= plan.count { finish() } else { beginExercise(next) }
        default:
            break
        }
    }

    func stop() {
        restTimer?.invalidate(); restTimer = nil
        sessionTimer?.invalidate(); sessionTimer = nil
        elapsedSeconds = Date().timeIntervalSince(startedAt)
        let wasRunning = (phase == .active || phase == .resting)
        if phase == .active { recordCurrent() }
        posture.onMotion = nil
        posture.exerciseActive = false
        if wasRunning { writeSession() }
        summaryItems = results
        phase = .done
        currentExercise = nil
        feedbackText = "Session ended"
    }

    // MARK: - Sequencing

    private func beginExercise(_ i: Int) {
        currentIndex = i
        let ex = plan[i]
        currentExercise = ex
        targetReps = ex.totalReps
        repCount = 0
        holdProgress = 0; holdElapsed = 0; holdActive = false
        engaged = false
        yawBaselineSet = false
        holdCooldownUntil = 0
        liveSignalDeg = 0
        isInRange = false
        feedbackText = ex.instruction
        phase = .active
        if debug { print("[uppod-ex] begin \(ex.id) target=\(targetReps)") }
    }

    private func completeExercise() {
        recordCurrent()
        advance()
    }

    private func advance() {
        let next = currentIndex + 1
        if next >= plan.count { finish(); return }
        startRest(then: next)
    }

    private func startRest(then next: Int) {
        let rest = plan[currentIndex].restSeconds
        phase = .resting
        restRemaining = rest
        isInRange = false
        feedbackText = "Rest"
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.restRemaining = max(0, self.restRemaining - 0.1)
            if self.restRemaining <= 0 {
                self.restTimer?.invalidate(); self.restTimer = nil
                self.beginExercise(next)
            }
        }
    }

    private func finish() {
        restTimer?.invalidate(); restTimer = nil
        sessionTimer?.invalidate(); sessionTimer = nil
        elapsedSeconds = Date().timeIntervalSince(startedAt)
        posture.onMotion = nil
        posture.exerciseActive = false
        writeSession()
        summaryItems = results
        phase = .done
        currentExercise = nil
        feedbackText = "Done — great work!"
        if debug { print("[uppod-ex] session done, \(results.count) exercises") }
    }

    // MARK: - Recording

    private func recordCurrent() {
        guard let ex = currentExercise else { return }
        if results.last?.id == ex.id { return }   // prevent duplicate recording
        switch ex.goal {
        case .guidedHold: results.append(ExerciseResult(id: ex.id, name: ex.name, reps: 0, holds: repCount))
        case .reps:       results.append(ExerciseResult(id: ex.id, name: ex.name, reps: repCount, holds: 0))
        }
    }

    private func writeSession() {
        guard !results.isEmpty else { return }
        let rec = ExerciseSessionRecord(
            date: DayKey.string(from: startedAt),
            startedAt: startedAt,
            durationSec: Date().timeIntervalSince(startedAt),
            items: results)
        posture.appendExerciseSession(rec)   // single owner → no clobber
    }

    private func startSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsedSeconds = Date().timeIntervalSince(self.startedAt)
        }
    }

    // MARK: - Detection

    private func handle(flex: Double, roll: Double, yaw: Double, sample: MotionSample) {
        guard phase == .active, let ex = currentExercise else { lastT = sample.t; return }
        switch ex.axis {
        case .flexion:  detectRep(signal: flex, ex: ex)
        case .roll:     detectRep(signal: roll, ex: ex)
        case .yaw:      detectYaw(yaw: yaw, ex: ex)
        case .chinTuck: detectChinTuck(sample: sample, ex: ex)
        }
        lastT = sample.t
    }

    /// Drift-free axes (flexion/roll): reach target + return to neutral = rep.
    private func detectRep(signal: Double, ex: Exercise) {
        liveSignalDeg = signal
        let target = ex.targetDeg
        if !engaged {
            if abs(signal) >= target {
                engaged = true; isInRange = true
                feedbackText = "✓ — return to center"
            } else {
                isInRange = false
                feedbackText = "Reach \(Int(target))°"
            }
        } else if abs(signal) <= ex.neutralBand {
            engaged = false; isInRange = false
            repCount += 1
            if debug { print("[uppod-ex] \(ex.id) rep \(repCount)/\(targetReps) sig=\(Int(signal))") }
            if repCount >= targetReps { completeExercise() }
            else { feedbackText = "\(repCount)/\(targetReps) — now the other side" }
        }
    }

    /// Yaw: baseline at the start + reset to zero at neutral on every rep → drift cancelled within the rep window.
    private func detectYaw(yaw: Double, ex: Exercise) {
        if !yawBaselineSet { yawBaseline = yaw; yawBaselineSet = true; liveSignalDeg = 0; return }
        let dyaw = wrapPi(yaw - yawBaseline) * DEG
        liveSignalDeg = dyaw
        let target = ex.targetDeg
        if !engaged {
            if abs(dyaw) >= target {
                engaged = true; isInRange = true
                feedbackText = "✓ — return to center"
            } else {
                isInRange = false
                feedbackText = "Turn to \(Int(target))°"
            }
        } else if abs(dyaw) <= ex.neutralBand {
            engaged = false; isInRange = false
            yawBaseline = yaw   // reset again at neutral (cancels slow drift)
            repCount += 1
            if debug { print("[uppod-ex] yaw rep \(repCount)/\(targetReps)") }
            if repCount >= targetReps { completeExercise() }
            else { feedbackText = "\(repCount)/\(targetReps) — now the other side" }
        }
    }

    /// Chin tuck: can't be validated by angle. Motion gate (rotMag peak) → guided hold counter.
    private func detectChinTuck(sample: MotionSample, ex: Exercise) {
        guard case let .guidedHold(seconds, _) = ex.goal else { return }
        let dt = lastT > 0 ? max(0, sample.t - lastT) : 0
        if !holdActive {
            if sample.t < holdCooldownUntil {
                feedbackText = "Relax…"
                holdProgress = 0
                return
            }
            if sample.rotMag > 0.3 {          // engagement gate: brief motion peak
                holdActive = true; holdElapsed = 0
                feedbackText = "Hold the tuck…"
            } else {
                feedbackText = "Tuck your chin and hold"
                holdProgress = 0
            }
        } else {
            holdElapsed += dt
            holdProgress = min(1, holdElapsed / seconds)
            isInRange = true
            if holdElapsed >= seconds {
                holdActive = false; isInRange = false; holdProgress = 0
                repCount += 1
                holdCooldownUntil = sample.t + 1.8
                if debug { print("[uppod-ex] chintuck hold \(repCount)/\(targetReps)") }
                if repCount >= targetReps { completeExercise() }
                else { feedbackText = "Relax… \(repCount)/\(targetReps)" }
            }
        }
    }

    private func wrapPi(_ a: Double) -> Double {
        var x = a
        while x > .pi { x -= 2 * .pi }
        while x < -.pi { x += 2 * .pi }
        return x
    }
}
