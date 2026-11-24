import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    private var controllers: [TerminalWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = FontLibrary.shared
        NSApp.mainMenu = buildMainMenu()
        openWindow(tabbedWith: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Clicking the Dock icon with no windows open starts a new session, as in Terminal.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openWindow(tabbedWith: nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Windows and tabs

    @discardableResult
    private func openWindow(tabbedWith existing: NSWindow?) -> TerminalWindowController {
        let controller = TerminalWindowController()
        controller.onClose = { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
        guard let window = controller.window else { return controller }

        if let existing {
            existing.addTabbedWindow(window, ordered: .above)
        } else if let last = controllers.dropLast().last?.window {
            window.setFrame(last.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY)))
        } else {
            window.center()
        }
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        controller.startShell()
        return controller
    }

    @objc func newWindow(_ sender: Any?) {
        openWindow(tabbedWith: nil)
    }

    @objc func newTab(_ sender: Any?) {
        openWindow(tabbedWith: NSApp.keyWindow ?? NSApp.mainWindow)
    }

    /// Called by the "+" button in the window tab bar.
    @objc func newWindowForTab(_ sender: Any?) {
        newTab(sender)
    }

    // MARK: Appearance

    @objc func selectProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        ProfileStore.shared.select(name)
    }

    @objc func toggleEffects(_ sender: Any?) {
        ProfileStore.shared.effectsEnabled.toggle()
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
        case #selector(toggleEffects(_:)):
            menuItem.state = ProfileStore.shared.effectsEnabled ? .on : .off
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
                + "Native macOS front end, built on SwiftTerm (MIT License).\n"
                + "Licensed under the GNU General Public License v3 or later.\n"
                + "Bundled fonts are under their own licenses; see Help ▸ Licenses.",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Cool Retro Term",
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

    // MARK: Menu bar

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = submenu(in: main, title: "Cool Retro Term")
        app.addItem(item("About Cool Retro Term", #selector(showAbout(_:))))
        app.addItem(.separator())
        app.addItem(item("Secure Keyboard Entry", #selector(toggleSecureKeyboardEntry(_:))))
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        app.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(item("Hide Cool Retro Term", #selector(NSApplication.hide(_:)), "h"))
        app.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit Cool Retro Term", #selector(NSApplication.terminate(_:)), "q"))

        let shell = submenu(in: main, title: "Shell")
        shell.addItem(item("New Window", #selector(newWindow(_:)), "n"))
        shell.addItem(item("New Tab", #selector(newTab(_:)), "t"))
        shell.addItem(.separator())
        shell.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))

        let edit = submenu(in: main, title: "Edit")
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))

        let view = submenu(in: main, title: "View")
        let profiles = NSMenu(title: "Profile")
        profiles.delegate = self
        view.addItem(withTitle: "Profile", action: nil, keyEquivalent: "").submenu = profiles
        view.addItem(item("CRT Effects", #selector(toggleEffects(_:)), "e", [.command, .option]))
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
