import AppKit

/// A look for the terminal: colours, font and CRT effect strengths.
///
/// Uses the same format as the Qt app's built-in profiles
/// (app/qml/ApplicationSettings.qml), exported to profiles.json at build time.
struct Profile: Decodable, Equatable {
    var name: String
    var fontName: String
    var fontColor: String
    var backgroundColor: String
    var frameColor: String
    var ambientLight: Double
    var bloom: Double
    var brightness: Double
    var burnIn: Double
    var chromaColor: Double
    var contrast: Double
    var flickering: Double
    var frameShininess: Double
    var frameSize: Double
    var glowingLine: Double
    var horizontalSync: Double
    var jitter: Double
    var margin: Double
    var rasterization: Int
    var rgbShift: Double
    var saturationColor: Double
    var screenCurvature: Double
    var screenRadius: Double
    var staticNoise: Double
    var blinkingCursor: Bool

    static let fallback = Profile(
        name: "Default Amber", fontName: "TERMINESS_SCALED",
        fontColor: "#ff8100", backgroundColor: "#000000", frameColor: "#cfcfcf",
        ambientLight: 0.3, bloom: 0.6, brightness: 0.5, burnIn: 0.3, chromaColor: 0.2,
        contrast: 0.8, flickering: 0.1, frameShininess: 0.3, frameSize: 0.1,
        glowingLine: 0.2, horizontalSync: 0.1, jitter: 0.2, margin: 0.3,
        rasterization: 0, rgbShift: 0, saturationColor: 0.2, screenCurvature: 0.2,
        screenRadius: 0.1, staticNoise: 0.1, blinkingCursor: false)
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

/// The built-in profiles plus the user's current choices, persisted in
/// UserDefaults and shared by every window.
final class ProfileStore {
    static let shared = ProfileStore()

    let profiles: [Profile]
    private let defaults = UserDefaults.standard

    private init() {
        let loaded = AppResources.decode([Profile].self, from: "profiles.json") ?? []
        profiles = loaded.isEmpty ? [Profile.fallback] : loaded
    }

    var current: Profile {
        // CRT_PROFILE overrides the saved choice (used for CI screenshots).
        let name = ProcessInfo.processInfo.environment["CRT_PROFILE"] ?? defaults.string(forKey: "profile")
        return profiles.first { $0.name == name } ?? profiles[0]
    }

    func select(_ name: String) {
        defaults.set(name, forKey: "profile")
        notify()
    }

    var effectsEnabled: Bool {
        get { defaults.object(forKey: "effectsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "effectsEnabled"); notify() }
    }

    /// Text size multiplier, changed with Cmd-Plus / Cmd-Minus.
    var zoom: Double {
        get { defaults.object(forKey: "zoom") as? Double ?? 1.0 }
        set { defaults.set(min(max(newValue, 0.5), 4.0), forKey: "zoom"); notify() }
    }

    private func notify() {
        NotificationCenter.default.post(name: .terminalAppearanceDidChange, object: nil)
    }
}
