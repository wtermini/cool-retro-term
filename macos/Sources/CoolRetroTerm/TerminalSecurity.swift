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
import SwiftTerm
import UniformTypeIdentifiers

/// Sits between SwiftTerm and the terminal view to apply this app's security
/// policy to things that output from programs can trigger.
///
/// Anything printed to the terminal, including a file you `cat`, a web page
/// you `curl`, or output from a remote machine over ssh, can contain escape
/// sequences. SwiftTerm 1.20 acts on two of these more trustingly than it
/// should, so this delegate:
///
/// - **Refuses clipboard reads (OSC 52 query).** SwiftTerm would otherwise
///   send the clipboard's contents back to whatever program asked, silently,
///   which could leak a password you just copied. Clipboard *writes* are still
///   allowed, so copying from vim or tmux, including over ssh, keeps working.
/// - **Checks links before opening them.** Cmd-clicking a link opens web and
///   mail links normally; files open only if they are documents, otherwise
///   they're shown in Finder; anything else asks first and shows the real
///   destination, since a link's text can differ from where it points.
///
/// Every other callback is passed straight to the terminal view.
final class TerminalSecurityDelegate: TerminalViewDelegate {
    private weak var view: LocalProcessTerminalView?

    init(view: LocalProcessTerminalView) {
        self.view = view
    }

    // MARK: Policy

    func clipboardRead(source: TerminalView) -> Data? {
        nil
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        withView { $0.clipboardCopy(source: source, content: content) }
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        onMain { LinkOpener.open(link, from: source.window) }
    }

    // MARK: Pass-through

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        withView { $0.sizeChanged(source: source, newCols: newCols, newRows: newRows) }
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        withView { $0.setTerminalTitle(source: source, title: title) }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        withView { $0.hostCurrentDirectoryUpdate(source: source, directory: directory) }
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        withView { $0.send(source: source, data: data) }
    }

    func scrolled(source: TerminalView, position: Double) {
        withView { $0.scrolled(source: source, position: position) }
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        withView { $0.rangeChanged(source: source, startY: startY, endY: endY) }
    }

    func bell(source: TerminalView) {
        NSSound.beep()
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    private func withView(_ body: @escaping @MainActor (LocalProcessTerminalView) -> Void) {
        let target = view
        onMain {
            if let target { body(target) }
        }
    }

    /// SwiftTerm calls its delegate on the main thread; this keeps the order
    /// of calls (important for `send`) and stays safe if that ever changes.
    private func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(body) }
        }
    }
}

/// Decides what to do with a link the user Cmd-clicked in the terminal.
@MainActor
enum LinkOpener {
    static func open(_ link: String, from window: NSWindow?) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return
        }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https", "mailto":
                NSWorkspace.shared.open(url)
            case "file":
                openFile(url)
            default:
                confirm(url, from: window)
            }
            return
        }

        // A plain path, possibly with a ":line" or ":line:column" suffix.
        var path = (trimmed as NSString).expandingTildeInPath
        if !FileManager.default.fileExists(atPath: path),
           let range = path.range(of: #":[0-9]+(?::[0-9]+)?$"#, options: .regularExpression) {
            path = String(path[..<range.lowerBound])
        }
        if FileManager.default.fileExists(atPath: path) {
            openFile(URL(fileURLWithPath: path))
        }
    }

    /// Opens documents with their default app. Applications, scripts,
    /// installers and anything else that could run code are revealed in
    /// Finder instead.
    private static func openFile(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        let isDocument = !isDirectory.boolValue
            && !FileManager.default.isExecutableFile(atPath: url.path)
            && [UTType.text, .sourceCode, .image, .pdf, .audiovisualContent, .json, .xml]
                .contains { type?.conforms(to: $0) == true }
            && type?.conforms(to: .script) != true
            && type?.conforms(to: .shellScript) != true

        if isDocument {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Other schemes can launch apps, so show where the link really goes.
    private static func confirm(_ url: URL, from window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Open this link?"
        alert.informativeText = "A program running in the terminal printed a link to:\n\n\(url.absoluteString)\n\n"
            + "Only open it if you trust where it came from."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }
}
