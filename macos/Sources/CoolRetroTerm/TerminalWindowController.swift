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

/// A terminal window with its own tab bar. Each tab is a TerminalSession;
/// only the selected one is in the window, so background tabs don't render.
final class TerminalWindowController: NSWindowController, NSWindowDelegate, TabBarViewDelegate {
    private(set) var sessions: [TerminalSession] = []
    private(set) var selectedIndex = 0
    var onClose: ((TerminalWindowController) -> Void)?

    private let container = NSView()
    private let tabBar = TabBarView(frame: NSRect(x: 0, y: 0, width: 960, height: TabBarView.height))
    private let tabBarAccessory = NSTitlebarAccessoryViewController()
    private var appearanceObserver: NSObjectProtocol?

    var currentSession: TerminalSession? {
        sessions.indices.contains(selectedIndex) ? sessions[selectedIndex] : nil
    }

    init() {
        let frame = NSRect(x: 0, y: 0, width: 960, height: 640)
        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Cool Retro Term"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.titlebarAppearsTransparent = true
        // This window draws its own tabs instead of using system tabbing.
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.minSize = NSSize(width: 320, height: 200)
        window.isReleasedWhenClosed = false

        container.frame = frame
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = container

        super.init(window: window)

        window.delegate = self
        tabBar.delegate = self
        tabBarAccessory.view = tabBar
        tabBarAccessory.layoutAttribute = .bottom
        window.addTitlebarAccessoryViewController(tabBarAccessory)

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .terminalAppearanceDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
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

    // MARK: Sessions

    /// Opens a new tab after the current one and starts its shell.
    @discardableResult
    func addSession() -> TerminalSession {
        let session = TerminalSession(frame: container.bounds)
        session.onChange = { [weak self] in self?.refresh() }
        session.onExit = { [weak self, weak session] in
            guard let self, let session else { return }
            self.close(session)
        }
        let index = sessions.isEmpty ? 0 : selectedIndex + 1
        sessions.insert(session, at: index)
        select(index)
        session.start()
        return session
    }

    func select(_ index: Int) {
        guard sessions.indices.contains(index) else { return }
        if let current = currentSession, current !== sessions[index] {
            current.crtView.removeFromSuperview()
        }
        selectedIndex = index
        let view = sessions[index].crtView
        if view.superview !== container {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        window?.makeFirstResponder(view.terminal)
        refresh()
    }

    func select(number: Int) {
        // Cmd-9 always goes to the last tab, as in browsers.
        select(number == 9 ? sessions.count - 1 : number - 1)
    }

    func selectNext() { if !sessions.isEmpty { select((selectedIndex + 1) % sessions.count) } }
    func selectPrevious() { if !sessions.isEmpty { select((selectedIndex - 1 + sessions.count) % sessions.count) } }

    func close(_ session: TerminalSession) {
        guard let index = sessions.firstIndex(where: { $0 === session }) else { return }
        let wasSelected = index == selectedIndex
        session.terminate()
        session.crtView.removeFromSuperview()
        sessions.remove(at: index)
        if sessions.isEmpty {
            window?.close()
            return
        }
        if index < selectedIndex {
            selectedIndex -= 1
            refresh()
        } else if wasSelected {
            // Move to the neighbour, as browsers do.
            selectedIndex = min(index, sessions.count - 1)
            select(selectedIndex)
        } else {
            refresh()
        }
    }

    func closeCurrentTab() {
        if let session = currentSession { close(session) }
    }

    func closeOtherTabs(than keep: TerminalSession) {
        for session in sessions where session !== keep { close(session) }
    }

    /// Renames the current tab in place in the tab bar, or with a sheet when
    /// the bar is hidden (a single tab).
    func renameCurrentTab() {
        if !tabBarAccessory.isHidden {
            tabBar.beginEditing(selectedIndex)
            return
        }
        guard let window, let session = currentSession else { return }
        let field = NSTextField(string: session.customTitle ?? session.title)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        alert.informativeText = "Leave empty, or choose Automatic, to show the title set by the program running in the tab."
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Automatic")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self, weak session] response in
            MainActor.assumeIsolated {
                switch response {
                case .alertFirstButtonReturn: session?.setCustomTitle(field.stringValue)
                case .alertThirdButtonReturn: session?.setCustomTitle(nil)
                default: break
                }
                if let terminal = self?.currentSession?.crtView.terminal {
                    self?.window?.makeFirstResponder(terminal)
                }
            }
        }
    }

    /// Brings the tab bar, window title and proxy icon up to date.
    private func refresh() {
        tabBar.items = sessions.map {
            TabBarView.Item(title: $0.title, color: $0.tabColor, editableTitle: $0.customTitle ?? "")
        }
        tabBar.selectedIndex = selectedIndex
        tabBar.accentColor = NSColor(rgb: ProfileStore.shared.current.effectiveFontColor)
        tabBarAccessory.isHidden = sessions.count < 2 && !ProfileStore.shared.alwaysShowTabBar
        if let session = currentSession {
            window?.title = session.title
            window?.representedURL = session.directory
        }
    }

    // MARK: TabBarViewDelegate

    func tabBar(_ tabBar: TabBarView, didSelect index: Int) {
        select(index)
    }

    func tabBar(_ tabBar: TabBarView, didClose index: Int) {
        if sessions.indices.contains(index) { close(sessions[index]) }
    }

    func tabBar(_ tabBar: TabBarView, didMoveFrom source: Int, to destination: Int) {
        guard sessions.indices.contains(source), sessions.indices.contains(destination) else { return }
        let selected = currentSession
        sessions.insert(sessions.remove(at: source), at: destination)
        selectedIndex = sessions.firstIndex { $0 === selected } ?? 0
        refresh()
    }

    func tabBar(_ tabBar: TabBarView, didRename index: Int, to title: String?) {
        if sessions.indices.contains(index) { sessions[index].setCustomTitle(title) }
    }

    func tabBarDidRequestNewTab(_ tabBar: TabBarView) {
        addSession()
    }

    func tabBar(_ tabBar: TabBarView, menuFor index: Int) -> NSMenu? {
        guard sessions.indices.contains(index) else { return nil }
        let session = sessions[index]
        let menu = NSMenu()

        let rename = NSMenuItem(title: "Rename Tab", action: #selector(menuRename(_:)), keyEquivalent: "")
        rename.representedObject = session
        rename.target = self
        menu.addItem(rename)

        let colors = NSMenu()
        let none = NSMenuItem(title: "None", action: #selector(menuColor(_:)), keyEquivalent: "")
        none.representedObject = TabColorChoice(session: session, name: nil)
        none.target = self
        none.state = session.tabColorName == nil ? .on : .off
        colors.addItem(none)
        colors.addItem(.separator())
        for (name, color) in TabColorPalette.colors {
            let item = NSMenuItem(title: name, action: #selector(menuColor(_:)), keyEquivalent: "")
            item.representedObject = TabColorChoice(session: session, name: name)
            item.image = TabColorPalette.swatch(color)
            item.target = self
            item.state = session.tabColorName == name ? .on : .off
            colors.addItem(item)
        }
        let colorItem = NSMenuItem(title: "Tab Color", action: nil, keyEquivalent: "")
        colorItem.submenu = colors
        menu.addItem(colorItem)

        menu.addItem(.separator())
        let close = NSMenuItem(title: "Close Tab", action: #selector(menuClose(_:)), keyEquivalent: "")
        close.representedObject = session
        close.target = self
        menu.addItem(close)
        if sessions.count > 1 {
            let others = NSMenuItem(title: "Close Other Tabs", action: #selector(menuCloseOthers(_:)), keyEquivalent: "")
            others.representedObject = session
            others.target = self
            menu.addItem(others)
        }
        return menu
    }

    @objc private func menuRename(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? TerminalSession,
              let index = sessions.firstIndex(where: { $0 === session }) else { return }
        select(index)
        renameCurrentTab()
    }

    @objc private func menuColor(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? TabColorChoice else { return }
        choice.session?.setTabColor(choice.name.flatMap(TabColorPalette.color(named:)), name: choice.name)
    }

    @objc private func menuClose(_ sender: NSMenuItem) {
        if let session = sender.representedObject as? TerminalSession { close(session) }
    }

    @objc private func menuCloseOthers(_ sender: NSMenuItem) {
        if let session = sender.representedObject as? TerminalSession { closeOtherTabs(than: session) }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        for session in sessions { session.terminate() }
        sessions.removeAll()
        onClose?(self)
    }
}

/// A colour choice from a tab's right-click menu.
private final class TabColorChoice: NSObject {
    weak var session: TerminalSession?
    let name: String?

    init(session: TerminalSession, name: String?) {
        self.session = session
        self.name = name
    }
}
