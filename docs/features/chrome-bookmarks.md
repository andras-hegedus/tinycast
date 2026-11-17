# Chrome Bookmarks

Google Chrome's bookmarks appear in the launcher as their own section, found by title or by address
and opened in Chrome with ↵. Tinycast reads and opens them and nothing else: adding, editing and
organizing stay with Chrome.

The section is a launcher category, **on** by default, like Applications. **Settings → Chrome
Bookmarks** carries the category switch and lists every bookmark with its alias field and the checkbox
that hides one row from search. Off is fully off: no profile folder is read, the slice is emptied, and
`ChromeBookmarkCoordinator.open(entryID:)` refuses to open anything.

## Invariants

- **Chrome owns the library.** Nothing about a bookmark is stored except what every launcher entry
  already keys by `preferenceKey` — alias, visibility, favorite, ranking.
- **The URL is the identity.** The entry id is `chrome-bookmark:<absolute URL>`. Chrome's own ids
  differ per profile, so a URL saved in two profiles is one row, titled by the first profile.
- **Bookmarks answer a query.** With an empty query they are left out of the listing (favorites and
  Suggestions still show them), because hundreds of rows would bury every other section.
- **A failed read keeps the last good library**, and only a non-empty read frees the preferences of
  bookmarks it no longer lists.
- **`Model/` stays Foundation-only and pure** for `ChromeBookmarkTests`.

## Discovery

`ChromeBookmarkReader` lists `~/Library/Application Support/Google/Chrome`, keeps `Default` and every
`Profile N` folder that holds a `Bookmarks` file, and parses each one's JSON off the main actor. Only
`http` and `https` bookmarks are kept, so bookmarklets and `chrome://` pages fall out. No TCC grant is
needed: the folder is not protected.

The files are re-checked on every launcher open and when the pane appears. A stamp of each file's
modification date skips the parse when nothing changed.

## Launcher

`AppEntry.Kind.chromeBookmark` publishes right after Apple Shortcuts. The row's title is the bookmark's
name, or its address when the name is blank; the subtitle is the address without scheme, `www.` or
trailing slash, so typing a domain finds it. It is file-backed: every row's `url` is Chrome.app, so all
rows draw Chrome's icon from one cached bitmap. `rankPriority` is 0, so on a full tie every other kind
leads. There is no per-bookmark hotkey.

↵ hides the palette without restoring focus and opens the URL with Chrome through `NSWorkspace`;
without Chrome installed it falls back to the default browser. A failure shows Tinycast's dialog.

`chromeBookmarks.enabled` in `settings.json` binds the category switch, as `systemSettings.enabled`
does.

## Standalone harness

```sh
./Scripts/run-tests.sh ChromeBookmarkTests
```
