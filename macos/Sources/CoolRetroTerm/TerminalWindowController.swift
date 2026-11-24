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

/// One terminal window (or tab) running the user's login shell.
final class TerminalWindowController: NSWindowController, NSWindowDelegate, LocalProcessTerminalViewDelegate {
    let crtView: CRTTerminalView
    var onClose: ((TerminalWindowController) -> Void)?

    /// Tab colour picked from the menu (name from TabColorPalette, or "Custom").
    private(set) var tabColorName: String?
    private var userTabColor: NSColor?
    /// Tab colour set by a program with the iTerm2 escape sequence.
    private var programTabColor: NSColor?
    private var programTabRGB: [Double] = [0, 0, 0]
    private var appearanceObserver: NSObjectProtocol?

    init() {
        let store = ProfileStore.shared
        let frame = NSRect(x: 0, y: 0, width: 960, height: 640)
        crtView = CRTTerminalView(frame: frame, profile: store.current,
                                  effectsEnabled: store.effectsEnabled, zoom: store.zoom)

        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Cool Retro Term"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.titlebarAppearsTransparent = true
        window.tabbingIdentifier = "CoolRetroTerm"
        window.tabbingMode = .automatic
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.minSize = NSSize(width: 320, height: 200)
        window.contentView = crtView
        window.initialFirstResponder = crtView.terminal
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        crtView.terminal.processDelegate = self
        crtView.terminal.terminal.registerOscHandler(code: 6) { [weak self] data in
            guard let sequence = TabColorSequence(data) else { return }
            Task { @MainActor [weak self] in self?.applyProgramTabColor(sequence) }
        }
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .terminalAppearanceDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            let store = ProfileStore.shared
            self?.crtView.update(profile: store.current, effectsEnabled: store.effectsEnabled, zoom: store.zoom)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    /// Starts the user's login shell in their home directory, or the custom
    /// command set in the Qt app's settings.
    func startShell() {
        let shell = Self.loginShell
        var executable = shell
        var arguments: [String] = []
        var execName: String? = "-" + (shell as NSString).lastPathComponent
        if let command = ProfileStore.shared.customCommand, let program = Self.resolve(command[0]) {
            executable = program
            arguments = Array(command.dropFirst())
            execName = nil
        }
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "cool-retro-term"
        // Apps launched from Finder or the Dock get no LANG, which makes
        // shells and tools fall back to ASCII and garble Unicode output.
        if environment["LANG"] == nil && environment["LC_ALL"] == nil && environment["LC_CTYPE"] == nil {
            environment["LANG"] = Self.utf8Locale
        }
        // The CRT_* debug switches are for this app only; don't pass them on.
        for key in environment.keys where key.hasPrefix("CRT_") {
            environment.removeValue(forKey: key)
        }
        crtView.terminal.startProcess(
            executable: executable,
            args: arguments,
            environment: environment.map { "\($0.key)=\($0.value)" },
            execName: execName,
            currentDirectory: NSHomeDirectory())

        // Debug aid for CI screenshots: type a command once the shell is up.
        if let command = ProcessInfo.processInfo.environment["CRT_SNAPSHOT_COMMAND"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.crtView.terminal.send(data: ArraySlice(Array((command + "\n").utf8)))
            }
        }
    }

    /// Finds a program on the PATH, as the Qt app's shell launching does.
    private static func resolve(_ program: String) -> String? {
        let expanded = (program as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return FileManager.default.isExecutableFile(atPath: expanded) ? expanded : nil
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let searchPath = path + ":/usr/local/bin:/opt/homebrew/bin"
        for directory in searchPath.split(separator: ":") {
            let candidate = "\(directory)/\(expanded)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private static var loginShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    private static var utf8Locale: String {
        let locale = Locale.current
        if let language = locale.language.languageCode?.identifier,
           let region = locale.region?.identifier {
            return "\(language)_\(region).UTF-8"
        }
        return "en_US.UTF-8"
    }

    // MARK: Tab colour

    var tabColor: NSColor? { userTabColor ?? programTabColor }

    func setTabColor(_ color: NSColor?, name: String?) {
        userTabColor = color
        tabColorName = color == nil ? nil : name
        updateTabAppearance()
    }

    private func applyProgramTabColor(_ sequence: TabColorSequence) {
        switch sequence {
        case .reset:
            programTabRGB = [0, 0, 0]
            programTabColor = nil
        case .channel(let index, let value):
            programTabRGB[index] = value
            programTabColor = NSColor(srgbRed: programTabRGB[0], green: programTabRGB[1],
                                      blue: programTabRGB[2], alpha: 1)
        }
        updateTabAppearance()
    }

    /// Shows the colour as a dot and coloured title in the tab, and as a
    /// tint on the CRT bezel.
    func updateTabAppearance() {
        guard let window else { return }
        if let color = tabColor {
            window.tab.attributedTitle = NSAttributedString(
                string: window.title,
                attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
            window.tab.accessoryView = TabColorDot(color: color)
        } else {
            window.tab.attributedTitle = nil
            window.tab.accessoryView = nil
        }
        crtView.accentColor = tabColor
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        crtView.terminal.terminate()
        onClose?(self)
    }

    // MARK: LocalProcessTerminalViewDelegate
    //
    // SwiftTerm's delegate protocol isn't actor-isolated, so these hop to the
    // main actor before touching the window.

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in
            self?.window?.title = title.isEmpty ? "Cool Retro Term" : title
            self?.updateTabAppearance()
        }
    }

    /// Shells that report their directory (OSC 7, which macOS's zsh does by
    /// default) get a proxy icon in the title bar.
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        let url: URL? = directory.map { value in
            if let parsed = URL(string: value), parsed.isFileURL {
                return URL(fileURLWithPath: parsed.path)
            }
            return URL(fileURLWithPath: value)
        }
        Task { @MainActor [weak self] in
            self?.window?.representedURL = url
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            self?.window?.close()
        }
    }
}
