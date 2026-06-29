import XCTest
@testable import uppod

final class PersistedStateDecodeTests: XCTestCase {
    private func decode(_ json: String) throws -> PersistedState {
        try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
    }

    func testOldFileWithoutVersionOrExerciseSessionsDoesNotWipe() throws {
        // A pre-versioning file: calibration + settings + days present, no schemaVersion / exerciseSessions.
        let json = """
        {
          "calibration": {"pitch0": 0.1, "roll0": 0.2, "g0x": 0, "g0y": 0, "g0z": -1, "calibratedAt": 0},
          "settings": {"sensitivity": 1.3},
          "days": {"2024-01-01": {"date": "2024-01-01", "goodSec": 10, "slightSec": 5, "poorSec": 2, "doseSeconds": 3, "validSeconds": 100}}
        }
        """
        let s = try decode(json)
        XCTAssertNotNil(s.calibration)
        XCTAssertEqual(s.calibration?.pitch0 ?? .nan, 0.1, accuracy: 1e-9)
        XCTAssertEqual(s.settings.sensitivity, 1.3, accuracy: 1e-9)
        XCTAssertEqual(s.days["2024-01-01"]?.goodSec, 10)
        XCTAssertNil(s.exerciseSessions)
        XCTAssertEqual(s.schemaVersion, 0)   // pre-versioning marker, before migrate()
    }

    func testMinimalFileDecodesWithDefaults() throws {
        let s = try decode(#"{"days": {"2024-02-02": {"date": "2024-02-02"}}}"#)
        XCTAssertEqual(s.settings.sensitivity, 1.0, accuracy: 1e-9)   // default
        XCTAssertNotNil(s.days["2024-02-02"])
        XCTAssertNil(s.calibration)
    }

    func testEmptyObjectDecodesToDefaults() throws {
        let s = try decode("{}")
        XCTAssertNil(s.calibration)
        XCTAssertTrue(s.days.isEmpty)
        XCTAssertEqual(s.schemaVersion, 0)
    }

    func testUnknownFutureKeyIsIgnored() throws {
        let s = try decode(#"{"schemaVersion": 1, "futureField": 123, "days": {}}"#)
        XCTAssertEqual(s.schemaVersion, 1)
        XCTAssertTrue(s.days.isEmpty)
    }

    func testMigrateBumpsVersionAndPreservesData() throws {
        var s = try decode(#"{"days": {"2024-01-01": {"date": "2024-01-01", "goodSec": 7}}}"#)
        XCTAssertEqual(s.schemaVersion, 0)
        s.migrate()
        XCTAssertEqual(s.schemaVersion, 1)
        XCTAssertEqual(s.days["2024-01-01"]?.goodSec, 7)
    }

    func testRoundTrip() throws {
        var original = PersistedState()
        original.settings.sensitivity = 1.4
        original.days["2024-03-03"] = DailySummary(date: "2024-03-03", goodSec: 1, slightSec: 2, poorSec: 3, doseSeconds: 4, validSeconds: 5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, PersistedState.currentSchemaVersion)
        XCTAssertEqual(decoded.settings.sensitivity, 1.4, accuracy: 1e-9)
        XCTAssertEqual(decoded.days["2024-03-03"]?.validSeconds, 5)
    }

    func testMalformedFieldThrows() {
        // `days` is the wrong shape (array, not object) → decode must throw so load() can back up.
        XCTAssertThrowsError(try decode(#"{"days": []}"#))
    }
}

final class JSONFileStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("uppod-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMissingFileReturnsFreshStateWithoutBackup() {
        let url = dir.appendingPathComponent("state.json")
        let store = JSONFileStore(url: url)
        let s = store.load()
        XCTAssertTrue(s.days.isEmpty)
        XCTAssertEqual(s.schemaVersion, PersistedState.currentSchemaVersion)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("bak").path))
    }

    func testRoundTripThroughDisk() {
        let url = dir.appendingPathComponent("state.json")
        let store = JSONFileStore(url: url)
        var s = PersistedState()
        s.settings.sensitivity = 1.5
        s.days["2024-05-05"] = DailySummary(date: "2024-05-05", goodSec: 42)
        store.save(s)

        let reloaded = JSONFileStore(url: url).load()
        XCTAssertEqual(reloaded.settings.sensitivity, 1.5, accuracy: 1e-9)
        XCTAssertEqual(reloaded.days["2024-05-05"]?.goodSec, 42)
    }

    func testCorruptFileIsBackedUpNotWiped() throws {
        let url = dir.appendingPathComponent("state.json")
        let garbage = "this is not json at all {{{".data(using: .utf8)!
        try garbage.write(to: url)

        let store = JSONFileStore(url: url)
        let s = store.load()

        // Fresh state returned (no silent loss of behavior)…
        XCTAssertTrue(s.days.isEmpty)
        XCTAssertEqual(s.schemaVersion, PersistedState.currentSchemaVersion)

        // …and the user's original bytes are preserved in .bak for recovery.
        let bak = url.appendingPathExtension("bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bak.path))
        XCTAssertEqual(try Data(contentsOf: bak), garbage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))   // original moved, not copied
    }
}
