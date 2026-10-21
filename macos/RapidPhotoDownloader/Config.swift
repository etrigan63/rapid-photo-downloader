import Foundation

/// Portable configuration mirroring Rapid Photo Downloader's settings subset.
/// Persisted to UserDefaults and exportable/importable as JSON so a config
/// can be saved and applied to later installations.
struct RPDConfig: Codable, Equatable {
    var destinationRoot: String = ""
    var backupRoot: String = ""
    var backupEnabled: Bool = false
    var folderPattern: String = "%Y/%Y-%m-%d"
    var includeVideos: Bool = true
    var counterDigits: Int = 4
    var thumbnailSize: Int = 200

    static let userDefaultsKey = "RPDConfig"

    // MARK: - UserDefaults persistence

    static func load() -> RPDConfig {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let cfg = try? JSONDecoder().decode(RPDConfig.self, from: data) {
            return cfg
        }
        return RPDConfig()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: RPDConfig.userDefaultsKey)
        }
    }

    // MARK: - File export/import (portable config)

    func export(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> RPDConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RPDConfig.self, from: data)
    }

    // MARK: - Folder pattern formatting (RPD uses strftime-like %Y/%m/%d)

    func formattedFolder(for date: Date) -> String {
        // Convert % directives to DateFormatter tokens.
        var fmt = folderPattern
        let map: [(String, String)] = [
            ("%Y", "yyyy"), ("%y", "yy"),
            ("%m", "MM"), ("%d", "dd"),
            ("%H", "HH"), ("%M", "mm"), ("%S", "ss"),
            ("%B", "MMMM"), ("%b", "MMM"),
        ]
        for (a, b) in map { fmt = fmt.replacingOccurrences(of: a, with: b) }
        let df = DateFormatter()
        df.dateFormat = fmt
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.string(from: date)
    }
}

// MARK: - Config application helper

extension RPDConfig {
    /// Resolve a possibly-~ path.
    var resolvedDestination: URL? {
        guard !destinationRoot.isEmpty else { return nil }
        return URL(fileURLWithPath: (destinationRoot as NSString).expandingTildeInPath)
    }
    var resolvedBackup: URL? {
        guard backupEnabled, !backupRoot.isEmpty else { return nil }
        return URL(fileURLWithPath: (backupRoot as NSString).expandingTildeInPath)
    }
}