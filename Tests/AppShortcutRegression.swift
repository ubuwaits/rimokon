import Foundation
@main struct AppShortcutRegression {
    static func main() {
        let apps: [[String: Any]] = [
            ["id": "netflix", "title": "Localized title"],
            ["id": "youtube.leanback.v4", "title": "YouTube"],
            ["id": "apple.variant", "title": "Apple TV"],
            ["id": "unrelated", "title": "YouTube Music"]]
        assert(TVApp.netflix.installedID(in: apps) == "netflix")
        assert(TVApp.youtube.installedID(in: apps) == "youtube.leanback.v4")
        assert(TVApp.appleTV.installedID(in: apps) == "apple.variant")
        assert(TVApp.youtube.installedID(in: [["id": "music", "title": "YouTube Music"]]) == nil)
        assert(TVApp.appleTV.installedID(in: [["title": "Apple TV"]]) == nil)
        assert(TVApp.netflix.installedID(in: []) == nil)
        print("PASS: installed app IDs, title fallback, missing apps and unrelated apps")
    }
}
