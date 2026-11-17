import SwiftUI

struct ChromeBookmarksSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        Form {
            LauncherCategorySwitchSection(
                kind: .chromeBookmark, anchor: .chromeBookmarksChromeBookmarks,
                title: "Enable Chrome Bookmarks")

            LauncherItemsSection(
                kind: .chromeBookmark,
                anchor: .chromeBookmarksChromeBookmarks,
                searchPrompt: "Search bookmarks…",
                emptyMessage: LocalizedStringResource(
                    "chrome-bookmarks-empty", defaultValue: "No Chrome bookmarks found."))
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.chromeBookmarks)
        .releasesFocusOnOutsideClick()
        // Bookmarks change in Chrome while Settings sits open, and the switch reads or clears them.
        .task(id: visibility.isKindEnabled(.chromeBookmark)) { core.chromeBookmarkCoordinator.refresh() }
    }
}
