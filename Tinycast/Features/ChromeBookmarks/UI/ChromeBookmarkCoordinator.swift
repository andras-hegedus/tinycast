import AppKit

/// Owns the Chrome Bookmarks flow: discovery into the launcher slice, and the one open funnel.
@MainActor
@Observable
final class ChromeBookmarkCoordinator {
    /// Every row draws Chrome's icon, so one cached bitmap serves the whole list.
    static var iconURL: URL {
        ChromeBookmarkReader.chromeApplicationURL
            ?? URL(fileURLWithPath: "/Applications/Google Chrome.app")
    }

    private let appIndex: AppIndex
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    @ObservationIgnored private var stamp: ChromeBookmarkReader.Stamp?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(
        appIndex: AppIndex, favorites: FavoritesStore, visibility: VisibilityStore,
        ranking: LauncherRankingStore, aliases: AliasStore,
        paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.appIndex = appIndex
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    private var isEnabled: Bool { visibility.isKindEnabled(.chromeBookmark) }

    /// Re-checked on every launcher open; only a changed file is parsed again.
    func refresh() {
        guard isEnabled else {
            stamp = nil
            appIndex.setChromeBookmarks([])
            return
        }
        guard refreshTask == nil else { return }
        refreshTask = Task {
            defer { refreshTask = nil }
            let current = await ChromeBookmarkReader.stamp()
            guard current != stamp else { return }
            // A failed read keeps the last good library, and with it every alias and favorite.
            guard let found = await ChromeBookmarkReader.read(), isEnabled else { return }
            stamp = current
            let iconURL = Self.iconURL
            appIndex.setChromeBookmarks(found.map { AppEntry($0, iconURL: iconURL) })
            removeReferences(toBookmarksMissingFrom: found)
        }
    }

    /// Frees what a deleted bookmark held; an empty library can't be told from an unreadable one.
    private func removeReferences(toBookmarksMissingFrom live: [ChromeBookmark]) {
        guard !live.isEmpty else { return }
        let liveIDs = Set(live.map(\.entryID))
        let keys =
            Array(aliases.aliases.keys) + favorites.keys + visibility.hiddenItemKeys
            + ranking.visits.keys
        let stale = Set(
            keys.filter { $0.hasPrefix(ChromeBookmark.entryIDPrefix) && !liveIDs.contains($0) })
        guard !stale.isEmpty else { return }
        favorites.remove(keys: stale)
        visibility.removeItemKeys(stale)
        aliases.removeKeys(stale)
        for key in stale { ranking.reset(itemKey: key) }
    }

    /// The one funnel a launcher row opens through, so the category switch can't be bypassed.
    func open(entryID: String) {
        guard isEnabled, let url = ChromeBookmark.url(fromEntryID: entryID) else { return }
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        Task {
            do {
                try await ChromeBookmarkReader.open(url)
            } catch {
                await core.showNotice(
                    title: String(localized: "Couldn’t Open Bookmark"),
                    message: error.localizedDescription, symbol: "bookmark", tone: .danger)
            }
        }
    }
}
