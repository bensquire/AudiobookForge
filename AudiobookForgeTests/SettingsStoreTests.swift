import XCTest
@testable import ForgeCore

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "SettingsStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func test_load_returnsDefaultsWhenNothingStored() {
        // Act
        let loaded = SettingsStore.load(defaults: defaults)

        // Assert
        XCTAssertEqual(loaded, EncodeSettings())
    }

    func test_roundTrip_preservesBitrateGainAndTemplate() {
        // Arrange
        var settings = EncodeSettings()
        settings.bitrate = .k128
        settings.gainBoost = .dB6
        settings.filenameTemplate = "{title}.m4b"

        // Act
        SettingsStore.save(settings, defaults: defaults)
        let loaded = SettingsStore.load(defaults: defaults)

        // Assert
        XCTAssertEqual(loaded.bitrate, .k128)
        XCTAssertEqual(loaded.gainBoost, .dB6)
        XCTAssertEqual(loaded.filenameTemplate, "{title}.m4b")
    }

    func test_roundTrip_restoresExistingOutputDirectory() throws {
        // Arrange — a real directory so the vanished-dir guard passes.
        // (The bare test runner isn't sandboxed, so persistence rides on
        // the plain-path fallback here; the bookmark path needs the app.)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var settings = EncodeSettings()
        settings.outputDirectory = dir

        // Act
        SettingsStore.save(settings, defaults: defaults)
        let loaded = SettingsStore.load(defaults: defaults)

        // Assert
        XCTAssertEqual(
            loaded.outputDirectory?.standardizedFileURL.path,
            dir.standardizedFileURL.path
        )
    }

    func test_load_dropsOutputDirectoryThatNoLongerExists() throws {
        // Arrange — save a real dir, then delete it before loading.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var settings = EncodeSettings()
        settings.outputDirectory = dir
        SettingsStore.save(settings, defaults: defaults)
        try FileManager.default.removeItem(at: dir)

        // Act
        let loaded = SettingsStore.load(defaults: defaults)

        // Assert — a stale dir must not satisfy canEnqueue.
        XCTAssertNil(loaded.outputDirectory)
    }

    func test_save_nilOutputDirectoryClearsStoredLocation() {
        // Arrange — store a directory first.
        let dir = FileManager.default.temporaryDirectory
        var settings = EncodeSettings()
        settings.outputDirectory = dir
        SettingsStore.save(settings, defaults: defaults)

        // Act — save again with no directory.
        settings.outputDirectory = nil
        SettingsStore.save(settings, defaults: defaults)
        let loaded = SettingsStore.load(defaults: defaults)

        // Assert
        XCTAssertNil(loaded.outputDirectory)
    }

    func test_load_ignoresUnknownRawValues() {
        // Arrange — simulate a future/renamed enum case in defaults.
        defaults.set("512k", forKey: "settings.bitrate")
        defaults.set("dB99", forKey: "settings.gainBoost")

        // Act
        let loaded = SettingsStore.load(defaults: defaults)

        // Assert — falls back to defaults instead of crashing/misreading.
        XCTAssertEqual(loaded.bitrate, EncodeSettings().bitrate)
        XCTAssertEqual(loaded.gainBoost, EncodeSettings().gainBoost)
    }
}
