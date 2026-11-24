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

    /// The font for a profile: a bundled font id, or (fontSource 1) the
    /// family name of a font installed on the system.
    func font(for profile: Profile, pointSize: CGFloat) -> NSFont {
        if profile.fontSource == 1,
           let font = NSFontManager.shared.font(withFamily: profile.fontName, traits: [], weight: 5, size: pointSize)
            ?? NSFont(name: profile.fontName, size: pointSize) {
            return font
        }
        return font(for: profile.fontName, pointSize: pointSize)
    }

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
