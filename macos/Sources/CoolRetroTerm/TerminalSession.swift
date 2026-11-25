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

/// One tab: a shell running in a CRT terminal view, with its title and colour.
@MainActor
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    let crtView: CRTTerminalView

    /// Called when the title, colour or directory changes.
    var onChange: (() -> Void)?
    /// Called when the shell exits.
    var onExit: (() -> Void)?

    /// Title set by the program running in the terminal (the shell, or a tool
    /// such as Claude Code naming its session), and a name the user gave the
    /// tab, which takes precedence while set.
    private(set) var programTitle = "Cool Retro Term SE"
    private(set) var customTitle: String?
    var title: String { customTitle ?? programTitle }

    /// The shell's current directory, if it reports it (OSC 7).
    private(set) var directory: URL?

    /// Tab colour picked by the user (a TabColorPalette name, or "Custom"),
    /// which takes precedence over one set by a program.
    private(set) var tabColorName: String?
    private var userTabColor: NSColor?
    private var programTabColor: NSColor?
    private var programTabRGB: [Double] = [0, 0, 0]
    var tabColor: NSColor? { userTabColor ?? programTabColor }

    private var appearanceObserver: NSObjectProtocol?

    init(frame: NSRect) {
        let store = ProfileStore.shared
        crtView = CRTTerminalView(frame: frame, profile: store.current,
                                  effectsEnabled: store.effectsEnabled, zoom: store.zoom)
        super.init()

        crtView.terminal.processDelegate = self
        crtView.terminal.terminal.registerOscHandler(code: 6) { [weak self] data in
            guard let sequence = TabColorSequence(data) else { return }
            Task { @MainActor [weak self] in self?.applyProgramTabColor(sequence) }
        }
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .terminalAppearanceDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                let store = ProfileStore.shared
                self?.crtView.update(profile: store.current, effectsEnabled: store.effectsEnabled, zoom: store.zoom)
            }
        }
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    // MARK: Process

    /// Starts the user's login shell in their home directory, or the custom
    /// command set in the Qt app's settings.
    /// - Parameters:
    ///   - command: a program and arguments to run instead (the -e option).
    ///   - directory: the starting directory (the --workdir option).
    func start(command explicitCommand: [String]? = nil, directory: String? = nil) {
        let shell = Self.loginShell
        var executable = shell
        var arguments: [String] = []
        var execName: String? = "-" + (shell as NSString).lastPathComponent
        if let command = explicitCommand ?? ProfileStore.shared.customCommand, !command.isEmpty,
           let program = Self.resolve(command[0]) {
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
            currentDirectory: directory.map { ($0 as NSString).expandingTildeInPath } ?? NSHomeDirectory())

        // Debug aid for CI screenshots: type a command once the shell is up.
        if let command = CIHooks.value("CRT_SNAPSHOT_COMMAND") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.crtView.terminal.send(data: ArraySlice(Array((command + "\n").utf8)))
            }
        }
    }

    func terminate() {
        crtView.terminal.terminate()
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

    // MARK: Title and colour

    /// Gives the tab a fixed name; nil or empty goes back to the program's title.
    func setCustomTitle(_ title: String?) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        customTitle = (trimmed?.isEmpty ?? true) ? nil : trimmed
        onChange?()
    }

    func setTabColor(_ color: NSColor?, name: String?) {
        userTabColor = color
        tabColorName = color == nil ? nil : name
        crtView.accentColor = tabColor
        onChange?()
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
        crtView.accentColor = tabColor
        onChange?()
    }

    // MARK: LocalProcessTerminalViewDelegate
    //
    // SwiftTerm's delegate protocol isn't actor-isolated, so these hop to the
    // main actor.

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        Task { @MainActor [weak self] in
            self?.crtView.terminalSizeChanged(cols: newCols, rows: newRows)
        }
    }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in
            self?.programTitle = title.isEmpty ? "Cool Retro Term SE" : title
            self?.onChange?()
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        let url: URL? = directory.map { value in
            if let parsed = URL(string: value), parsed.isFileURL {
                return URL(fileURLWithPath: parsed.path)
            }
            return URL(fileURLWithPath: value)
        }
        Task { @MainActor [weak self] in
            self?.directory = url
            self?.onChange?()
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            self?.onExit?()
        }
    }
}
