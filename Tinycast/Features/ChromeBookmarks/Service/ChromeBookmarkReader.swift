import AppKit

/// Reads Chrome's per-profile bookmark files and hands a URL to Chrome.
enum ChromeBookmarkReader {
    /// Every profile's file and its modification date, so an unchanged library is never re-parsed.
    struct Stamp: Equatable, Sendable {
        fileprivate let files: [String: Date]
    }

    static var chromeApplicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: ChromeBookmark.chromeBundleID)
    }

    private static var supportFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Google/Chrome", directoryHint: .isDirectory)
    }

    @concurrent
    static func stamp() async -> Stamp {
        var files: [String: Date] = [:]
        for file in bookmarkFiles() {
            let date = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            files[file.path] = date ?? .distantPast
        }
        return Stamp(files: files)
    }

    /// Nil when Chrome keeps no profile folder at all, so the caller can keep what it had.
    @concurrent
    static func read() async -> [ChromeBookmark]? {
        let files = bookmarkFiles()
        guard !files.isEmpty else { return nil }
        return ChromeBookmark.merged(
            files.compactMap { try? Data(contentsOf: $0) }.map(ChromeBookmark.parse))
    }

    private static func bookmarkFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: supportFolder.path)) ?? []
        return ChromeBookmark.profileDirectories(in: names)
            .map { supportFolder.appending(path: $0).appending(path: ChromeBookmark.fileName) }
            .filter { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    @MainActor
    static func open(_ url: URL) async throws {
        guard let chrome = chromeApplicationURL else {
            _ = try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        _ = try await NSWorkspace.shared.open(
            [url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
    }
}
