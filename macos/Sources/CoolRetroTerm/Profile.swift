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
        if let n = json["rasterization"] as? NSNumber { rasterization = n.intValue }
        if let n = json["fontSource"] as? NSNumber { fontSource = n.intValue }
        if let b = json["blinkingCursor"] as? Bool { blinkingCursor = b }
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
         screenCurvature, screenRadius, staticNoise].map { ($0 * 10000).rounded() / 10000 }
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
        reload()
    }

    var profiles: [Profile] { builtins + customProfiles }
    var builtinProfiles: [Profile] { builtins }

    /// Re-reads the Qt app's settings, e.g. after it was changed there.
    func reload() {
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
        if settings["useCustomCommand"] as? Bool == true,
           let command = settings["customCommand"] as? String {
            let arguments = tokenizeCommandLine(command)
            customCommand = arguments.isEmpty ? nil : arguments
        } else {
            customCommand = nil
        }

        if previous.0 != current || previous.1 != zoom || previous.2 != customProfiles.map(\.name) {
            notify()
        }
    }

    func select(_ name: String) {
        guard let profile = profiles.first(where: { $0.name == name }) else { return }
        current = profile
        qt.setJSON(profile.json, for: "_CURRENT_PROFILE")
        notify()
    }

    /// Text size, stored as the Qt app's fontScaling (0.25 to 2.5).
    func setZoom(_ value: Double) {
        zoom = min(max(value, 0.25), 2.5)
        var settings = qt.jsonObject(for: "_CURRENT_SETTINGS") ?? [:]
        settings["fontScaling"] = zoom
        qt.setJSON(settings, for: "_CURRENT_SETTINGS")
        notify()
    }

    /// Show the tab bar even when a window has a single tab.
    var alwaysShowTabBar: Bool {
        get { UserDefaults.standard.bool(forKey: "alwaysShowTabBar") }
        set { UserDefaults.standard.set(newValue, forKey: "alwaysShowTabBar"); notify() }
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
