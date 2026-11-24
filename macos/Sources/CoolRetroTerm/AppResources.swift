import Foundation

/// Locates the resources shared with the Qt app (profiles, fonts) and the
/// CRT shader source.
///
/// Inside the app bundle they live in Contents/Resources. When running with
/// `swift run` from the source tree, they come from macos/.build/resources,
/// which ./build-app.sh populates.
enum AppResources {
    static let directory: URL = {
        if let bundled = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("profiles.json").path) {
            return bundled
        }
        let macosDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CoolRetroTerm
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // macos
        return macosDirectory.appendingPathComponent(".build/resources")
    }()

    static var fontsDirectory: URL { directory.appendingPathComponent("Fonts") }

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        do {
            let data = try Data(contentsOf: url(name))
            return try JSONDecoder().decode(type, from: data)
        } catch {
            NSLog("cool-retro-term: could not load %@: %@", name, String(describing: error))
            return nil
        }
    }
}
