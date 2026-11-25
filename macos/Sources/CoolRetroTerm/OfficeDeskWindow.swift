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

/// Edits the office desk: the three sticky notes and the calendar's events
/// (OfficeDesk, shared with the Qt app and with agents through the MCP
/// server). Opened from View > Office Mode > Edit Notes and Calendar, or by
/// double-clicking a note or the calendar in the room.
@MainActor
final class OfficeDeskWindowController: NSWindowController {
    static let shared = OfficeDeskWindowController()

    private let model = OfficeDeskModel()

    private init() {
        let hosting = NSHostingController(rootView: OfficeDeskView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Office Desk"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 620))
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// what: "note:<id>", "calendar" or "". `date` (YYYY-MM-DD) is the
    /// calendar day to add an event on.
    func show(focusing what: String, date: String? = nil) {
        model.reload()
        model.tab = what == "calendar" ? .calendar : .notes
        model.focusedNote = what.hasPrefix("note:") ? String(what.dropFirst(5)) : nil
        model.newEventDate = date
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class OfficeDeskModel: ObservableObject {
    enum Tab { case notes, calendar }

    @Published var tab = Tab.notes
    @Published var focusedNote: String?
    @Published var newEventDate: String?
    @Published var notes: [DeskNote] = []
    @Published var events: [DeskEvent] = []

    private var observer: NSObjectProtocol?

    init() {
        reload()
        observer = NotificationCenter.default.addObserver(forName: .officeDeskDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func reload() {
        let desk = OfficeDesk.shared
        if notes != desk.notes { notes = desk.notes }
        if events != desk.events { events = desk.events }
    }
}

private struct OfficeDeskView: View {
    @ObservedObject var model: OfficeDeskModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.tab) {
                Text("Sticky Notes").tag(OfficeDeskModel.Tab.notes)
                Text("Calendar").tag(OfficeDeskModel.Tab.calendar)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300)
            .padding(12)

            Group {
                switch model.tab {
                case .notes: NotesEditor(model: model)
                case .calendar: CalendarEditor(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Agents can read and change the notes and calendar too, through this app's MCP server. To set it up in Claude Code, run:")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(OfficeDesk.mcpCommand)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(OfficeDesk.mcpCommand, forType: .string)
                    }
                }
            }
            .padding(12)
        }
        .frame(minWidth: 520, minHeight: 520)
    }
}

private struct NotesEditor: View {
    @ObservedObject var model: OfficeDeskModel

    var body: some View {
        Form {
            ForEach(model.notes) { note in
                NoteEditor(note: note, focused: model.focusedNote == note.id)
            }
            Section {
                HStack {
                    Button("Add Note") { _ = OfficeDesk.shared.addNote(text: "", color: nil) }
                        .disabled(model.notes.count >= OfficeDesk.maxNotes)
                    Spacer()
                    Text("\(model.notes.count) of \(OfficeDesk.maxNotes) notes, up to \(OfficeDesk.maxNoteLength) characters each. Saved as you type.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct NoteEditor: View {
    let note: DeskNote
    let focused: Bool

    @State private var text = ""
    @State private var pendingSave: DispatchWorkItem?
    @FocusState private var hasFocus: Bool

    var body: some View {
        Section {
            TextEditor(text: $text)
                .font(.body)
                .frame(height: 60)
                .focused($hasFocus)
                .onChange(of: text) { newValue in
                    guard newValue != note.text else { return }
                    pendingSave?.cancel()
                    let id = note.id
                    let save = DispatchWorkItem { _ = OfficeDesk.shared.updateNote(id: id, text: newValue, color: nil) }
                    pendingSave = save
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: save)
                }
        } header: {
            HStack {
                Picker("Colour", selection: Binding(
                    get: { note.color },
                    set: { _ = OfficeDesk.shared.updateNote(id: note.id, text: text, color: $0) })) {
                    ForEach(OfficeDesk.colors, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)
                Spacer()
                Button("Delete") { _ = OfficeDesk.shared.removeNote(id: note.id) }
            }
        }
        .onAppear {
            text = note.text
            if focused { hasFocus = true }
        }
        // Keep up with changes from the other app or an agent unless it's being edited.
        .onChange(of: note.text) { newValue in
            if !hasFocus { text = newValue }
        }
    }
}

private struct CalendarEditor: View {
    @ObservedObject var model: OfficeDeskModel

    @State private var date = Date()
    @State private var time = ""
    @State private var title = ""
    @State private var error = false

    var body: some View {
        Form {
            Section("Add an event") {
                HStack {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                    TextField("HH:MM", text: $time)
                        .frame(width: 70)
                    TextField("What's on", text: $title)
                        .onSubmit(add)
                    Button("Add", action: add)
                }
                if error {
                    Text("Check the time (HH:MM, or empty for all day) and the title.")
                        .foregroundStyle(.red)
                }
            }
            Section("Events") {
                if model.events.isEmpty {
                    Text("No events yet.").foregroundStyle(.secondary)
                }
                ForEach(model.events) { event in
                    EventRow(event: event)
                }
            }
        }
        .formStyle(.grouped)
        // A day double-clicked on the calendar in the room.
        .onAppear(perform: useRequestedDate)
        .onChange(of: model.newEventDate) { _ in useRequestedDate() }
    }

    private func useRequestedDate() {
        guard let iso = model.newEventDate else { return }
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        if parts.count == 3, let value = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) {
            date = value
        }
        model.newEventDate = nil
    }

    private func add() {
        if OfficeDesk.shared.addEvent(date: OfficeDesk.iso(date), time: time.trimmingCharacters(in: .whitespaces), title: title) != nil {
            title = ""
            time = ""
            error = false
        } else {
            error = true
        }
    }
}

private struct EventRow: View {
    let event: DeskEvent
    @State private var date = ""
    @State private var time = ""
    @State private var title = ""

    var body: some View {
        HStack {
            TextField("YYYY-MM-DD", text: $date).frame(width: 100).onSubmit(save)
            TextField("All day", text: $time).frame(width: 60).onSubmit(save)
            TextField("Title", text: $title).onSubmit(save)
            Button("Delete") { _ = OfficeDesk.shared.removeEvent(id: event.id) }
        }
        .onAppear(perform: reset)
        .onChange(of: event) { _ in reset() }
    }

    private func reset() {
        date = event.date
        time = event.time
        title = event.title
    }

    private func save() {
        if !OfficeDesk.shared.updateEvent(id: event.id, date: date.trimmingCharacters(in: .whitespaces),
                                          time: time.trimmingCharacters(in: .whitespaces), title: title) {
            reset()
        }
    }
}
