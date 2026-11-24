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

/// The Settings window (Cool Retro Term ▸ Settings…, Cmd-Comma).
///
/// Profile and effect changes edit the same shared settings as the Qt app's
/// settings dialog and apply to every window as you make them.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let hosting = NSHostingController(rootView: SettingsView(model: SettingsModel()))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
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

// MARK: - Views

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings(model: model)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            EffectsSettings(model: model)
                .tabItem { Label("Effects", systemImage: "tv") }
        }
        .frame(width: 540, height: 620)
    }
}

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
            Section("Tabs") {
                Toggle("Always show the tab bar", isOn: model.alwaysShowTabBar)
                Toggle("Show the tab bar in full screen", isOn: model.tabBarInFullScreen)
            }
            Section("Shell") {
                Toggle("Run a custom command instead of the login shell", isOn: model.customCommandEnabled)
                TextField("Command", text: model.customCommand)
                    .disabled(!model.customCommandEnabled.wrappedValue)
                Text("Shared with the Qt app. Applies to new tabs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var savingName = ""
    @State private var showingSave = false

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
                    Button("Save as Profile…") {
                        savingName = model.profile.name.isEmpty ? "" : model.profile.name
                        showingSave = true
                    }
                    Button("Delete Profile") { model.deleteCurrentProfile() }
                        .disabled(!model.canDeleteCurrent)
                    Spacer()
                }
                Toggle("CRT effects", isOn: model.effectsEnabled)
            } footer: {
                Text("Profiles and changes here are shared with the Qt app.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Text") {
                Picker("Font", selection: model.font) {
                    ForEach(model.bundledFonts, id: \.id) { font in
                        Text(font.name).tag("bundled:" + font.id)
                    }
                    Divider()
                    ForEach(model.systemFonts, id: \.self) { family in
                        Text(family).tag("system:" + family)
                    }
                }
                LabeledSlider("Size", value: model.zoom, range: 0.25...2.5)
            }

            Section("Colours") {
                ColorPicker("Text", selection: model.color(\.fontColor), supportsOpacity: false)
                ColorPicker("Background", selection: model.color(\.backgroundColor), supportsOpacity: false)
                ColorPicker("Frame", selection: model.color(\.frameColor), supportsOpacity: false)
                LabeledSlider("Contrast", value: model.number(\.contrast))
                LabeledSlider("Brightness", value: model.number(\.brightness))
                LabeledSlider("Saturation", value: model.number(\.saturationColor))
                LabeledSlider("Colour", value: model.number(\.chromaColor))
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

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double> = 0...1) {
        self.title = title
        self.value = value
        self.range = range
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(String(format: "%.2f", value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}
