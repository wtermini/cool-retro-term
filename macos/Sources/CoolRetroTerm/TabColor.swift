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

/// Colours offered in Shell ▸ Tab Color.
enum TabColorPalette {
    static let colors: [(name: String, color: NSColor)] = [
        ("Red", .systemRed),
        ("Orange", .systemOrange),
        ("Yellow", .systemYellow),
        ("Green", .systemGreen),
        ("Teal", .systemTeal),
        ("Blue", .systemBlue),
        ("Purple", .systemPurple),
        ("Pink", .systemPink),
        ("Gray", .systemGray),
    ]

    static func color(named name: String) -> NSColor? {
        colors.first { $0.name == name }?.color
    }

    /// A round swatch for menu items.
    static func swatch(_ color: NSColor, size: CGFloat = 12) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }
}

/// The widely used OSC 6 tab colour escape sequence, so scripts and shell config can
/// colour a tab, e.g. red while you're logged in to a production server:
///
///     printf '\e]6;1;bg;red;brightness;255\a'   (and green, blue; 0-255 each)
///     printf '\e]6;1;bg;*;default\a'            (back to no colour)
///
/// A colour chosen from the menu always takes precedence over one set this way.
enum TabColorSequence {
    case channel(index: Int, value: Double)   // 0 red, 1 green, 2 blue
    case reset

    /// Parses the data of an OSC 6 sequence (everything after "6;").
    init?(_ data: ArraySlice<UInt8>) {
        guard let text = String(bytes: data, encoding: .ascii) else { return nil }
        let parts = text.split(separator: ";").map { $0.lowercased() }
        guard parts.count >= 4, parts[0] == "1", parts[1] == "bg" else { return nil }
        if parts[2] == "*" && parts[3] == "default" {
            self = .reset
            return
        }
        guard parts.count == 5, parts[3] == "brightness",
              let level = Int(parts[4]), (0...255).contains(level),
              let index = ["red", "green", "blue"].firstIndex(of: parts[2]) else { return nil }
        self = .channel(index: index, value: Double(level) / 255)
    }
}
