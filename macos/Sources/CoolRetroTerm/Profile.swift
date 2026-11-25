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

import AppKit

/// A look for the terminal: colours, font and CRT effect strengths.
///
/// Uses the Qt app's profile format (composeProfileObject() in
/// app/qml/ApplicationSettings.qml). Missing keys take the Qt app's defaults,
/// as its loadProfileString() does, and the original JSON is kept so that a
/// profile can be written back without losing keys this app doesn't use.
struct Profile: Equatable {
    var name: String
    var fontName: String = "TERMINESS_SCALED"
    var fontSource: Int = 0          // 0 bundled font id, 1 system font family
    var fontColor: String = "#ff8100"
    var backgroundColor: String = "#000000"
    var frameColor: String = "#ffffff"
    var ambientLight: Double = 0.2
    var bloom: Double = 0.55
    var brightness: Double = 0.5
    var burnIn: Double = 0.25
    var chromaColor: Double = 0.25
    var contrast: Double = 0.8
    var flickering: Double = 0.1
    var frameShininess: Double = 0.2
    var frameSize: Double = 0.2
    var glowingLine: Double = 0.2
    var horizontalSync: Double = 0.08
    var jitter: Double = 0.2
    var margin: Double = 0.5
    var rasterization: Int = 0
    var rgbShift: Double = 0
    var saturationColor: Double = 0.25
    var screenCurvature: Double = 0.3
    var screenRadius: Double = 0.2
    var staticNoise: Double = 0.12
    var blinkingCursor: Bool = false
    /// Horizontal stretch of the text, 0.5 to 1.5.
    var fontWidth: Double = 1.0
    /// Extra space between lines, as a fraction of the font's height.
    var lineSpacing: Double = 0.1
    /// 0 to 1; the window is shown at 70% to 100% opacity, as in the Qt app.
    var windowOpacity: Double = 1.0

    /// The profile as the Qt app stores it.
    var json: [String: Any] = [:]

    init(name: String, json: [String: Any]) {
        self.name = name
        self.json = json
        func number(_ key: String, _ value: inout Double) {
            if let n = json[key] as? NSNumber { value = n.doubleValue }
        }
        func string(_ key: String, _ value: inout String) {
            if let s = json[key] as? String { value = s }
        }
        string("fontName", &fontName)
        string("fontColor", &fontColor)
        string("backgroundColor", &backgroundColor)
        string("frameColor", &frameColor)
        number("ambientLight", &ambientLight)
        number("bloom", &bloom)
        number("brightness", &brightness)
        number("burnIn", &burnIn)
        number("chromaColor", &chromaColor)
        number("contrast", &contrast)
        number("flickering", &flickering)
        number("frameShininess", &frameShininess)
        number("frameSize", &frameSize)
        number("glowingLine", &glowingLine)
        number("horizontalSync", &horizontalSync)
        number("jitter", &jitter)
        number("margin", &margin)
        number("rgbShift", &rgbShift)
        number("saturationColor", &saturationColor)
        number("screenCurvature", &screenCurvature)
        number("screenRadius", &screenRadius)
        number("staticNoise", &staticNoise)
        number("fontWidth", &fontWidth)
        number("lineSpacing", &lineSpacing)
        number("windowOpacity", &windowOpacity)
        if let n = json["rasterization"] as? NSNumber { rasterization = n.intValue }
        if let n = json["fontSource"] as? NSNumber { fontSource = n.intValue }
        if let b = json["blinkingCursor"] as? Bool { blinkingCursor = b }
    }

    /// The profile in the Qt app's format, including any keys this app
    /// doesn't use (kept from the original JSON).
    var qtJSON: [String: Any] {
        var j = json
        j["fontName"] = fontName
        j["fontSource"] = fontSource
        j["fontColor"] = fontColor
        j["backgroundColor"] = backgroundColor
        j["frameColor"] = frameColor
        j["ambientLight"] = ambientLight
        j["bloom"] = bloom
        j["brightness"] = brightness
        j["burnIn"] = burnIn
        j["chromaColor"] = chromaColor
        j["contrast"] = contrast
        j["flickering"] = flickering
        j["frameShininess"] = frameShininess
        j["frameSize"] = frameSize
        j["glowingLine"] = glowingLine
        j["horizontalSync"] = horizontalSync
        j["jitter"] = jitter
        j["margin"] = margin
        j["rasterization"] = rasterization
        j["rgbShift"] = rgbShift
        j["saturationColor"] = saturationColor
        j["screenCurvature"] = screenCurvature
        j["screenRadius"] = screenRadius
        j["staticNoise"] = staticNoise
        j["blinkingCursor"] = blinkingCursor
        j["fontWidth"] = fontWidth
        j["lineSpacing"] = lineSpacing
        j["windowOpacity"] = windowOpacity
        return j
    }

    /// Whether two profiles look the same (ignoring the name).
    func sameSettings(as other: Profile) -> Bool {
        var a = self, b = other
        a.name = ""; b.name = ""
        a.json = [:]; b.json = [:]
        return a == b
    }

    static func == (lhs: Profile, rhs: Profile) -> Bool {
        lhs.name == rhs.name && lhs.fontName == rhs.fontName && lhs.fontSource == rhs.fontSource
            && lhs.fontColor.lowercased() == rhs.fontColor.lowercased()
            && lhs.backgroundColor.lowercased() == rhs.backgroundColor.lowercased()
            && lhs.frameColor.lowercased() == rhs.frameColor.lowercased()
            && lhs.numbers == rhs.numbers && lhs.rasterization == rhs.rasterization
            && lhs.blinkingCursor == rhs.blinkingCursor
    }

    private var numbers: [Double] {
        [ambientLight, bloom, brightness, burnIn, chromaColor, contrast, flickering, frameShininess,
         frameSize, glowingLine, horizontalSync, jitter, margin, rgbShift, saturationColor,
         screenCurvature, screenRadius, staticNoise, fontWidth, lineSpacing, windowOpacity].map { ($0 * 10000).rounded() / 10000 }
    }
}

// MARK: - Derived values (same formulas as the Qt app)

typealias RGB = SIMD3<Float>

func lint<T: FloatingPoint>(_ a: T, _ b: T, _ t: T) -> T { (1 - t) * a + t * b }

private func mix(_ a: RGB, _ b: RGB, _ t: Float) -> RGB { a * (1 - t) + b * t }

private func parseHex(_ string: String) -> RGB {
    let hex = string.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return RGB(1, 1, 1) }
    return RGB(Float((value >> 16) & 0xff), Float((value >> 8) & 0xff), Float(value & 0xff)) / 255
}

extension Profile {
    static func parseHexColor(_ string: String) -> RGB { parseHex(string) }

    /// Text colour after saturation and contrast are applied.
    var effectiveFontColor: RGB {
        let k = Float(0.7 + contrast * 0.3)
        return mix(parseHex(backgroundColor), saturatedColor, k)
    }

    /// Screen colour after saturation and contrast are applied.
    var effectiveBackgroundColor: RGB {
        let k = Float(0.7 + contrast * 0.3)
        return mix(saturatedColor, parseHex(backgroundColor), k)
    }

    /// Bezel colour, lit by the screen and the ambient light (TerminalFrame.qml).
    var effectiveFrameColor: RGB {
        let staticFrame = (parseHex(frameColor) + RGB(repeating: 0.1))
            .clamped(lowerBound: RGB(repeating: 0), upperBound: RGB(repeating: 1))
        let light = mix(effectiveFontColor, effectiveBackgroundColor, 0.2)
        return mix(light * 0.2, staticFrame, Float(0.125 + 0.75 * ambientLight))
    }

    private var saturatedColor: RGB {
        mix(parseHex(fontColor), RGB(repeating: 1), Float(saturationColor * 0.5))
    }

    /// Inset of the text from the edge of the screen, in points.
    var marginPoints: CGFloat {
        CGFloat(lint(1.0, 40.0, margin) + (1.0 - 0.5.squareRoot()) * screenRadiusPoints)
    }

    var screenRadiusPoints: Double { lint(4.0, 120.0, screenRadius) }
}

extension NSColor {
    convenience init(rgb: RGB) {
        self.init(srgbRed: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)
    }
}

// MARK: - Store

extension Notification.Name {
    static let terminalAppearanceDidChange = Notification.Name("CoolRetroTermAppearanceDidChange")
}

/// The profiles and current settings, shared with the Qt app.
///
/// The Qt app's settings database is the source of truth: the current
/// profile, the custom profiles and the text size are read from it, and
/// choices made here are written back, so the two apps stay in step. Only
/// the CRT Effects switch, which the Qt app doesn't have, is kept in this
/// app's own preferences.
final class ProfileStore {
    static let shared = ProfileStore()

    private let qt = QtSettings()
    private let builtins: [Profile]
    private(set) var customProfiles: [Profile] = []
    private(set) var current: Profile
    private(set) var zoom: Double = 1.0
    private(set) var customCommand: [String]?

    /// --default-settings: start from the built-in defaults and don't save.
    static var useDefaultSettings = false

    /// The Qt app's app-wide settings (_CURRENT_SETTINGS), with its defaults.
    private(set) var effectsFrameSkip = 3
    private(set) var windowScaling = 1.0
    private(set) var bloomQuality = 0.5
    private(set) var burnInQuality = 0.5
    private(set) var showTerminalSize = true
    /// Shared with the Qt app too (its Advanced settings).
    private(set) var sharedNewLineKeys = true
    private(set) var sharedAlwaysShowTabBar = false
    private(set) var sharedSecureKeyboardEntry = false
    private(set) var sharedPauseEffectsWhenIdle = false
    private(set) var sharedCursorShape = 0

    private init() {
        let exported = AppResources.decodeJSONArray(from: "profiles.json") ?? []
        let loaded = exported.compactMap { object -> Profile? in
            guard let name = object["name"] as? String else { return nil }
            var json = object
            json.removeValue(forKey: "name")
            return Profile(name: name, json: json)
        }
        builtins = loaded.isEmpty ? [Profile(name: "Default Amber", json: [:])] : loaded
        current = builtins[0]
        // No change notification here: observers would read
        // ProfileStore.shared while it is still being created, which traps.
        reload(notifying: false)
    }

    var profiles: [Profile] { builtins + customProfiles }
    var builtinProfiles: [Profile] { builtins }

    /// Re-reads the Qt app's settings, e.g. after it was changed there.
    func reload(notifying: Bool = true) {
        if Self.useDefaultSettings {
            current = builtins[0]
            return
        }
        flushPendingWrite()
        let previous = (current, zoom, customProfiles.map(\.name))

        customProfiles = (qt.jsonArray(for: "_CUSTOM_PROFILES") ?? []).compactMap { entry in
            guard let name = entry["text"] as? String,
                  let string = entry["obj_string"] as? String,
                  let data = string.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            return Profile(name: name, json: json)
        }

        if let override = ProcessInfo.processInfo.environment["CRT_PROFILE"],
           let profile = profiles.first(where: { $0.name == override }) {
            // Used for CI screenshots.
            current = profile
        } else if let json = qt.jsonObject(for: "_CURRENT_PROFILE") {
            // The Qt app stores the profile's settings, not its name, so
            // name it after the profile it matches, if any.
            let stored = Profile(name: "", json: json)
            current = Profile(name: profiles.first { $0.sameSettings(as: stored) }?.name ?? "", json: json)
        }

        let settings = qt.jsonObject(for: "_CURRENT_SETTINGS") ?? [:]
        if let scaling = settings["fontScaling"] as? NSNumber {
            zoom = scaling.doubleValue
        }
        if let n = settings["effectsFrameSkip"] as? NSNumber { effectsFrameSkip = min(max(n.intValue, 1), 5) }
        if let n = settings["windowScaling"] as? NSNumber { windowScaling = min(max(n.doubleValue, 0.25), 1) }
        if let n = settings["bloomQuality"] as? NSNumber { bloomQuality = min(max(n.doubleValue, 0.25), 1) }
        if let n = settings["burnInQuality"] as? NSNumber { burnInQuality = min(max(n.doubleValue, 0.25), 1) }
        if let b = settings["showTerminalSize"] as? Bool { showTerminalSize = b }
        if let b = settings["newLineKeys"] as? Bool { sharedNewLineKeys = b }
        if let b = settings["alwaysShowTabBar"] as? Bool { sharedAlwaysShowTabBar = b }
        if let b = settings["secureKeyboardEntry"] as? Bool { sharedSecureKeyboardEntry = b }
        if let b = settings["pauseEffectsWhenIdle"] as? Bool { sharedPauseEffectsWhenIdle = b }
        if let n = settings["cursorShape"] as? NSNumber { sharedCursorShape = min(max(n.intValue, 0), 2) }
        if settings["useCustomCommand"] as? Bool == true,
           let command = settings["customCommand"] as? String {
            let arguments = tokenizeCommandLine(command)
            customCommand = arguments.isEmpty ? nil : arguments
        } else {
            customCommand = nil
        }

        if notifying, previous.0 != current || previous.1 != zoom || previous.2 != customProfiles.map(\.name) {
            notify()
        }
    }

    func select(_ name: String) {
        guard let profile = profiles.first(where: { $0.name == name }) else { return }
        current = profile
        if !Self.useDefaultSettings {
            qt.setJSON(profile.json, for: "_CURRENT_PROFILE")
        }
        notify()
    }

    /// Text size, stored as the Qt app's fontScaling (0.25 to 2.5).
    func setZoom(_ value: Double) {
        zoom = min(max(value, 0.25), 2.5)
        writeAppSetting("fontScaling", zoom)
    }

    func setEffectsFrameSkip(_ value: Int) {
        effectsFrameSkip = min(max(value, 1), 5)
        writeAppSetting("effectsFrameSkip", effectsFrameSkip)
    }

    func setWindowScaling(_ value: Double) {
        windowScaling = min(max(value, 0.25), 1)
        writeAppSetting("windowScaling", windowScaling)
    }

    func setBloomQuality(_ value: Double) {
        bloomQuality = min(max(value, 0.25), 1)
        writeAppSetting("bloomQuality", bloomQuality)
    }

    func setBurnInQuality(_ value: Double) {
        burnInQuality = min(max(value, 0.25), 1)
        writeAppSetting("burnInQuality", burnInQuality)
    }

    func setShowTerminalSize(_ value: Bool) {
        showTerminalSize = value
        writeAppSetting("showTerminalSize", value)
    }

    private func writeAppSetting(_ key: String, _ value: Any) {
        if !Self.useDefaultSettings {
            var settings = qt.jsonObject(for: "_CURRENT_SETTINGS") ?? [:]
            settings[key] = value
            qt.setJSON(settings, for: "_CURRENT_SETTINGS")
        }
        notify()
    }

    // MARK: Import and export (same file format as the Qt app)

    /// Writes a profile as JSON with its name, as the Qt app's Export does.
    func exportProfile(_ profile: Profile, to url: URL) throws {
        var json = profile.qtJSON
        json["name"] = profile.name.isEmpty ? "Custom" : profile.name
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    /// Reads a profile exported by either app and saves it as a custom
    /// profile, then selects it. Returns its name.
    @discardableResult
    func importProfile(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var name = (json["name"] as? String) ?? url.deletingPathExtension().lastPathComponent
        json.removeValue(forKey: "name")
        if isBuiltin(name) { name += " (imported)" }
        current = Profile(name: "", json: json)
        current.json = current.qtJSON
        saveCurrent(as: name)
        select(name)
        return name
    }

    // MARK: Editing (Settings window)

    private var pendingWrite: DispatchWorkItem?

    /// Changes the current profile, as the Qt app's settings dialog does. The
    /// result is named after a saved profile if it matches one, and written
    /// to the shared settings shortly after the last change.
    func updateCurrent(_ change: (inout Profile) -> Void) {
        var profile = current
        change(&profile)
        profile.json = profile.qtJSON
        profile.name = profiles.first { $0.sameSettings(as: profile) }?.name ?? ""
        current = profile

        pendingWrite?.cancel()
        let write = DispatchWorkItem { [weak self] in self?.flushPendingWrite(force: true) }
        pendingWrite = write
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: write)
        notify()
    }

    private func flushPendingWrite(force: Bool = false) {
        guard force || pendingWrite != nil else { return }
        pendingWrite?.cancel()
        pendingWrite = nil
        if !Self.useDefaultSettings {
            qt.setJSON(current.json, for: "_CURRENT_PROFILE")
        }
    }

    /// Saves the current settings as a custom profile (shared with the Qt app).
    func saveCurrent(as name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !builtins.contains(where: { $0.name == trimmed }),
              let data = try? JSONSerialization.data(withJSONObject: current.qtJSON, options: [.sortedKeys]),
              let objString = String(data: data, encoding: .utf8) else { return }
        var list = qt.jsonArray(for: "_CUSTOM_PROFILES") ?? []
        list.removeAll { ($0["text"] as? String) == trimmed }
        list.append(["text": trimmed, "obj_string": objString, "builtin": false])
        qt.setJSON(list, for: "_CUSTOM_PROFILES")
        flushPendingWrite(force: true)
        reload()
        notify()
    }

    func deleteCustomProfile(_ name: String) {
        var list = qt.jsonArray(for: "_CUSTOM_PROFILES") ?? []
        list.removeAll { ($0["text"] as? String) == name }
        qt.setJSON(list, for: "_CUSTOM_PROFILES")
        reload()
        notify()
    }

    func isBuiltin(_ name: String) -> Bool { builtins.contains { $0.name == name } }

    /// The Qt app's "custom command instead of the shell" setting.
    var customCommandSetting: (enabled: Bool, command: String) {
        let settings = qt.jsonObject(for: "_CURRENT_SETTINGS") ?? [:]
        return (settings["useCustomCommand"] as? Bool ?? false, settings["customCommand"] as? String ?? "")
    }

    func setCustomCommand(enabled: Bool, command: String) {
        var settings = qt.jsonObject(for: "_CURRENT_SETTINGS") ?? [:]
        settings["useCustomCommand"] = enabled
        settings["customCommand"] = command
        qt.setJSON(settings, for: "_CURRENT_SETTINGS")
        reload()
    }

    // MARK: This app's own preferences

    private func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    private func store(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
        notify()
    }

    /// Option acts as Meta (Esc prefix) rather than typing special characters.
    var optionAsMeta: Bool {
        get { bool("optionAsMeta", default: true) }
        set { store("optionAsMeta", newValue) }
    }

    /// Shift-Return and Control-Return insert a new line.
    var newLineKeys: Bool {
        get { sharedNewLineKeys }
        set { sharedNewLineKeys = newValue; writeAppSetting("newLineKeys", newValue) }
    }

    /// Keep the tab bar visible in full screen.
    var tabBarInFullScreen: Bool {
        get { bool("tabBarInFullScreen", default: true) }
        set { store("tabBarInFullScreen", newValue) }
    }

    /// Show the tab bar even when a window has a single tab.
    var alwaysShowTabBar: Bool {
        get { sharedAlwaysShowTabBar }
        set { sharedAlwaysShowTabBar = newValue; writeAppSetting("alwaysShowTabBar", newValue) }
    }

    /// 0 solid block, 1 underline, 2 bar. Shared with the Qt app.
    var cursorShape: Int {
        get { sharedCursorShape }
        set { sharedCursorShape = min(max(newValue, 0), 2); writeAppSetting("cursorShape", sharedCursorShape) }
    }

    /// Stop animating the effects a few seconds after the last activity.
    var pauseEffectsWhenIdle: Bool {
        get { sharedPauseEffectsWhenIdle }
        set { sharedPauseEffectsWhenIdle = newValue; writeAppSetting("pauseEffectsWhenIdle", newValue) }
    }

    /// Secure Keyboard Entry (macOS), shared with the Qt app.
    var secureKeyboardEntry: Bool {
        get { sharedSecureKeyboardEntry }
        set { sharedSecureKeyboardEntry = newValue; writeAppSetting("secureKeyboardEntry", newValue) }
    }

    var effectsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "effectsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "effectsEnabled"); notify() }
    }

    private func notify() {
        NotificationCenter.default.post(name: .terminalAppearanceDidChange, object: nil)
    }
}

/// Splits a command line the way the Qt app does (tokenizeCommandLine() in
/// app/qml/utils.js): whitespace separates arguments, quotes group them,
/// and a backslash escapes the next character.
func tokenizeCommandLine(_ line: String) -> [String] {
    var arguments: [String] = []
    var token = ""
    var quote: Character?
    var escaped = false

    for c in line {
        if escaped {
            escaped = false
            token.append(c)
        } else if let q = quote {
            escaped = c == "\\"
            if c == q {
                quote = nil
                arguments.append(token)
                token = ""
            } else if !escaped {
                token.append(c)
            }
        } else {
            escaped = c == "\\"
            switch c {
            case "\\":
                break
            case "\n":
                arguments.append(token)
                token = ""
            case " ", "\t":
                if !token.isEmpty {
                    arguments.append(token)
                    token = ""
                }
            case "'", "\"":
                quote = c
            default:
                token.append(c)
            }
        }
    }
    if !token.isEmpty && !escaped && quote == nil {
        arguments.append(token)
    }
    return arguments
}
