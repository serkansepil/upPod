import Foundation

// MARK: - Shared helpers

/// Shared day-key formatter ("yyyy-MM-dd") — the key format for `DailySummary` and
/// `ExerciseSessionRecord`. POSIX locale keeps the key stable regardless of the user's calendar/locale.
enum DayKey {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func string(from date: Date) -> String { formatter.string(from: date) }
}

// MARK: - Persistent data model

struct CalibrationData: Codable {
    var pitch0: Double, roll0: Double
    var g0x: Double, g0y: Double, g0z: Double
    var calibratedAt: Date
}

struct AppSettings: Codable {
    var sensitivity: Double = 1.0
}

extension AppSettings {
    // Tolerant decode: a missing key falls back to its default rather than throwing keyNotFound,
    // so adding a future setting never makes an old state.json undecodable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 1.0
    }
}

/// Daily summary (one record per day). For history/trend and continuing "today" where it left off.
struct DailySummary: Codable {
    var date: String           // "yyyy-MM-dd"
    var goodSec: Double = 0
    var slightSec: Double = 0
    var poorSec: Double = 0
    var doseSeconds: Double = 0
    var validSeconds: Double = 0
}

extension DailySummary {
    // Tolerant decode (same rationale as AppSettings): every field defaults if absent, so future
    // additive metrics won't throw on old files. `date` is also the dict key, so "" is a safe fallback.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date         = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        goodSec      = try c.decodeIfPresent(Double.self, forKey: .goodSec) ?? 0
        slightSec    = try c.decodeIfPresent(Double.self, forKey: .slightSec) ?? 0
        poorSec      = try c.decodeIfPresent(Double.self, forKey: .poorSec) ?? 0
        doseSeconds  = try c.decodeIfPresent(Double.self, forKey: .doseSeconds) ?? 0
        validSeconds = try c.decodeIfPresent(Double.self, forKey: .validSeconds) ?? 0
    }
}

/// Record of an exercise session (for history).
struct ExerciseResult: Codable {
    var id: String
    var name: String
    var reps: Int
    var holds: Int
}

struct ExerciseSessionRecord: Codable {
    var date: String           // "yyyy-MM-dd"
    var startedAt: Date
    var durationSec: Double
    var items: [ExerciseResult]
}

struct PersistedState: Codable {
    /// Bump when the on-disk semantics change (not just additive fields). Drives `migrate()`.
    static let currentSchemaVersion = 1

    var schemaVersion: Int = PersistedState.currentSchemaVersion
    var calibration: CalibrationData?
    var settings: AppSettings = AppSettings()
    var days: [String: DailySummary] = [:]
    var exerciseSessions: [ExerciseSessionRecord]? = nil   // Optional keeps the on-disk shape (no empty arrays)
}

extension PersistedState {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, calibration, settings, days, exerciseSessions
    }

    /// TOLERANT decoder: every field is read with `decodeIfPresent`, so a MISSING key never throws
    /// `.keyNotFound` (which would otherwise make `load()` discard the whole file). Additive future
    /// keys are simply ignored by the keyed container. A missing `schemaVersion` ⇒ 0 (pre-versioning).
    /// `encode(to:)` stays synthesized (same CodingKeys), so `schemaVersion` is written back out.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion    = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        calibration      = try c.decodeIfPresent(CalibrationData.self, forKey: .calibration)
        settings         = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        days             = try c.decodeIfPresent([String: DailySummary].self, forKey: .days) ?? [:]
        exerciseSessions = try c.decodeIfPresent([ExerciseSessionRecord].self, forKey: .exerciseSessions)
    }

    /// Forward-migration hook, applied after a successful decode. The bumped version is persisted on the next save.
    mutating func migrate() {
        if schemaVersion < 1 { schemaVersion = 1 }   // v0 → v1: stamp only, no data transform
        // future: if schemaVersion < 2 { /* transform */ schemaVersion = 2 }
    }
}

// MARK: - Store abstraction (plan §11: migration to GRDB is isolated behind this)

protocol SessionStore: AnyObject {
    func load() -> PersistedState
    func save(_ state: PersistedState)
}

/// JSON file store — ~/Library/Application Support/uppod/state.json. Zero dependencies,
/// 100% on-device ("Data Not Collected"), atomic writes. Can migrate to GRDB/SQLite as volume grows.
final class JSONFileStore: SessionStore {
    private let url: URL

    /// Direct path injection — used by tests; the file's directory is created if needed.
    init(url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.url = url
    }

    convenience init() {
        if let p = RuntimeFlags.value("UPPOD_STORE_PATH") {   // test isolation
            self.init(url: URL(fileURLWithPath: p))
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.init(url: base.appendingPathComponent("uppod", isDirectory: true).appendingPathComponent("state.json"))
        }
    }

    func load() -> PersistedState {
        guard let data = try? Data(contentsOf: url) else { return PersistedState() }   // no file yet
        do {
            var s = try JSONDecoder().decode(PersistedState.self, from: data)
            s.migrate()
            return s
        } catch {
            // Present but undecodable → preserve the user's bytes for recovery instead of silently wiping.
            backupCorruptFile()
            return PersistedState()
        }
    }

    private func backupCorruptFile() {
        let bak = url.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: bak)
        try? FileManager.default.moveItem(at: url, to: bak)
    }

    func save(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Diskless store — for mock/test (UPPOD_MOCK).
final class MemoryStore: SessionStore {
    private var state = PersistedState()
    func load() -> PersistedState { state }
    func save(_ s: PersistedState) { state = s }
}
