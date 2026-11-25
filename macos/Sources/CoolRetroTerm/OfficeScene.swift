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

/// Office mode: the terminal is shown as the screen of a monitor on a desk,
/// zoomed out, in an 80s or 90s office. Shared with the Qt app
/// (`officeScene` in its settings, and app/qml/OfficeScene.qml).
///
/// The pictures come from scripts/generate-office-scenes.py, which also
/// defines the layout numbers below; keep them in step.
enum OfficeScene: String, CaseIterable {
    case off = ""
    case eighties = "80s"
    case nineties = "90s"

    var title: String {
        switch self {
        case .off: return "Off"
        case .eighties: return "80s Den"
        case .nineties: return "90s Cubicle"
        }
    }

    /// Fills any part of the window the picture doesn't cover.
    var wallColor: NSColor {
        switch self {
        case .off: return .black
        case .eighties: return NSColor(srgbRed: 72 / 255, green: 45 / 255, blue: 25 / 255, alpha: 1)
        case .nineties: return NSColor(srgbRed: 64 / 255, green: 70 / 255, blue: 83 / 255, alpha: 1)
        }
    }

    var image: NSImage? {
        switch self {
        case .off: return nil
        case .eighties, .nineties:
            return NSImage(contentsOf: AppResources.url("Office/office-\(rawValue).jpg"))
        }
    }

    // Layout of the pictures, in their pixels with the origin at the top left.
    static let imageSize = CGSize(width: 2400, height: 1500)
    static let screen = CGRect(x: 720, y: 250, width: 960, height: 720)
    static let monitor = CGRect(x: 620, y: 150, width: 1160, height: 1000)

    struct Layout {
        /// Where the picture is drawn, and where the terminal goes, in view
        /// coordinates (origin at the bottom left, as AppKit uses).
        var image: CGRect
        var screen: CGRect
    }

    /// Fills the view with the picture, centred on the monitor, zooming out
    /// further if needed so the whole monitor stays in view.
    static func layout(in size: CGSize) -> Layout {
        let m = monitor
        var scale = max(size.width / imageSize.width, size.height / imageSize.height)
        scale = min(scale, size.width / m.width, size.height / m.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale

        func offset(_ view: CGFloat, _ image: CGFloat, _ centre: CGFloat) -> CGFloat {
            guard image >= view else { return (view - image) / 2 }
            return min(max(view / 2 - centre * scale, view - image), 0)
        }
        let x = offset(size.width, w, m.midX)
        let top = offset(size.height, h, m.midY)   // from the top
        let imageRect = CGRect(x: x, y: size.height - top - h, width: w, height: h)
        let screenRect = CGRect(x: x + screen.minX * scale,
                                y: size.height - top - screen.maxY * scale,
                                width: screen.width * scale,
                                height: screen.height * scale).integral
        return Layout(image: imageRect, screen: screenRect)
    }
}

/// Draws the office picture behind the terminal.
final class OfficeSceneView: NSView {
    var scene: OfficeScene = .off {
        didSet {
            guard scene != oldValue else { return }
            imageLayer.contents = scene.image
            layer?.backgroundColor = scene.wallColor.cgColor
            isHidden = scene == .off
        }
    }

    private let imageLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isHidden = true
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        imageLayer.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func place(image frame: CGRect) {
        imageLayer.frame = frame
    }
}
