import AppKit
import CoreText

/// A font bundled with cool-retro-term (exported from app/fontmanager.cpp).
struct BundledFont: Decodable {
    var id: String
    var name: String
    var file: String
    var baseWidth: Double
    /// The size, in pixels, the font was designed for.
    var pixelSize: Int
    /// Bitmap-style fonts that should be rendered at their native pixel size
    /// and scaled up, rather than drawn smoothly at screen resolution.
    var lowResolution: Bool
    var fallback: String?
}

/// Registers the bundled retro fonts with Core Text for this process and
/// resolves profile font ids to NSFonts.
final class FontLibrary {
    static let shared = FontLibrary()

    private var fonts: [String: BundledFont] = [:]
    private var postScriptNames: [String: String] = [:]

    private init() {
        for font in AppResources.decode([BundledFont].self, from: "fonts.json") ?? [] {
            fonts[font.id] = font
            let url = AppResources.fontsDirectory.appendingPathComponent(font.file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let first = descriptors.first,
               let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String {
                postScriptNames[font.id] = name
            }
        }
    }

    func entry(for id: String) -> BundledFont? { fonts[id] }

    func font(for id: String, pointSize: CGFloat) -> NSFont {
        if let name = postScriptNames[id], let font = NSFont(name: name, size: pointSize) {
            return font
        }
        if let fallback = fonts[id]?.fallback, fallback != id {
            return font(for: fallback, pointSize: pointSize)
        }
        return NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
    }
}
