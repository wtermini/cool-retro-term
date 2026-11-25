/*******************************************************************************
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
*******************************************************************************/
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

/// Edits the office desk: the three sticky notes and the calendar's events
/// (officeDesk, shared with Cool Retro Term SE and with agents through the
/// MCP server). Opened from View > Office Mode > Edit Notes and Calendar,
/// or by double-clicking a note or the calendar in the room.
ApplicationWindow {
    id: deskWindow
    title: qsTr("Office Desk")
    width: 600
    height: 640
    visible: false

    readonly property var colors: ["yellow", "pink", "green", "blue", "orange"]
    readonly property var colorNames: [qsTr("Yellow"), qsTr("Pink"), qsTr("Green"), qsTr("Blue"), qsTr("Orange")]

    function todayIso() {
        const d = new Date()
        return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2)
    }

    /// what: "note:<id>", "calendar" or "". date (YYYY-MM-DD): the calendar
    /// day to add an event on.
    function openAt(what, date) {
        show()
        raise()
        requestActivate()
        tabs.currentIndex = what === "calendar" ? 1 : 0
        if (date)
            newDate.text = date
        if (what === "calendar")
            newTitle.forceActiveFocus()
        const notes = officeDesk.notes
        for (let i = 0; i < notes.length; ++i)
            if ("note:" + notes[i].id === what && noteRepeater.itemAt(i))
                noteRepeater.itemAt(i).focusText()
    }

    header: TabBar {
        id: tabs
        TabButton { text: qsTr("Sticky Notes") }
        TabButton { text: qsTr("Calendar") }
    }

    StackLayout {
        anchors.fill: parent
        anchors.margins: 12
        currentIndex: tabs.currentIndex

        ColumnLayout {
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: qsTr("Add Note")
                    enabled: officeDesk.notes.length < officeDesk.maxNotes
                    onClicked: officeDesk.addNote("", "")
                }
                Label {
                    Layout.fillWidth: true
                    text: qsTr("%1 of %2 notes, up to 280 characters each. Saved when you click away.")
                          .arg(officeDesk.notes.length).arg(officeDesk.maxNotes)
                    opacity: 0.7
                    elide: Text.ElideRight
                }
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: parent.width
                    spacing: 10
                    Repeater {
                        id: noteRepeater
                        model: officeDesk.notes
                        ColumnLayout {
                            id: noteEditor
                            required property var modelData
                            Layout.fillWidth: true
                            function focusText() { textArea.forceActiveFocus() }
                            function save() {
                                if (textArea.text !== modelData.text || deskWindow.colors[colorBox.currentIndex] !== modelData.color)
                                    officeDesk.updateNote(modelData.id, textArea.text, deskWindow.colors[colorBox.currentIndex])
                            }

                            RowLayout {
                                ComboBox {
                                    id: colorBox
                                    model: deskWindow.colorNames
                                    currentIndex: Math.max(deskWindow.colors.indexOf(noteEditor.modelData.color), 0)
                                    onActivated: noteEditor.save()
                                }
                                Item { Layout.fillWidth: true }
                                Button { text: qsTr("Delete"); onClicked: officeDesk.removeNote(noteEditor.modelData.id) }
                            }
                            TextArea {
                                id: textArea
                                Layout.fillWidth: true
                                Layout.preferredHeight: 70
                                textFormat: TextEdit.PlainText
                                wrapMode: TextEdit.Wrap
                                placeholderText: qsTr("Blank")
                                text: noteEditor.modelData.text
                                onActiveFocusChanged: if (!activeFocus) noteEditor.save()
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            spacing: 8
            Label { text: qsTr("Add an event"); font.bold: true }
            RowLayout {
                Layout.fillWidth: true
                TextField { id: newDate; text: deskWindow.todayIso(); placeholderText: "YYYY-MM-DD"; Layout.preferredWidth: 110 }
                TextField { id: newTime; placeholderText: qsTr("HH:MM"); Layout.preferredWidth: 70 }
                TextField { id: newTitle; placeholderText: qsTr("What's on"); Layout.fillWidth: true; onAccepted: addButton.clicked() }
                Button {
                    id: addButton
                    text: qsTr("Add")
                    onClicked: {
                        if (officeDesk.addEvent(newDate.text.trim(), newTime.text.trim(), newTitle.text) !== "") {
                            newTitle.text = ""
                            newTime.text = ""
                            addError.visible = false
                        } else {
                            addError.visible = true
                        }
                    }
                }
            }
            Label {
                id: addError
                visible: false
                color: "#d03030"
                text: qsTr("Check the date (YYYY-MM-DD), the time (HH:MM, or empty for all day) and the title.")
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Label { text: qsTr("Events"); font.bold: true; Layout.topMargin: 8 }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: officeDesk.events
                ScrollBar.vertical: ScrollBar { }
                delegate: RowLayout {
                    id: eventRow
                    required property var modelData
                    width: ListView.view.width - 12
                    function save() {
                        if (!officeDesk.updateEvent(modelData.id, dateField.text.trim(), timeField.text.trim(), titleField.text)) {
                            dateField.text = modelData.date
                            timeField.text = modelData.time
                            titleField.text = modelData.title
                        }
                    }
                    TextField { id: dateField; text: eventRow.modelData.date; Layout.preferredWidth: 110; onEditingFinished: eventRow.save() }
                    TextField { id: timeField; text: eventRow.modelData.time; placeholderText: qsTr("All day"); Layout.preferredWidth: 70; onEditingFinished: eventRow.save() }
                    TextField { id: titleField; text: eventRow.modelData.title; Layout.fillWidth: true; onEditingFinished: eventRow.save() }
                    Button { text: qsTr("Delete"); onClicked: officeDesk.removeEvent(eventRow.modelData.id) }
                }
                Label {
                    anchors.centerIn: parent
                    visible: parent.count === 0
                    text: qsTr("No events yet.")
                    opacity: 0.7
                }
            }
        }
    }

    footer: Pane {
        ColumnLayout {
            anchors.fill: parent
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: qsTr("Agents can read and change the notes and calendar too, through this app's MCP server. To set it up in Claude Code, run:")
            }
            RowLayout {
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    readOnly: true
                    selectByMouse: true
                    text: officeDesk.mcpCommand
                }
                Button { text: qsTr("Copy"); onClicked: officeDesk.copyToClipboard(officeDesk.mcpCommand) }
            }
        }
    }
}
