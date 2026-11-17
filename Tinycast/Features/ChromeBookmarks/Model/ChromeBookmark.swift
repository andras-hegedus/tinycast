import Foundation

/// A bookmark Chrome owns; Tinycast holds only what it needs to find and open it.
struct ChromeBookmark: Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "chrome-bookmark:"
    static let chromeBundleID = "com.google.Chrome"
    /// The file every profile folder keeps its bookmarks in, as Chrome writes it.
    static let fileName = "Bookmarks"

    let title: String
    let url: URL

    /// The URL is the identity: Chrome's own ids differ per profile and per sync round.
    var id: String { url.absoluteString }

    var entryID: String { Self.entryIDPrefix + url.absoluteString }

    static func url(fromEntryID entryID: String) -> URL? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return URL(string: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    /// What a row prints and what typing a domain matches: no scheme, `www.` or trailing slash.
    var displayURL: String {
        var text = url.absoluteString
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
            text.removeFirst(scheme.count)
        }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// A blank title falls back to the address, as Chrome's own bookmark bar does.
    var displayTitle: String { title.isEmpty ? displayURL : title }

    /// Profile folders that hold a bookmarks file, `Default` first, then `Profile N` in order.
    static func profileDirectories(in names: [String]) -> [String] {
        names.filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted { lhs, rhs in
                if lhs == "Default" || rhs == "Default" { return lhs == "Default" && rhs != "Default" }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }

    /// Reads one profile's `Bookmarks` JSON; anything that isn't an http(s) bookmark falls out.
    static func parse(_ data: Data) -> [ChromeBookmark] {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        var found: [ChromeBookmark] = []
        for root in file.roots.values { collect(root, into: &found) }
        return found
    }

    /// Profiles in order, first title wins; sorted by title so a section reads alphabetically.
    static func merged(_ profiles: [[ChromeBookmark]]) -> [ChromeBookmark] {
        var seen: Set<String> = []
        return profiles.joined()
            .filter { seen.insert($0.id).inserted }
            .sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
    }

    private static func collect(_ node: Node, into found: inout [ChromeBookmark]) {
        if node.type == "url", let raw = node.url, let url = URL(string: raw),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        {
            let title = (node.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            found.append(ChromeBookmark(title: title, url: url))
        }
        for child in node.children ?? [] { collect(child, into: &found) }
    }

    private struct File: Decodable {
        let roots: [String: Node]

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // `roots` also carries non-folder values such as `sync_transaction_version`.
            let raw = try container.nestedContainer(keyedBy: AnyKey.self, forKey: .roots)
            var roots: [String: Node] = [:]
            for key in raw.allKeys {
                if let node = try? raw.decode(Node.self, forKey: key) { roots[key.stringValue] = node }
            }
            self.roots = roots
        }

        private enum CodingKeys: String, CodingKey { case roots }
    }

    private struct Node: Decodable {
        let type: String?
        let name: String?
        let url: String?
        let children: [Node]?
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
