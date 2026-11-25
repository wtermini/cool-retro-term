/*******************************************************************************
* Copyright (c) 2013-2021 "Filippo Scognamiglio"
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
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQml.Models

Item {
    id: tabsRoot

    readonly property int innerPadding: 6
    readonly property string currentTitle: displayTitle(tabsModel.get(currentIndex))
    property alias currentIndex: tabBar.currentIndex
    readonly property int count: tabsModel.count
    property size terminalSize: Qt.size(0, 0)

    /// Index of the tab whose name is being edited, or -1.
    property int editingIndex: -1

    /// Tab colours offered in the tab menu (the same set as Cool Retro Term SE).
    readonly property var tabColors: [
        { name: qsTr("Red"), color: "#ff3b30" },
        { name: qsTr("Orange"), color: "#ff9500" },
        { name: qsTr("Yellow"), color: "#ffcc00" },
        { name: qsTr("Green"), color: "#34c759" },
        { name: qsTr("Teal"), color: "#30b0c7" },
        { name: qsTr("Blue"), color: "#007aff" },
        { name: qsTr("Purple"), color: "#af52de" },
        { name: qsTr("Pink"), color: "#ff2d55" },
        { name: qsTr("Gray"), color: "#8e8e93" }
    ]

    function normalizeTitle(rawTitle) {
        if (rawTitle === undefined || rawTitle === null) {
            return ""
        }
        return String(rawTitle).trim()
    }

    /// A name the user gave the tab wins over the title the program sets.
    function displayTitle(tab) {
        if (!tab)
            return "cool-retro-term"
        return tab.customTitle || tab.title || "cool-retro-term"
    }

    /// The user's colour wins over one a program set (OSC 6).
    function tabColor(tab) {
        return tab.userColor !== "" ? tab.userColor : tab.programColor
    }

    function addTab() {
        tabsModel.append({ title: "", customTitle: "", userColor: "", programColor: "",
                           programRed: 0, programGreen: 0, programBlue: 0 })
        tabBar.currentIndex = tabsModel.count - 1
    }

    function closeTab(index) {
        if (tabsModel.count <= 1) {
            terminalWindow.close()
            return
        }

        tabsModel.remove(index)
        tabBar.currentIndex = Math.min(tabBar.currentIndex, tabsModel.count - 1)
    }

    function closeOtherTabs(index) {
        for (let i = tabsModel.count - 1; i >= 0; i--) {
            if (i !== index)
                tabsModel.remove(i)
        }
        tabBar.currentIndex = 0
    }

    function renameTab(index, name) {
        tabsModel.setProperty(index, "customTitle", normalizeTitle(name))
    }

    /// Office mode: back to the starting view of the room.
    function resetOfficeView() {
        if (officeLoader.item)
            officeLoader.item.resetView()
    }

    function renameCurrentTab() {
        editingIndex = currentIndex
    }

    /// Opens the colour picker for any colour, for the tab at `index`.
    function chooseCustomColor(index) {
        const tab = tabsModel.get(index)
        customColorDialog.tabIndex = index
        customColorDialog.selectedColor = tab && tabColor(tab) !== "" ? tabColor(tab) : "#007aff"
        customColorDialog.open()
    }

    function setTabColor(index, color) {
        tabsModel.setProperty(index, "userColor", color)
    }

    /// OSC 6 from the program: "1;bg;red|green|blue;brightness;N" sets one
    /// channel (0-255); "1;bg;*;default" clears the colour.
    function applyProgramColor(index, spec) {
        const parts = String(spec).toLowerCase().split(";")
        if (parts.length < 4 || parts[0] !== "1" || parts[1] !== "bg")
            return
        if (parts[2] === "*" && parts[3] === "default") {
            tabsModel.setProperty(index, "programColor", "")
            return
        }
        const channels = { red: "programRed", green: "programGreen", blue: "programBlue" }
        const level = parseInt(parts[4])
        if (parts.length !== 5 || parts[3] !== "brightness" || !channels.hasOwnProperty(parts[2])
                || isNaN(level) || level < 0 || level > 255)
            return
        tabsModel.setProperty(index, channels[parts[2]], level)
        const tab = tabsModel.get(index)
        tabsModel.setProperty(index, "programColor",
                              Qt.rgba(tab.programRed / 255, tab.programGreen / 255, tab.programBlue / 255, 1).toString())
    }

    function luminance(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    ListModel {
        id: tabsModel
    }

    Component.onCompleted: addTab()

    ColorDialog {
        id: customColorDialog
        property int tabIndex: -1
        title: qsTr("Tab Color")
        onAccepted: tabsRoot.setTabColor(tabIndex, selectedColor.toString())
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: tabRow
            Layout.fillWidth: true
            height: rowLayout.implicitHeight
            color: palette.window
            visible: tabsModel.count > 1 || appSettings.alwaysShowTabBar

            RowLayout {
                id: rowLayout
                anchors.fill: parent
                spacing: 0

                TabBar {
                    id: tabBar
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    focusPolicy: Qt.NoFocus

                    Repeater {
                        model: tabsModel
                        TabButton {
                            id: tabButton
                            readonly property string colorName: tabsRoot.tabColor(model)
                            readonly property bool colored: colorName !== ""
                            readonly property color fillColor: colored ? colorName : palette.window
                            readonly property bool editing: tabsRoot.editingIndex === index

                            // Coloured tabs are filled: full colour when selected, dimmed otherwise.
                            background: Rectangle {
                                color: tabButton.colored
                                       ? (tabButton.checked ? tabButton.fillColor
                                                            : Qt.tint(palette.window, Qt.rgba(tabButton.fillColor.r, tabButton.fillColor.g, tabButton.fillColor.b, 0.5)))
                                       : (tabButton.checked ? palette.base : palette.window)
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: 2
                                    visible: tabButton.checked
                                    color: tabButton.colored ? Qt.rgba(1, 1, 1, 0.85) : palette.highlight
                                }
                            }

                            onDoubleClicked: tabsRoot.editingIndex = index

                            // Middle-click closes; right-click opens the tab menu.
                            TapHandler {
                                acceptedButtons: Qt.MiddleButton
                                onTapped: tabsRoot.closeTab(index)
                            }
                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: tabMenu.popup()
                            }

                            Menu {
                                id: tabMenu
                                MenuItem {
                                    text: qsTr("Rename Tab")
                                    onTriggered: tabsRoot.editingIndex = index
                                }
                                Menu {
                                    title: qsTr("Tab Color")
                                    MenuItem {
                                        text: qsTr("None")
                                        onTriggered: tabsRoot.setTabColor(index, "")
                                    }
                                    MenuSeparator {}
                                    Repeater {
                                        model: tabsRoot.tabColors
                                        MenuItem {
                                            text: modelData.name
                                            icon.color: modelData.color
                                            onTriggered: tabsRoot.setTabColor(tabButton.TabBar.index, modelData.color)
                                        }
                                    }
                                    MenuSeparator {}
                                    MenuItem {
                                        text: qsTr("Custom…")
                                        onTriggered: {
                                            customColorDialog.tabIndex = index
                                            customColorDialog.selectedColor = tabButton.colored ? tabButton.fillColor : "#007aff"
                                            customColorDialog.open()
                                        }
                                    }
                                }
                                MenuSeparator {}
                                MenuItem {
                                    text: qsTr("Close Tab")
                                    onTriggered: tabsRoot.closeTab(index)
                                }
                                MenuItem {
                                    text: qsTr("Close Other Tabs")
                                    enabled: tabsModel.count > 1
                                    onTriggered: tabsRoot.closeOtherTabs(index)
                                }
                            }

                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors { leftMargin: innerPadding; rightMargin: innerPadding }
                                spacing: innerPadding

                                Label {
                                    visible: !tabButton.editing
                                    text: tabsRoot.displayTitle(model)
                                    // Programs set the title (OSC 0/2): never treat it as HTML,
                                    // which could load remote images or fake the tab's content.
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: tabButton.colored
                                           ? (tabsRoot.luminance(tabButton.checked ? tabButton.fillColor : tabButton.background.color) > 0.55 ? "#111111" : "#ffffff")
                                           : palette.buttonText
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Return saves, Escape cancels; empty goes back to the program's title.
                                TextField {
                                    id: nameField
                                    visible: tabButton.editing
                                    text: model.customTitle
                                    placeholderText: qsTr("Automatic")
                                    selectByMouse: true
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    onVisibleChanged: if (visible) { text = model.customTitle || model.title; forceActiveFocus(); selectAll() }
                                    onAccepted: { tabsRoot.renameTab(index, text); tabsRoot.editingIndex = -1 }
                                    onActiveFocusChanged: if (!activeFocus && tabButton.editing) { tabsRoot.renameTab(index, text); tabsRoot.editingIndex = -1 }
                                    Keys.onEscapePressed: tabsRoot.editingIndex = -1
                                }

                                ToolButton {
                                    text: "\u00d7"
                                    focusPolicy: Qt.NoFocus
                                    padding: innerPadding
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: tabsRoot.closeTab(index)
                                }
                            }
                        }
                    }
                }

                ToolButton {
                    id: addTabButton
                    text: "+"
                    focusPolicy: Qt.NoFocus
                    Layout.fillHeight: true
                    padding: innerPadding
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: tabsRoot.addTab()
                }
            }
        }

        Item {
            id: terminalArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Office mode. In 3D, the terminal is laid out at the screen's shape and
            // shown on the monitor in a 3D room (OfficeScene.qml), drawn over
            // it. In 2D (3D turned off, Qt Quick 3D missing or no GPU), it's
            // placed over the monitor in a picture of the room (OfficePicture.qml).
            readonly property bool officeMode: appSettings.officeScene === "80s" || appSettings.officeScene === "90s"
            readonly property bool can3D: GraphicsInfo.api !== GraphicsInfo.Software
                                          && officeLoader.status !== Loader.Error
            readonly property bool office3D: officeMode && appSettings.office3D && can3D
            readonly property bool office2D: officeMode && !office3D
            // The monitor's screen shape: 4:3 or 16:10.
            readonly property real screenAspect: officeLoader.item ? officeLoader.item.screenAspect
                                               : appSettings.officeMonitor === "standard" ? 4 / 3 : 16 / 10
            readonly property real screenHeight: Math.min(height, width / screenAspect)

            OfficePicture {
                id: officePicture
                anchors.fill: parent
                visible: terminalArea.office2D
                scene: terminalArea.officeMode ? appSettings.officeScene : "80s"
                monitor: appSettings.officeMonitor
                zoom: appSettings.officeZoom
                stickyNotes: appSettings.officeStickyNotes
            }

            StackLayout {
                id: stack
                width: terminalArea.office3D ? Math.round(terminalArea.screenHeight * terminalArea.screenAspect)
                     : terminalArea.office2D ? officePicture.screenRect.width : terminalArea.width
                height: terminalArea.office3D ? Math.round(terminalArea.screenHeight)
                      : terminalArea.office2D ? officePicture.screenRect.height : terminalArea.height
                x: terminalArea.office2D ? officePicture.screenRect.x : (terminalArea.width - width) / 2
                y: terminalArea.office2D ? officePicture.screenRect.y : (terminalArea.height - height) / 2
                currentIndex: tabBar.currentIndex

                Repeater {
                    model: tabsModel
                    TerminalContainer {
                        property bool shouldHaveFocus: terminalWindow.active && StackLayout.isCurrentItem && tabsRoot.editingIndex < 0
                        isActive: StackLayout.isCurrentItem
                        onShouldHaveFocusChanged: {
                            if (shouldHaveFocus) {
                                activate()
                            }
                        }
                        onTitleChanged: tabsModel.setProperty(index, "title", normalizeTitle(title))
                        onTabColorRequested: (spec) => tabsRoot.applyProgramColor(index, spec)
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        onSessionFinished: tabsRoot.closeTab(index)
                        onTerminalSizeChanged: updateTerminalSize()

                        function updateTerminalSize() {
                            // Every tab will have the same size so we can simply take the first one.
                            if (index == 0) {
                                tabsRoot.terminalSize = terminalSize
                            }
                        }
                    }
                }
            }

            // Loaded by name, so the app still runs (in 2D) without Qt Quick 3D.
            Loader {
                id: officeLoader
                anchors.fill: parent
                active: terminalArea.officeMode && appSettings.office3D
                visible: terminalArea.office3D
                source: active ? "OfficeScene.qml" : ""
                onStatusChanged: if (status === Loader.Error)
                    console.warn("Office mode: 3D isn't available, showing the picture instead.")
                onLoaded: {
                    item.screenItem = stack
                    item.scene = Qt.binding(() => appSettings.officeScene)
                    item.monitor = Qt.binding(() => appSettings.officeMonitor)
                    item.zoom = Qt.binding(() => appSettings.officeZoom)
                    item.stickyNotes = Qt.binding(() => appSettings.officeStickyNotes)
                    // The notes' text and the calendar's events.
                    item.deskNotes = Qt.binding(() => officeDesk.notes)
                    item.deskEvents = Qt.binding(() => officeDesk.events)
                    item.editRequested.connect((what) => officeDeskWindow.openAt(what))
                    item.time = Qt.binding(() => timeManager.time)
                    item.glowColor = Qt.binding(() => appSettings.fontColor)
                    item.lookAround = Qt.binding(() => appSettings.officeLookAround)
                }
            }
        }
    }
}
