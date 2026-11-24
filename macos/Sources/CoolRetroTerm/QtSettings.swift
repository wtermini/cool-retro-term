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

import CryptoKit
import Foundation
import SQLite3

/// Reads and writes the Qt app's settings, so both front ends share one
/// configuration.
///
/// The Qt app stores its settings with QtQuick.LocalStorage (app/qml/Storage.qml):
/// a SQLite database named "coolretroterm2", in a table
/// `settings(setting TEXT UNIQUE, value TEXT)`. Qt keeps it at
///   <AppDataLocation>/QML/OfflineStorage/Databases/<md5(name)>.sqlite
/// which on macOS is under ~/Library/Application Support/cool-retro-term/cool-retro-term.
/// Alongside it is an .ini file describing the database, which Qt checks
/// when opening it.
///
/// Keys used (see ApplicationSettings.qml):
///   _CURRENT_PROFILE   JSON object: the profile currently in use
///   _CURRENT_SETTINGS  JSON object: app settings such as fontScaling
///   _CUSTOM_PROFILES   JSON array of {"text", "obj_string", "builtin"}
final class QtSettings {
    static let databaseName = "coolretroterm2"
    static let databaseVersion = "1.0"

    let databaseURL: URL

    init(directory: URL = QtSettings.defaultDirectory) {
        let digest = Insecure.MD5.hash(data: Data(Self.databaseName.utf8))
        let id = digest.map { String(format: "%02x", $0) }.joined()
        databaseURL = directory.appendingPathComponent(id + ".sqlite")
    }

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        // QCoreApplication organisation and application names, from app/main.cpp.
        return support
            .appendingPathComponent("cool-retro-term/cool-retro-term/QML/OfflineStorage/Databases")
    }

    var exists: Bool { FileManager.default.fileExists(atPath: databaseURL.path) }

    // MARK: Reading

    func value(for key: String) -> String? {
        guard exists, let db = open(flags: SQLITE_OPEN_READONLY) else { return nil }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM settings WHERE setting = ?;", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, Self.transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: text)
    }

    func jsonObject(for key: String) -> [String: Any]? {
        guard let text = value(for: key), let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func jsonArray(for key: String) -> [[String: Any]]? {
        guard let text = value(for: key), let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    // MARK: Writing

    /// Stores a value the way Storage.qml's setSetting() does. Creates the
    /// database, and its .ini descriptor, if the Qt app has never run.
    @discardableResult
    func setValue(_ value: String, for key: String) -> Bool {
        let creating = !exists
        if creating {
            try? FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
        }
        guard let db = open(flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) else { return false }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)

        guard sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS settings(setting TEXT UNIQUE, value TEXT);",
                           nil, nil, nil) == SQLITE_OK else { return false }
        if creating { writeIniDescriptor() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO settings VALUES (?, ?);", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, Self.transient)
        sqlite3_bind_text(statement, 2, value, -1, Self.transient)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    func setJSON(_ object: Any, for key: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        setValue(text, for: key)
    }

    // MARK: Helpers

    private func open(flags: Int32) -> OpaquePointer? {
        var db: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &db, flags, nil) != SQLITE_OK {
            sqlite3_close(db)
            return nil
        }
        return db
    }

    /// The descriptor QtQuick.LocalStorage writes next to each database.
    private func writeIniDescriptor() {
        let ini = """
            [General]
            Description=StorageDatabase
            Driver=QSQLITE
            EstimatedSize=100000
            Name=\(Self.databaseName)
            Version=\(Self.databaseVersion)

            """
        let url = databaseURL.deletingPathExtension().appendingPathExtension("ini")
        try? ini.write(to: url, atomically: true, encoding: .utf8)
    }

    /// SQLITE_TRANSIENT: SQLite copies bound strings before the call returns.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
