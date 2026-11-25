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

/// Draws the office desk's sticky notes and wall calendar for the 3D room,
/// as the Qt app's StickyNoteFace.qml and CalendarFace.qml do. The text
/// comes from the desk, which agents can write, so it's only ever drawn as
/// plain text.
enum OfficeDeskArt {
    static let papers: [String: NSColor] = [
        "yellow": NSColor(hex: "#faec78"), "pink": NSColor(hex: "#ffaabe"), "green": NSColor(hex: "#b4e6a0"),
        "blue": NSColor(hex: "#a8d0f8"), "orange": NSColor(hex: "#ffc078"),
    ]
    private static let ink = NSColor(hex: "#2b2d6e")

    static func note(_ note: DeskNote) -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: true) { rect in
            let paper = papers[note.color] ?? papers["yellow"]!
            paper.setFill()
            rect.fill()
            (paper.blended(withFraction: 0.06, of: .black) ?? paper).setFill()
            NSRect(x: 0, y: 0, width: 256, height: 26).fill()

            let box = NSRect(x: 20, y: 34, width: 216, height: 202)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            // The largest size, from 46 down to 14 points, at which it fits.
            var size: CGFloat = 46
            var attributes: [NSAttributedString.Key: Any] = [:]
            var height: CGFloat = 0
            repeat {
                let font = NSFont(name: "Marker Felt", size: size) ?? NSFont.systemFont(ofSize: size)
                attributes = [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
                height = (note.text as NSString).boundingRect(with: NSSize(width: box.width, height: .greatestFiniteMagnitude),
                                                              options: [.usesLineFragmentOrigin], attributes: attributes).height
                size -= 2
            } while height > box.height && size >= 14
            let drawn = NSRect(x: box.minX, y: box.midY - min(height, box.height) / 2,
                               width: box.width, height: min(height, box.height))
            (note.text as NSString).draw(with: drawn, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                         attributes: attributes)
            return true
        }
    }

    static func calendar(_ events: [DeskEvent], now: Date = Date()) -> NSImage {
        NSImage(size: NSSize(width: 384, height: 480), flipped: true) { rect in
            NSColor(hex: "#f4f2ec").setFill()
            rect.fill()
            if let picture = NSImage(contentsOf: AppResources.url("Office/calendar-picture.jpg")) {
                picture.draw(in: NSRect(x: 16, y: 16, width: 352, height: 150), from: .zero, operation: .copy,
                             fraction: 1, respectFlipped: true, hints: nil)
            }

            let calendar = Calendar.current
            let parts = calendar.dateComponents([.year, .month, .day], from: now)
            let year = parts.year ?? 2000, month = parts.month ?? 1, today = parts.day ?? 1
            let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
            let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
            let firstWeekday = calendar.firstWeekday - 1   // 0 = Sunday
            let offset = (calendar.component(.weekday, from: first) - 1 - firstWeekday + 7) % 7

            // Month and year on the red bar.
            NSColor(hex: "#c83c32").setFill()
            NSRect(x: 16, y: 172, width: 352, height: 30).fill()
            let monthFormatter = DateFormatter()
            monthFormatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
            draw(monthFormatter.string(from: now), in: NSRect(x: 16, y: 176, width: 352, height: 24),
                 size: 20, bold: true, color: .white, alignment: .center)

            let cellWidth: CGFloat = 352 / 7
            let symbols = calendar.shortWeekdaySymbols
            for i in 0..<7 {
                draw(String(symbols[(firstWeekday + i) % 7].prefix(2)), in: NSRect(x: 16 + CGFloat(i) * cellWidth, y: 206,
                     width: cellWidth, height: 18), size: 13, bold: true, color: NSColor(hex: "#6a6660"), alignment: .center)
            }

            let eventDays = Set(events.map(\.date))
            for index in 0..<42 {
                let day = index - offset + 1
                let inMonth = day >= 1 && day <= daysInMonth
                if !inMonth && index >= 35 { continue }
                let cell = NSRect(x: 16 + CGFloat(index % 7) * cellWidth, y: 226 + CGFloat(index / 7) * 28,
                                  width: cellWidth, height: 28)
                NSColor(hex: "#c6c2b8").setStroke()
                NSBezierPath(rect: cell.insetBy(dx: 1, dy: 1)).stroke()
                guard inMonth else { continue }
                draw("\(day)", in: NSRect(x: cell.minX, y: cell.minY + 5, width: cell.width, height: 20),
                     size: 15, bold: false, color: NSColor(hex: "#3a3834"), alignment: .center)
                if day == today {
                    let ring = NSBezierPath(roundedRect: NSRect(x: cell.midX - 15, y: cell.midY - 12, width: 30, height: 24),
                                            xRadius: 12, yRadius: 12)
                    ring.lineWidth = 3
                    NSColor(hex: "#d22828").setStroke()
                    ring.stroke()
                }
                if eventDays.contains(String(format: "%04d-%02d-%02d", year, month, day)) {
                    NSColor(hex: "#2860b4").setFill()
                    NSRect(x: cell.midX - 9, y: cell.maxY - 5, width: 18, height: 3).fill()
                }
            }

            // The next few events.
            let todayISO = String(format: "%04d-%02d-%02d", year, month, today)
            let dayFormatter = DateFormatter()
            dayFormatter.setLocalizedDateFormatFromTemplate("MMM d")
            for (i, event) in events.filter({ $0.date >= todayISO }).prefix(3).enumerated() {
                let parts = event.date.split(separator: "-").compactMap { Int($0) }
                let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? now
                let line = dayFormatter.string(from: date) + (event.time.isEmpty ? "" : " " + event.time) + "  " + event.title
                draw(line, in: NSRect(x: 18, y: 400 + CGFloat(i) * 22, width: 348, height: 20),
                     size: 16, bold: false, color: ink, alignment: .left)
            }
            return true
        }
    }

    private static func draw(_ text: String, in rect: NSRect, size: CGFloat, bold: Bool, color: NSColor,
                             alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
}
