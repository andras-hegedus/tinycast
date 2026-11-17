import Foundation

@main
struct ChromeBookmarkTests {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // Chrome's own shape: folders nest, and `roots` carries a non-folder value too.
        let file = Data(
            """
            {
              "checksum": "abc",
              "roots": {
                "bookmark_bar": {
                  "type": "folder", "name": "Bookmarks bar",
                  "children": [
                    { "type": "url", "name": "GitHub", "url": "https://github.com/" },
                    { "type": "folder", "name": "Work", "children": [
                      { "type": "url", "name": "  Linear  ", "url": "https://linear.app/team" },
                      { "type": "url", "name": "", "url": "https://www.example.com/docs/" }
                    ]},
                    { "type": "url", "name": "Script", "url": "javascript:alert(1)" },
                    { "type": "url", "name": "Settings", "url": "chrome://settings" }
                  ]
                },
                "other": { "type": "folder", "name": "Other", "children": [] },
                "synced": { "type": "folder", "name": "Mobile", "children": [
                  { "type": "url", "name": "News", "url": "http://news.ycombinator.com" }
                ]},
                "sync_transaction_version": "12"
              },
              "version": 1
            }
            """.utf8)
        let parsed = ChromeBookmark.parse(file)
        check("every http(s) bookmark is read, at any depth", parsed.count == 4)
        check(
            "bookmarklets and chrome:// pages fall out",
            !parsed.contains { $0.url.scheme == "javascript" || $0.url.scheme == "chrome" })
        check("a title is trimmed", parsed.contains { $0.title == "Linear" })

        let untitled = parsed.first { $0.title.isEmpty }
        check("the display URL drops scheme, www. and the trailing slash",
            untitled?.displayURL == "example.com/docs")
        check("an untitled bookmark shows its address", untitled?.displayTitle == "example.com/docs")

        check("garbage reads as empty", ChromeBookmark.parse(Data("not json".utf8)).isEmpty)
        check("a file without roots reads as empty", ChromeBookmark.parse(Data("{}".utf8)).isEmpty)

        let github = ChromeBookmark(title: "GitHub", url: URL(string: "https://github.com/")!)
        let renamed = ChromeBookmark(title: "Code", url: URL(string: "https://github.com/")!)
        let apple = ChromeBookmark(title: "apple", url: URL(string: "https://apple.com")!)
        let merged = ChromeBookmark.merged([[github], [renamed, apple]])
        check("a URL saved in two profiles is listed once", merged.count == 2)
        check("the first profile's title wins", merged.contains { $0.title == "GitHub" })
        check("sorted by title, ignoring case", merged.map(\.title) == ["apple", "GitHub"])

        check("the entry id round-trips", ChromeBookmark.url(fromEntryID: github.entryID) == github.url)
        check("another kind's id is refused", ChromeBookmark.url(fromEntryID: "quicklink:x") == nil)

        check(
            "only profile folders, Default first, then by number",
            ChromeBookmark.profileDirectories(
                in: ["Profile 10", "System Profile", "Crashpad", "Profile 2", "Default", "Guest Profile"])
                == ["Default", "Profile 2", "Profile 10"])

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) failed")
        if failures > 0 { exit(1) }
    }
}
