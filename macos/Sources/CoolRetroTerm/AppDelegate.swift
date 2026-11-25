import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    private var controllers: [TerminalWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load settings and fonts before any window exists.
        _ = ProfileStore.shared
        _ = FontLibrary.shared
        NSApp.mainMenu = buildMainMenu()
        installTabShortcuts()
        let options = LaunchOptions.current
        if let name = options.profile {
            if ProfileStore.shared.profiles.contains(where: { $0.name == name }) {
                ProfileStore.shared.select(name)
            } else {
                FileHandle.standardError.write(Data("cool-retro-term: no profile named \"\(name)\"\n".utf8))
            }
        }
        let controller = openWindow(command: options.command, directory: options.workdir)
        if options.fullscreen {
            controller.window?.toggleFullScreen(nil)
        }
        // CI aid: save images of the Settings panes, then quit.
        if let directory = CIHooks.value("CRT_SETTINGS_SNAPSHOT_DIR") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                SettingsWindowController.shared.writeSnapshots(to: URL(fileURLWithPath: directory)) {
                    NSApp.terminate(nil)
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Clicking the Dock icon with no windows open starts a new session, as in Terminal.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Windows and tabs

    @discardableResult
    private func openWindow(command: [String]? = nil, directory: String? = nil) -> TerminalWindowController {
        let controller = TerminalWindowController()
        controller.onClose = { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
        guard let window = controller.window else { return controller }

        if let last = controllers.dropLast().last?.window {
            window.setFrame(last.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY)))
        } else {
            window.center()
        }
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        controller.addSession(command: command, directory: directory)
        return controller
    }

    @objc func newWindow(_ sender: Any?) {
        openWindow()
    }

    @MainActor @objc func newTab(_ sender: Any?) {
        if let controller = frontController {
            controller.addSession()
        } else {
            openWindow()
        }
    }

    @MainActor @objc func closeTab(_ sender: Any?) {
        frontController?.closeCurrentTab()
    }

    @MainActor @objc func selectNextTab(_ sender: Any?) { frontController?.selectNext() }
    @MainActor @objc func selectPreviousTab(_ sender: Any?) { frontController?.selectPrevious() }

    @MainActor @objc func toggleAlwaysShowTabBar(_ sender: Any?) {
        ProfileStore.shared.alwaysShowTabBar.toggle()
    }

    /// Cmd-1 to Cmd-9 switch tabs; Shift- and Control-Return insert new lines.
    private func installTabShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { UserActivity.note() }   // ends office mode's idle orbit
            let shiftReturnHandled: Bool = MainActor.assumeIsolated {
                (event.window?.firstResponder as? RetroTerminalView)?.handleModifiedReturn(event) ?? false
            }
            if shiftReturnHandled { return nil }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  let characters = event.charactersIgnoringModifiers,
                  let number = Int(characters), (1...9).contains(number) else { return event }
            let handled: Bool = MainActor.assumeIsolated {
                guard let controller = self?.frontController else { return false }
                controller.select(number: number)
                return true
            }
            return handled ? nil : event
        }
    }

    // MARK: Tab colour

    private weak var colorPanelTarget: TerminalSession?

    @MainActor private var frontController: TerminalWindowController? {
        let window = NSApp.mainWindow ?? NSApp.keyWindow
        return controllers.first { $0.window === window }
    }

    @MainActor @objc func renameTab(_ sender: Any?) {
        frontController?.renameCurrentTab()
    }

    @MainActor @objc func chooseTabColor(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String
        frontController?.currentSession?.setTabColor(name.flatMap(TabColorPalette.color(named:)), name: name)
    }

    @MainActor @objc func chooseCustomTabColor(_ sender: Any?) {
        guard let session = frontController?.currentSession else { return }
        colorPanelTarget = session
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = session.tabColor ?? .systemBlue
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @MainActor @objc func colorPanelChanged(_ sender: NSColorPanel) {
        colorPanelTarget?.setTabColor(sender.color, name: "Custom")
    }

    // MARK: Appearance

    @objc func selectProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        ProfileStore.shared.select(name)
    }

    @objc func toggleEffects(_ sender: Any?) {
        ProfileStore.shared.effectsEnabled.toggle()
    }

    @objc func chooseOfficeScene(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let scene = OfficeScene(rawValue: raw) else { return }
        ProfileStore.shared.officeScene = scene
    }

    @objc func chooseOfficeMonitor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let monitor = OfficeMonitor(rawValue: raw) else { return }
        ProfileStore.shared.officeMonitor = monitor
    }

    @objc func chooseOfficeZoom(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let zoom = OfficeZoom(rawValue: raw) else { return }
        ProfileStore.shared.officeZoom = zoom
    }

    @objc func chooseOfficeIdleOrbit(_ sender: NSMenuItem) {
        ProfileStore.shared.officeIdleOrbit = sender.tag
    }

    @objc func chooseOfficeIdleOrbitSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let speed = OfficeOrbitSpeed(rawValue: raw) else { return }
        ProfileStore.shared.officeIdleOrbitSpeed = speed
    }

    @objc func toggleOfficeStickyNotes(_ sender: Any?) {
        ProfileStore.shared.officeStickyNotes.toggle()
    }

    @objc func toggleOffice3D(_ sender: Any?) {
        ProfileStore.shared.office3D.toggle()
    }

    @objc func toggleOfficeLookAround(_ sender: Any?) {
        ProfileStore.shared.officeLookAround.toggle()
    }

    @MainActor @objc func editOfficeDesk(_ sender: Any?) {
        OfficeDeskWindowController.shared.show(focusing: "")
    }

    /// Copies the command that registers the office desk's MCP server with Claude Code.
    @objc func copyMCPCommand(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(OfficeDesk.mcpCommand, forType: .string)
    }

    @MainActor @objc func resetOfficeView(_ sender: Any?) {
        frontController?.currentSession?.crtView.resetOfficeView()
    }

    @objc func chooseCursorShape(_ sender: NSMenuItem) {
        ProfileStore.shared.cursorShape = sender.tag
    }

    /// The profile's blinking cursor setting (shared with the Qt app).
    @objc func toggleBlinkingCursor(_ sender: Any?) {
        ProfileStore.shared.updateCurrent { $0.blinkingCursor.toggle() }
    }

    // Same steps as the Qt app's font scaling.
    @objc func makeTextBigger(_ sender: Any?) { ProfileStore.shared.setZoom(ProfileStore.shared.zoom + 0.05) }
    @objc func makeTextSmaller(_ sender: Any?) { ProfileStore.shared.setZoom(ProfileStore.shared.zoom - 0.05) }
    @objc func makeTextDefaultSize(_ sender: Any?) { ProfileStore.shared.setZoom(1.0) }

    /// Pick up changes made in the Qt app while this one was in the background.
    func applicationDidBecomeActive(_ notification: Notification) {
        ProfileStore.shared.reload()
        SecureKeyboardEntry.shared.appDidBecomeActive()
    }

    func applicationWillResignActive(_ notification: Notification) {
        SecureKeyboardEntry.shared.appWillResignActive()
    }

    @MainActor @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @MainActor @objc func toggleSecureKeyboardEntry(_ sender: Any?) {
        SecureKeyboardEntry.shared.isEnabled.toggle()
    }

    // MARK: NSMenuDelegate

    /// Rebuilds View ▸ Profile, since the Qt app may have added profiles.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let store = ProfileStore.shared
        for profile in store.builtinProfiles {
            menu.addItem(profileItem(profile))
        }
        if !store.customProfiles.isEmpty {
            menu.addItem(.separator())
            for profile in store.customProfiles {
                menu.addItem(profileItem(profile))
            }
        }
        if store.current.name.isEmpty {
            menu.addItem(.separator())
            let edited = NSMenuItem(title: "Edited in Qt app", action: nil, keyEquivalent: "")
            edited.state = .on
            edited.isEnabled = false
            menu.addItem(edited)
        }
    }

    private func profileItem(_ profile: Profile) -> NSMenuItem {
        let entry = item(profile.name, #selector(selectProfile(_:)))
        entry.representedObject = profile.name
        return entry
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectProfile(_:)):
            let name = ProfileStore.shared.current.name
            menuItem.state = !name.isEmpty && (menuItem.representedObject as? String) == name ? .on : .off
        case #selector(renameTab(_:)), #selector(closeTab(_:)):
            return frontController != nil
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)):
            return (frontController?.sessions.count ?? 0) > 1
        case #selector(toggleAlwaysShowTabBar(_:)):
            menuItem.state = ProfileStore.shared.alwaysShowTabBar ? .on : .off
        case #selector(chooseTabColor(_:)):
            menuItem.state = (menuItem.representedObject as? String) == frontController?.currentSession?.tabColorName ? .on : .off
            return frontController != nil
        case #selector(chooseCustomTabColor(_:)):
            menuItem.state = frontController?.currentSession?.tabColorName == "Custom" ? .on : .off
            return frontController != nil
        case #selector(toggleEffects(_:)):
            menuItem.state = ProfileStore.shared.effectsEnabled ? .on : .off
        case #selector(chooseOfficeScene(_:)):
            menuItem.state = (menuItem.representedObject as? String) == ProfileStore.shared.officeScene.rawValue ? .on : .off
        case #selector(chooseOfficeMonitor(_:)):
            menuItem.state = (menuItem.representedObject as? String) == ProfileStore.shared.officeMonitor.rawValue ? .on : .off
        case #selector(chooseOfficeZoom(_:)):
            menuItem.state = (menuItem.representedObject as? String) == ProfileStore.shared.officeZoom.rawValue ? .on : .off
        case #selector(chooseOfficeIdleOrbit(_:)):
            menuItem.state = menuItem.tag == ProfileStore.shared.officeIdleOrbit ? .on : .off
        case #selector(chooseOfficeIdleOrbitSpeed(_:)):
            menuItem.state = (menuItem.representedObject as? String) == ProfileStore.shared.officeIdleOrbitSpeed.rawValue ? .on : .off
            return ProfileStore.shared.officeIdleOrbit > 0
        case #selector(toggleOfficeStickyNotes(_:)):
            menuItem.state = ProfileStore.shared.officeStickyNotes ? .on : .off
        case #selector(toggleOffice3D(_:)):
            menuItem.state = ProfileStore.shared.office3D ? .on : .off
        case #selector(toggleOfficeLookAround(_:)):
            menuItem.state = ProfileStore.shared.officeLookAround ? .on : .off
            return ProfileStore.shared.office3D
        case #selector(resetOfficeView(_:)):
            return frontController != nil && ProfileStore.shared.officeScene != .off && ProfileStore.shared.office3D
        case #selector(chooseCursorShape(_:)):
            menuItem.state = menuItem.tag == ProfileStore.shared.cursorShape ? .on : .off
        case #selector(toggleBlinkingCursor(_:)):
            menuItem.state = ProfileStore.shared.current.blinkingCursor ? .on : .off
        case #selector(toggleSecureKeyboardEntry(_:)):
            menuItem.state = SecureKeyboardEntry.shared.isEnabled ? .on : .off
        default:
            break
        }
        return true
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSAttributedString(
            string: "A terminal emulator that mimics the look and feel of old cathode tube screens.\n\n"
                + "The native macOS edition of cool-retro-term by Filippo Scognamiglio, "
                + "built on SwiftTerm (MIT License).\n"
                + "Licensed under the GNU General Public License v3 or later.\n"
                + "Bundled fonts are under their own licenses; see Help ▸ Licenses.",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Cool Retro Term SE",
            .credits: credits,
        ])
    }

    /// Shows the license texts bundled in the app (GPL-3.0, third-party notices).
    @objc func showLicenses(_ sender: Any?) {
        let licenses = AppResources.url("Licenses")
        let notices = licenses.appendingPathComponent("THIRD_PARTY_NOTICES.md")
        if FileManager.default.fileExists(atPath: notices.path) {
            NSWorkspace.shared.activateFileViewerSelecting([notices])
        } else {
            NSWorkspace.shared.open(licenses)
        }
    }

    @objc func openSourceCode(_ sender: Any?) {
        if let url = URL(string: "https://github.com/Swordfish90/cool-retro-term") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Context menu

    /// The terminal's right-click menu, like the Qt app's.
    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "New Tab", action: #selector(newTab(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let profiles = NSMenu(title: "Profile")
        profiles.delegate = self
        menu.addItem(withTitle: "Profile", action: nil, keyEquivalent: "").submenu = profiles
        menu.addItem(withTitle: "CRT Effects", action: #selector(toggleEffects(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "About Cool Retro Term SE", action: #selector(showAbout(_:)), keyEquivalent: "")
        return menu
    }

    // MARK: Menu bar

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = submenu(in: main, title: "Cool Retro Term SE")
        app.addItem(item("About Cool Retro Term SE", #selector(showAbout(_:))))
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(showSettings(_:)), ","))
        app.addItem(.separator())
        app.addItem(item("Secure Keyboard Entry", #selector(toggleSecureKeyboardEntry(_:))))
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        app.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(item("Hide Cool Retro Term SE", #selector(NSApplication.hide(_:)), "h"))
        app.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit Cool Retro Term SE", #selector(NSApplication.terminate(_:)), "q"))

        let shell = submenu(in: main, title: "Shell")
        shell.addItem(item("New Window", #selector(newWindow(_:)), "n"))
        shell.addItem(item("New Tab", #selector(newTab(_:)), "t"))
        shell.addItem(.separator())
        shell.addItem(item("Rename Tab…", #selector(renameTab(_:)), "r", [.command, .shift]))
        let tabColors = NSMenu(title: "Tab Color")
        let none = item("None", #selector(chooseTabColor(_:)))
        tabColors.addItem(none)
        tabColors.addItem(.separator())
        for (name, color) in TabColorPalette.colors {
            let entry = item(name, #selector(chooseTabColor(_:)))
            entry.representedObject = name
            entry.image = TabColorPalette.swatch(color)
            tabColors.addItem(entry)
        }
        tabColors.addItem(.separator())
        tabColors.addItem(item("Custom…", #selector(chooseCustomTabColor(_:))))
        shell.addItem(withTitle: "Tab Color", action: nil, keyEquivalent: "").submenu = tabColors
        shell.addItem(.separator())
        shell.addItem(item("Close Tab", #selector(closeTab(_:)), "w"))
        shell.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]))

        let edit = submenu(in: main, title: "Edit")
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))

        let view = submenu(in: main, title: "View")
        let profiles = NSMenu(title: "Profile")
        profiles.delegate = self
        view.addItem(withTitle: "Profile", action: nil, keyEquivalent: "").submenu = profiles
        view.addItem(item("CRT Effects", #selector(toggleEffects(_:)), "e", [.command, .option]))
        view.addItem(item("Blinking Cursor", #selector(toggleBlinkingCursor(_:))))
        let shapes = NSMenu(title: "Cursor Shape")
        for (index, title) in ["Solid Block", "Underline", "Bar"].enumerated() {
            let entry = item(title, #selector(chooseCursorShape(_:)))
            entry.tag = index
            shapes.addItem(entry)
        }
        view.addItem(withTitle: "Cursor Shape", action: nil, keyEquivalent: "").submenu = shapes
        view.addItem(item("Always Show Tab Bar", #selector(toggleAlwaysShowTabBar(_:))))
        let office = NSMenu(title: "Office Mode")
        for scene in OfficeScene.allCases {
            let entry = item(scene.title, #selector(chooseOfficeScene(_:)))
            entry.representedObject = scene.rawValue
            office.addItem(entry)
        }
        office.addItem(.separator())
        for monitor in OfficeMonitor.allCases {
            let entry = item(monitor.title, #selector(chooseOfficeMonitor(_:)))
            entry.representedObject = monitor.rawValue
            office.addItem(entry)
        }
        office.addItem(.separator())
        for zoom in OfficeZoom.allCases {
            let entry = item(zoom.title, #selector(chooseOfficeZoom(_:)))
            entry.representedObject = zoom.rawValue
            office.addItem(entry)
        }
        office.addItem(.separator())
        let orbit = NSMenu(title: "Orbit When Idle")
        for minutes in [0, 1, 2, 5, 10, 15, 30] {
            let title = minutes == 0 ? "Never" : minutes == 1 ? "After 1 Minute" : "After \(minutes) Minutes"
            let entry = item(title, #selector(chooseOfficeIdleOrbit(_:)))
            entry.tag = minutes
            orbit.addItem(entry)
        }
        orbit.addItem(.separator())
        for speed in OfficeOrbitSpeed.allCases {
            let entry = item(speed.title, #selector(chooseOfficeIdleOrbitSpeed(_:)))
            entry.representedObject = speed.rawValue
            orbit.addItem(entry)
        }
        office.addItem(withTitle: "Orbit When Idle", action: nil, keyEquivalent: "").submenu = orbit
        office.addItem(item("Sticky Notes", #selector(toggleOfficeStickyNotes(_:))))
        office.addItem(item("3D Room", #selector(toggleOffice3D(_:))))
        office.addItem(item("Look Around", #selector(toggleOfficeLookAround(_:))))
        office.addItem(.separator())
        office.addItem(item("Edit Notes and Calendar…", #selector(editOfficeDesk(_:))))
        office.addItem(item("Copy Agent (MCP) Setup Command", #selector(copyMCPCommand(_:))))
        office.addItem(item("Reset View", #selector(resetOfficeView(_:))))
        view.addItem(withTitle: "Office Mode", action: nil, keyEquivalent: "").submenu = office
        view.addItem(.separator())
        view.addItem(item("Bigger", #selector(makeTextBigger(_:)), "+"))
        view.addItem(item("Smaller", #selector(makeTextSmaller(_:)), "-"))
        view.addItem(item("Default Size", #selector(makeTextDefaultSize(_:)), "0"))
        view.addItem(.separator())
        view.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))

        let window = submenu(in: main, title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(item("Show Previous Tab", #selector(selectPreviousTab(_:)), "[", [.command, .shift]))
        window.addItem(item("Show Next Tab", #selector(selectNextTab(_:)), "]", [.command, .shift]))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = window

        let help = submenu(in: main, title: "Help")
        help.addItem(item("Licenses", #selector(showLicenses(_:))))
        help.addItem(item("cool-retro-term Source Code", #selector(openSourceCode(_:))))
        NSApp.helpMenu = help

        return main
    }

    private func submenu(in menu: NSMenu, title: String) -> NSMenu {
        let submenu = NSMenu(title: title)
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
        return submenu
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "",
                      _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
