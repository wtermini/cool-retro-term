/*
 * Copyright (c) 2026 cool-retro-term contributors
 * https://github.com/Swordfish90/cool-retro-term
 *
 * This file is part of cool-retro-term.
 *
 * cool-retro-term is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import Foundation

/// Locates the resources shared with the Qt app (profiles, fonts) and the
/// CRT shader source.
///
/// Inside the app bundle they live in Contents/Resources. When running with
/// `swift run` from the source tree, they come from macos/.build/resources,
/// which ./build-app.sh populates.
/// Settings that CI uses to take screenshots (CRT_PROFILE, CRT_SNAPSHOT_PATH
/// and so on, read from the environment). They exist only in builds made
/// with `build-app.sh --ci-hooks`; in any other build every lookup is nil,
/// so nothing in the environment can type commands into the shell or write
/// files.
enum CIHooks {
    static func value(_ name: String) -> String? {
        #if CI_HOOKS
        return ProcessInfo.processInfo.environment[name]
        #else
        return nil
        #endif
    }
}

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

    static func decodeJSONArray(from name: String) -> [[String: Any]]? {
        do {
            let data = try Data(contentsOf: url(name))
            return try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        } catch {
            NSLog("cool-retro-term: could not load %@: %@", name, String(describing: error))
            return nil
        }
    }

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
