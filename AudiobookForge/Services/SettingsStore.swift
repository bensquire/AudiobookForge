import Foundation

/// Persists the encode settings that should survive app relaunches.
/// Bitrate, gain, and the filename template are plain UserDefaults
/// values; the output directory needs two representations:
///
/// - a security-scoped bookmark, so the *sandbox grant* survives a
///   relaunch (a bare path would resolve but EPERM on first write), and
/// - the plain path as a fallback, because unsigned dev builds
///   (`scripts/build.sh` passes CODE_SIGNING_ALLOWED=NO) have no
///   sandbox and can't create security-scoped bookmarks at all.
enum SettingsStore {
    private enum Key {
        static let bitrate = "settings.bitrate"
        static let gain = "settings.gainBoost"
        static let template = "settings.filenameTemplate"
        static let outputBookmark = "settings.outputBookmark"
        static let outputPath = "settings.outputPath"
    }

    /// Pass `previous` (the value before this change) to skip the
    /// bookmark work when the directory didn't change — bookmark
    /// creation talks to the sandbox daemon, which is the one
    /// non-trivial cost here and would otherwise run on every
    /// bitrate/gain click.
    static func save(
        _ settings: EncodeSettings,
        previous: EncodeSettings? = nil,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(settings.bitrate.rawValue, forKey: Key.bitrate)
        defaults.set(settings.gainBoost.rawValue, forKey: Key.gain)
        defaults.set(settings.filenameTemplate, forKey: Key.template)
        guard settings.outputDirectory != previous?.outputDirectory || previous == nil else {
            return
        }
        guard let url = settings.outputDirectory else {
            defaults.removeObject(forKey: Key.outputBookmark)
            defaults.removeObject(forKey: Key.outputPath)
            return
        }
        let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: Key.outputBookmark)
        defaults.set(url.path, forKey: Key.outputPath)
    }

    @MainActor
    static func load(defaults: UserDefaults = .standard) -> EncodeSettings {
        var settings = EncodeSettings()
        if let raw = defaults.string(forKey: Key.bitrate),
           let bitrate = EncodeSettings.Bitrate(rawValue: raw)
        {
            settings.bitrate = bitrate
        }
        if let raw = defaults.string(forKey: Key.gain),
           let gain = EncodeSettings.GainBoost(rawValue: raw)
        {
            settings.gainBoost = gain
        }
        if let template = defaults.string(forKey: Key.template), !template.isEmpty {
            settings.filenameTemplate = template
        }
        settings.outputDirectory = loadOutputDirectory(defaults: defaults)
        return settings
    }

    @MainActor
    private static func loadOutputDirectory(defaults: UserDefaults) -> URL? {
        var resolved: URL?
        if let data = defaults.data(forKey: Key.outputBookmark) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                SecurityScope.retain(url)
                resolved = url
            }
        }
        if resolved == nil, let path = defaults.string(forKey: Key.outputPath) {
            resolved = URL(fileURLWithPath: path)
        }
        // The directory may have been deleted or unmounted since last
        // run; a vanished output dir must not satisfy canEnqueue and
        // then fail at encode time.
        guard let url = resolved, isDirectory(url) else { return nil }
        return url
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            && isDir.boolValue
    }
}
