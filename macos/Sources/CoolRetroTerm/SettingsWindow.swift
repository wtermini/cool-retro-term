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
import SwiftUI
import UniformTypeIdentifiers

/// The Settings window (Cool Retro Term SE ▸ Settings…, Cmd-Comma), laid out
/// like the Mac's own apps: a toolbar of panes, the window titled after the
/// open pane and sized to fit it, and the last pane remembered.
///
/// Profile and effect changes edit the same shared settings as the Qt app's
/// settings dialog and apply to every window as you make them.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private enum Pane: String, CaseIterable {
        case general = "General"
        case profiles = "Profiles"
        case text = "Text"
        case effects = "Effects"
        case performance = "Performance"

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .profiles: return "paintpalette"
            case .text: return "textformat"
            case .effects: return "tv"
            case .performance: return "gauge.with.dots.needle.67percent"
            }
        }
    }

    private let tabs = NSTabViewController()
    private let model = SettingsModel()

    private init() {
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)

        for pane in Pane.allCases {
            let hosting = NSHostingController(rootView: Self.view(for: pane, model: model))
            hosting.sizingOptions = .preferredContentSize
            hosting.title = pane.rawValue
            let item = NSTabViewItem(viewController: hosting)
            item.label = pane.rawValue
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.rawValue)
            tabs.addTabViewItem(item)
        }

        let saved = UserDefaults.standard.string(forKey: "settingsPane")
        tabs.selectedTabViewItemIndex = Pane.allCases.firstIndex { $0.rawValue == saved } ?? 0
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// For checking the layout in CI: saves a PNG of each pane into the
    /// directory, then calls `done`.
    func writeSnapshots(to directory: URL, done: @escaping () -> Void) {
        show()
        func capture(_ index: Int) {
            guard index < Pane.allCases.count else {
                done()
                return
            }
            tabs.selectedTabViewItemIndex = index
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, let view = self.window?.contentView else { return }
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let url = directory.appendingPathComponent("Settings-\(Pane.allCases[index].rawValue).png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                    NSLog("cool-retro-term: wrote %@", url.path)
                }
                capture(index + 1)
            }
        }
        capture(0)
    }

    func windowWillClose(_ notification: Notification) {
        let index = tabs.selectedTabViewItemIndex
        if Pane.allCases.indices.contains(index) {
            UserDefaults.standard.set(Pane.allCases[index].rawValue, forKey: "settingsPane")
        }
    }

    private static func view(for pane: Pane, model: SettingsModel) -> AnyView {
        switch pane {
        case .general: return AnyView(GeneralSettings(model: model).frame(width: 540, height: 600))
        case .profiles: return AnyView(ProfilesSettings(model: model).frame(width: 540, height: 700))
        case .text: return AnyView(TextSettings(model: model).frame(width: 540, height: 370))
        case .effects: return AnyView(EffectsSettings(model: model).frame(width: 540, height: 740))
        case .performance: return AnyView(PerformanceSettings(model: model).frame(width: 540, height: 300))
        }
    }
}

// MARK: - Model

/// Bridges ProfileStore to SwiftUI and refreshes the views when the
/// settings change (from here, the menus, or the Qt app).
@MainActor
final class SettingsModel: ObservableObject {
    private var observer: NSObjectProtocol?
    private var store: ProfileStore { .shared }

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .terminalAppearanceDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var profile: Profile { store.current }
    var builtinNames: [String] { store.builtinProfiles.map(\.name) }
    var customNames: [String] { store.customProfiles.map(\.name) }

    // Profile values

    func number(_ keyPath: WritableKeyPath<Profile, Double>) -> Binding<Double> {
        Binding(get: { ProfileStore.shared.current[keyPath: keyPath] },
                set: { value in ProfileStore.shared.updateCurrent { $0[keyPath: keyPath] = value } })
    }

    func color(_ keyPath: WritableKeyPath<Profile, String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: Self.nsColor(hex: ProfileStore.shared.current[keyPath: keyPath])) },
            set: { value in
                let hex = Self.hex(NSColor(value))
                ProfileStore.shared.updateCurrent { $0[keyPath: keyPath] = hex }
            })
    }

    func flag(_ keyPath: WritableKeyPath<Profile, Bool>) -> Binding<Bool> {
        Binding(get: { ProfileStore.shared.current[keyPath: keyPath] },
                set: { value in ProfileStore.shared.updateCurrent { $0[keyPath: keyPath] = value } })
    }

    // The Qt app's performance settings.
    var effectsFrameSkip: Binding<Int> {
        Binding(get: { ProfileStore.shared.effectsFrameSkip }, set: { ProfileStore.shared.setEffectsFrameSkip($0) })
    }
    var windowScaling: Binding<Double> {
        Binding(get: { ProfileStore.shared.windowScaling }, set: { ProfileStore.shared.setWindowScaling($0) })
    }
    var bloomQuality: Binding<Double> {
        Binding(get: { ProfileStore.shared.bloomQuality }, set: { ProfileStore.shared.setBloomQuality($0) })
    }
    var burnInQuality: Binding<Double> {
        Binding(get: { ProfileStore.shared.burnInQuality }, set: { ProfileStore.shared.setBurnInQuality($0) })
    }
    var officeScene: Binding<OfficeScene> {
        Binding(get: { ProfileStore.shared.officeScene }, set: { ProfileStore.shared.officeScene = $0 })
    }
    var cursorShape: Binding<Int> {
        Binding(get: { ProfileStore.shared.cursorShape }, set: { ProfileStore.shared.cursorShape = $0 })
    }
    var pauseEffectsWhenIdle: Binding<Bool> {
        Binding(get: { ProfileStore.shared.pauseEffectsWhenIdle }, set: { ProfileStore.shared.pauseEffectsWhenIdle = $0 })
    }
    var showTerminalSize: Binding<Bool> {
        Binding(get: { ProfileStore.shared.showTerminalSize }, set: { ProfileStore.shared.setShowTerminalSize($0) })
    }

    // Import and export, with the Qt app's file format.
    func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a profile exported from Cool Retro Term SE."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProfileStore.shared.importProfile(from: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func exportProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let name = ProfileStore.shared.current.name
        panel.nameFieldStringValue = (name.isEmpty ? "Custom" : name) + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProfileStore.shared.exportProfile(ProfileStore.shared.current, to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    var rasterization: Binding<Int> {
        Binding(get: { ProfileStore.shared.current.rasterization },
                set: { value in ProfileStore.shared.updateCurrent { $0.rasterization = value } })
    }

    /// "bundled:<id>" or "system:<family>".
    var font: Binding<String> {
        Binding(
            get: {
                let p = ProfileStore.shared.current
                return (p.fontSource == 1 ? "system:" : "bundled:") + p.fontName
            },
            set: { value in
                let isSystem = value.hasPrefix("system:")
                let name = String(value.drop(while: { $0 != ":" }).dropFirst())
                ProfileStore.shared.updateCurrent {
                    $0.fontSource = isSystem ? 1 : 0
                    $0.fontName = name
                }
            })
    }

    var profileName: Binding<String> {
        Binding(get: { ProfileStore.shared.current.name },
                set: { name in if !name.isEmpty { ProfileStore.shared.select(name) } })
    }

    var zoom: Binding<Double> {
        Binding(get: { ProfileStore.shared.zoom }, set: { ProfileStore.shared.setZoom($0) })
    }

    func save(as name: String) { store.saveCurrent(as: name) }
    func deleteCurrentProfile() { store.deleteCustomProfile(store.current.name) }
    var canDeleteCurrent: Bool { !profile.name.isEmpty && !store.isBuiltin(profile.name) }

    // App preferences

    var effectsEnabled: Binding<Bool> {
        Binding(get: { ProfileStore.shared.effectsEnabled }, set: { ProfileStore.shared.effectsEnabled = $0 })
    }
    var optionAsMeta: Binding<Bool> {
        Binding(get: { ProfileStore.shared.optionAsMeta }, set: { ProfileStore.shared.optionAsMeta = $0 })
    }
    var newLineKeys: Binding<Bool> {
        Binding(get: { ProfileStore.shared.newLineKeys }, set: { ProfileStore.shared.newLineKeys = $0 })
    }
    var alwaysShowTabBar: Binding<Bool> {
        Binding(get: { ProfileStore.shared.alwaysShowTabBar }, set: { ProfileStore.shared.alwaysShowTabBar = $0 })
    }
    var tabBarInFullScreen: Binding<Bool> {
        Binding(get: { ProfileStore.shared.tabBarInFullScreen }, set: { ProfileStore.shared.tabBarInFullScreen = $0 })
    }
    var secureKeyboardEntry: Binding<Bool> {
        Binding(get: { MainActor.assumeIsolated { SecureKeyboardEntry.shared.isEnabled } },
                set: { [weak self] value in
                    MainActor.assumeIsolated {
                        SecureKeyboardEntry.shared.isEnabled = value
                        self?.objectWillChange.send()
                    }
                })
    }

    var customCommandEnabled: Binding<Bool> {
        Binding(get: { ProfileStore.shared.customCommandSetting.enabled },
                set: { [weak self] value in
                    ProfileStore.shared.setCustomCommand(enabled: value, command: ProfileStore.shared.customCommandSetting.command)
                    MainActor.assumeIsolated { self?.objectWillChange.send() }
                })
    }
    var customCommand: Binding<String> {
        Binding(get: { ProfileStore.shared.customCommandSetting.command },
                set: { [weak self] value in
                    ProfileStore.shared.setCustomCommand(enabled: ProfileStore.shared.customCommandSetting.enabled, command: value)
                    MainActor.assumeIsolated { self?.objectWillChange.send() }
                })
    }

    // Fonts

    var bundledFonts: [BundledFont] { FontLibrary.shared.bundledFonts }
    lazy var systemFonts: [String] = FontLibrary.shared.systemMonospacedFamilies

    // Colour conversion

    static func nsColor(hex: String) -> NSColor {
        let rgb = Profile.parseHexColor(hex)
        return NSColor(srgbRed: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)
    }

    static func hex(_ color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return "#ffffff" }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

// MARK: - Panes

private struct GeneralSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Keyboard") {
                Toggle("Use Option as Meta key", isOn: model.optionAsMeta)
                Toggle("Shift-Return and Control-Return insert a new line", isOn: model.newLineKeys)
                Toggle("Secure Keyboard Entry", isOn: model.secureKeyboardEntry)
                Text("Secure Keyboard Entry stops other apps from reading what you type while this app is in front.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Window") {
                Picker("Office mode", selection: model.officeScene) {
                    ForEach(OfficeScene.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Always show the tab bar", isOn: model.alwaysShowTabBar)
                Toggle("Show the tab bar in full screen", isOn: model.tabBarInFullScreen)
                Toggle("Show the terminal size when resizing", isOn: model.showTerminalSize)
            }
            Section {
                Toggle("Run a custom command instead of the login shell", isOn: model.customCommandEnabled)
                TextField("Command", text: model.customCommand)
                    .disabled(!model.customCommandEnabled.wrappedValue)
            } header: {
                Text("Shell")
            } footer: {
                Text("Shared with the Qt app. Applies to new tabs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProfilesSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var savingName = ""
    @State private var showingSave = false
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            Section {
                Picker("Profile", selection: model.profileName) {
                    if model.profile.name.isEmpty {
                        Text("Custom (unsaved)").tag("")
                    }
                    ForEach(model.builtinNames, id: \.self) { Text($0).tag($0) }
                    if !model.customNames.isEmpty {
                        Divider()
                        ForEach(model.customNames, id: \.self) { Text($0).tag($0) }
                    }
                }
                HStack {
                    Button("Save as…") {
                        savingName = model.profile.name.isEmpty ? "" : model.profile.name
                        showingSave = true
                    }
                    Button("Delete…") { confirmingDelete = true }
                        .disabled(!model.canDeleteCurrent)
                    Spacer()
                    Button("Import…") { model.importProfile() }
                    Button("Export…") { model.exportProfile() }
                }
                Toggle("CRT effects", isOn: model.effectsEnabled)
            } header: {
                Text("Profile")
            } footer: {
                Text("Profiles and every change here are shared with the Qt app. Changing a setting turns the profile into \"Custom\" until you save it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Colours") {
                ColorPicker("Text", selection: model.color(\.fontColor), supportsOpacity: false)
                ColorPicker("Background", selection: model.color(\.backgroundColor), supportsOpacity: false)
                ColorPicker("Frame", selection: model.color(\.frameColor), supportsOpacity: false)
                LabeledSlider("Colour", value: model.number(\.chromaColor))
                LabeledSlider("Saturation", value: model.number(\.saturationColor))
            }

            Section("Screen") {
                LabeledSlider("Brightness", value: model.number(\.brightness))
                LabeledSlider("Contrast", value: model.number(\.contrast))
                LabeledSlider("Opacity", value: model.number(\.windowOpacity))
            }
        }
        .formStyle(.grouped)
        .alert("Save Profile", isPresented: $showingSave) {
            TextField("Name", text: $savingName)
            Button("Save") { model.save(as: savingName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saving with the name of an existing custom profile replaces it.")
        }
        .confirmationDialog("Delete the profile \"\(model.profile.name)\"?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { model.deleteCurrentProfile() }
        } message: {
            Text("It's also removed from the Qt app.")
        }
    }
}

private struct TextSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Font") {
                Picker("Font", selection: model.font) {
                    Section("Bundled") {
                        ForEach(model.bundledFonts, id: \.id) { font in
                            Text(font.name).tag("bundled:" + font.id)
                        }
                    }
                    Section("System") {
                        ForEach(model.systemFonts, id: \.self) { family in
                            Text(family).tag("system:" + family)
                        }
                    }
                }
                LabeledSlider("Size", value: model.zoom, range: 0.25...2.5, percent: true)
                LabeledSlider("Width", value: model.number(\.fontWidth), range: 0.5...1.5, percent: true)
                LabeledSlider("Line spacing", value: model.number(\.lineSpacing), percent: true)
            }
            Section("Cursor") {
                Picker("Shape", selection: model.cursorShape) {
                    Text("Solid block").tag(0)
                    Text("Underline").tag(1)
                    Text("Bar").tag(2)
                }
                Toggle("Blinking cursor", isOn: model.flag(\.blinkingCursor))
            }
        }
        .formStyle(.grouped)
    }
}

private struct PerformanceSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Effects frame rate", selection: model.effectsFrameSkip) {
                    Text("60 fps").tag(1)
                    Text("30 fps").tag(2)
                    Text("20 fps").tag(3)
                    Text("15 fps").tag(4)
                    Text("12 fps").tag(5)
                }
                LabeledSlider("Texture quality", value: model.windowScaling, range: 0.25...1, percent: true)
                LabeledSlider("Bloom quality", value: model.bloomQuality, range: 0.25...1, percent: true)
                LabeledSlider("Burn-in quality", value: model.burnInQuality, range: 0.25...1, percent: true)
                Toggle("Pause effects when idle", isOn: model.pauseEffectsWhenIdle)
            } footer: {
                Text("Lower values use less CPU, GPU and battery. What you type is always shown straight away; only the animation of the effects slows down. The effects always run while a window can be seen, and stop while it's minimised or hidden; pausing when idle (off by default) also stops them a few seconds after the last output or key press. In Low Power Mode the effects run at 12 fps. Shared with the Qt app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct EffectsSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Screen") {
                Picker("Rasterization", selection: model.rasterization) {
                    Text("None").tag(0)
                    Text("Scanlines").tag(1)
                    Text("Pixels").tag(2)
                    Text("Sub-pixels").tag(3)
                    Text("Modern").tag(4)
                }
                LabeledSlider("Bloom", value: model.number(\.bloom))
                LabeledSlider("Burn-in", value: model.number(\.burnIn))
                LabeledSlider("Static noise", value: model.number(\.staticNoise))
                LabeledSlider("Jitter", value: model.number(\.jitter))
                LabeledSlider("Glowing line", value: model.number(\.glowingLine))
                LabeledSlider("Screen curvature", value: model.number(\.screenCurvature))
                LabeledSlider("Flickering", value: model.number(\.flickering))
                LabeledSlider("Horizontal sync", value: model.number(\.horizontalSync))
                LabeledSlider("RGB shift", value: model.number(\.rgbShift))
            }
            Section("Frame") {
                LabeledSlider("Frame size", value: model.number(\.frameSize))
                LabeledSlider("Frame shininess", value: model.number(\.frameShininess))
                LabeledSlider("Ambient light", value: model.number(\.ambientLight))
                LabeledSlider("Screen radius", value: model.number(\.screenRadius))
                LabeledSlider("Margin", value: model.number(\.margin))
            }
        }
        .formStyle(.grouped)
    }
}

private struct LabeledSlider: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let percent: Bool

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double> = 0...1, percent: Bool = false) {
        self.title = title
        self.value = value
        self.range = range
        self.percent = percent
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : String(format: "%.2f", value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}
