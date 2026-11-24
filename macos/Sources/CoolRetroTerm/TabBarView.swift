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

@MainActor
protocol TabBarViewDelegate: AnyObject {
    func tabBar(_ tabBar: TabBarView, didSelect index: Int)
    func tabBar(_ tabBar: TabBarView, didClose index: Int)
    func tabBar(_ tabBar: TabBarView, didMoveFrom source: Int, to destination: Int)
    /// A name typed in the tab; nil means go back to the automatic title.
    func tabBar(_ tabBar: TabBarView, didRename index: Int, to title: String?)
    func tabBarDidRequestNewTab(_ tabBar: TabBarView)
    func tabBar(_ tabBar: TabBarView, menuFor index: Int) -> NSMenu?
}

/// The window's tab bar, drawn by the app so tabs can be fully coloured,
/// renamed by double-clicking, closed with a button or middle click,
/// reordered by dragging and given a right-click menu.
@MainActor
final class TabBarView: NSView, NSTextFieldDelegate {
    struct Item: Equatable {
        var title: String
        var color: NSColor?
        /// The name to start editing from (the custom name, if any).
        var editableTitle: String
    }

    static let height: CGFloat = 30

    weak var delegate: TabBarViewDelegate?

    var items: [Item] = [] {
        didSet {
            if items != oldValue {
                needsDisplay = true
                rebuildAccessibility()
            }
        }
    }

    var selectedIndex = 0 {
        didSet { if selectedIndex != oldValue { needsDisplay = true; rebuildAccessibility() } }
    }

    /// Colour of the selected tab's underline: the profile's phosphor colour.
    var accentColor: NSColor = .systemOrange {
        didSet { needsDisplay = true }
    }

    private var hoverIndex: Int?
    private var hoverClose = false
    private var pressedCloseIndex: Int?
    private var dragIndex: Int?
    private var dragStartX: CGFloat = 0
    private var dragOffset: CGFloat = 0
    private var isDragging = false
    private var editor: NSTextField?
    private var editingIndex: Int?
    private var accessibilityTabs: [TabAccessibilityElement] = []

    private let barColor = NSColor(white: 0.07, alpha: 1)
    private let tabColor = NSColor(white: 0.12, alpha: 1)
    private let selectedTabColor = NSColor(white: 0.2, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Tabs")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry

    private let plusWidth: CGFloat = 30
    private let gap: CGFloat = 4
    private let sideInset: CGFloat = 8

    private var tabWidth: CGFloat {
        guard !items.isEmpty else { return 0 }
        let available = bounds.width - sideInset * 2 - plusWidth - gap * CGFloat(items.count)
        return min(240, max(56, available / CGFloat(items.count)))
    }

    private func tabRect(_ index: Int) -> NSRect {
        NSRect(x: sideInset + CGFloat(index) * (tabWidth + gap), y: 4,
               width: tabWidth, height: bounds.height - 4)
    }

    private func closeRect(in tab: NSRect) -> NSRect {
        NSRect(x: tab.minX + 7, y: tab.midY - 7, width: 14, height: 14)
    }

    private var plusRect: NSRect {
        let x = items.isEmpty ? sideInset : tabRect(items.count - 1).maxX + gap
        return NSRect(x: x, y: 4, width: plusWidth - 6, height: bounds.height - 6)
    }

    private func index(at point: NSPoint) -> Int? {
        items.indices.first { tabRect($0).contains(point) }
    }

    private func showsClose(_ index: Int) -> Bool {
        items.count > 1 && (index == hoverIndex || index == selectedIndex)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        barColor.setFill()
        bounds.fill()

        for index in items.indices where index != dragIndex || !isDragging {
            drawTab(index, in: tabRect(index))
        }
        if isDragging, let dragIndex, items.indices.contains(dragIndex) {
            var rect = tabRect(dragIndex)
            rect.origin.x = min(max(dragStartX + dragOffset - rect.width / 2, sideInset),
                                bounds.width - rect.width - plusWidth)
            drawTab(dragIndex, in: rect)
        }
        drawPlus()
    }

    private func drawTab(_ index: Int, in rect: NSRect) {
        let item = items[index]
        let selected = index == selectedIndex
        let hovered = index == hoverIndex

        let fill: NSColor
        if let color = item.color?.usingColorSpace(.sRGB) {
            // Coloured tabs: full colour when selected, dimmed otherwise.
            fill = selected ? color : color.blended(withFraction: hovered ? 0.35 : 0.5, of: barColor) ?? color
        } else {
            fill = selected ? selectedTabColor : (hovered ? selectedTabColor.blended(withFraction: 0.5, of: tabColor) ?? tabColor : tabColor)
        }
        let shape = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        fill.setFill()
        shape.fill()
        // Square off the bottom corners so tabs sit on the terminal.
        NSRect(x: rect.minX, y: rect.maxY - 6, width: rect.width, height: 6).fill()

        if selected {
            (item.color == nil ? accentColor : NSColor.white.withAlphaComponent(0.85)).setFill()
            NSRect(x: rect.minX + 6, y: rect.maxY - 2, width: rect.width - 12, height: 2).fill()
        }

        let textColor = Self.textColor(on: fill, selected: selected, colored: item.color != nil)
        let leading: CGFloat = 26
        let textRect = NSRect(x: rect.minX + leading, y: rect.minY, width: rect.width - leading * 2, height: rect.height)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .regular),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ]
        let title = NSAttributedString(string: item.title, attributes: attributes)
        let height = title.size().height
        title.draw(with: NSRect(x: textRect.minX, y: textRect.midY - height / 2, width: textRect.width, height: height),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        if showsClose(index) {
            let close = closeRect(in: rect)
            if hovered && hoverClose {
                textColor.withAlphaComponent(0.2).setFill()
                NSBezierPath(roundedRect: close, xRadius: 3, yRadius: 3).fill()
            }
            let cross = NSBezierPath()
            let inset = close.insetBy(dx: 4, dy: 4)
            cross.move(to: NSPoint(x: inset.minX, y: inset.minY))
            cross.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
            cross.move(to: NSPoint(x: inset.maxX, y: inset.minY))
            cross.line(to: NSPoint(x: inset.minX, y: inset.maxY))
            cross.lineWidth = 1.3
            textColor.withAlphaComponent(0.85).setStroke()
            cross.stroke()
        }
    }

    private func drawPlus() {
        let rect = plusRect
        let plus = NSBezierPath()
        let c = NSPoint(x: rect.midX, y: rect.midY)
        plus.move(to: NSPoint(x: c.x - 5, y: c.y))
        plus.line(to: NSPoint(x: c.x + 5, y: c.y))
        plus.move(to: NSPoint(x: c.x, y: c.y - 5))
        plus.line(to: NSPoint(x: c.x, y: c.y + 5))
        plus.lineWidth = 1.5
        NSColor(white: 0.7, alpha: 1).setStroke()
        plus.stroke()
    }

    /// Black or white text, whichever reads better on the tab.
    private static func textColor(on fill: NSColor, selected: Bool, colored: Bool) -> NSColor {
        guard colored, let c = fill.usingColorSpace(.sRGB) else {
            return selected ? .white : NSColor(white: 0.72, alpha: 1)
        }
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luminance > 0.55 ? NSColor(white: 0.05, alpha: 1) : .white
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { updateHover(event) }
    override func mouseEntered(with event: NSEvent) { updateHover(event) }

    override func mouseExited(with event: NSEvent) {
        hoverIndex = nil
        hoverClose = false
        needsDisplay = true
    }

    private func updateHover(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = index(at: point)
        let overClose = index.map { closeRect(in: tabRect($0)).contains(point) } ?? false
        if index != hoverIndex || overClose != hoverClose {
            hoverIndex = index
            hoverClose = overClose
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if plusRect.contains(point) {
            delegate?.tabBarDidRequestNewTab(self)
            return
        }
        guard let index = index(at: point) else {
            // Double-clicking empty space opens a tab, as in Safari.
            if event.clickCount == 2 { delegate?.tabBarDidRequestNewTab(self) }
            return
        }
        if showsClose(index) && closeRect(in: tabRect(index)).contains(point) {
            pressedCloseIndex = index
            return
        }
        if event.clickCount == 2 {
            beginEditing(index)
            return
        }
        delegate?.tabBar(self, didSelect: index)
        dragIndex = index
        dragStartX = point.x
        dragOffset = 0
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let current = dragIndex else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragOffset = point.x - dragStartX
        if !isDragging && abs(dragOffset) < 5 { return }
        isDragging = true

        // Move the tab once the pointer passes the middle of a neighbour.
        let target = min(max(Int((point.x - sideInset) / (tabWidth + gap)), 0), items.count - 1)
        if target != current {
            delegate?.tabBar(self, didMoveFrom: current, to: target)
            dragIndex = target
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = pressedCloseIndex, items.indices.contains(index),
           closeRect(in: tabRect(index)).contains(point) {
            delegate?.tabBar(self, didClose: index)
        }
        pressedCloseIndex = nil
        dragIndex = nil
        isDragging = false
        needsDisplay = true
    }

    /// Middle-click closes a tab.
    override func otherMouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.buttonNumber == 2, let index = index(at: point), items.count > 1 {
            delegate?.tabBar(self, didClose: index)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = index(at: point) else { return nil }
        return delegate?.tabBar(self, menuFor: index)
    }

    // MARK: Renaming

    /// Edits a tab's name in place. Return saves, Escape cancels, and an
    /// empty name goes back to the automatic title.
    func beginEditing(_ index: Int) {
        guard items.indices.contains(index) else { return }
        endEditing(commit: false)
        let field = NSTextField(string: items[index].editableTitle)
        field.frame = tabRect(index).insetBy(dx: 24, dy: 5)
        field.font = NSFont.systemFont(ofSize: 12)
        field.alignment = .center
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.placeholderString = "Automatic"
        addSubview(field)
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        editor = field
        editingIndex = index
    }

    private func endEditing(commit: Bool) {
        guard let field = editor, let index = editingIndex else { return }
        editor = nil
        editingIndex = nil
        let text = field.stringValue
        field.removeFromSuperview()
        if commit {
            delegate?.tabBar(self, didRename: index, to: text)
        }
        delegate?.tabBar(self, didSelect: selectedIndex)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endEditing(commit: false)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            endEditing(commit: true)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        endEditing(commit: true)
    }

    // MARK: Accessibility

    override func accessibilityChildren() -> [Any]? {
        accessibilityTabs
    }

    private func rebuildAccessibility() {
        accessibilityTabs = items.indices.map { index in
            let element = TabAccessibilityElement()
            element.setAccessibilityRole(.radioButton)
            element.setAccessibilityLabel(items[index].title)
            element.setAccessibilityValue(index == selectedIndex ? 1 : 0)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(tabRect(index))
            element.onPress = { [weak self] in
                guard let self else { return }
                self.delegate?.tabBar(self, didSelect: index)
            }
            return element
        }
    }

    override func layout() {
        super.layout()
        rebuildAccessibility()
    }
}

/// A tab as seen by VoiceOver.
final class TabAccessibilityElement: NSAccessibilityElement {
    var onPress: (@MainActor () -> Void)?

    override func accessibilityPerformPress() -> Bool {
        guard let onPress else { return false }
        MainActor.assumeIsolated { onPress() }
        return true
    }
}
