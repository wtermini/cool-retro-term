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
import QtQuick 2.2
import QtQuick.Controls 2.3

MenuBar {
    id: defaultMenuBar
    visible: appSettings.isMacOS || appSettings.showMenubar

    Menu {
        title: qsTr("File")
        MenuItem { action: newWindowAction }
        MenuItem { action: newTabAction }
        MenuItem { action: renameTabAction }
        Menu {
            id: tabColorMenu
            title: qsTr("Tab Color")
            MenuItem { text: qsTr("None"); onTriggered: terminalTabs.setTabColor(terminalTabs.currentIndex, "") }
            MenuSeparator { }
            Instantiator {
                model: terminalTabs.tabColors
                delegate: MenuItem {
                    text: modelData.name
                    onTriggered: terminalTabs.setTabColor(terminalTabs.currentIndex, modelData.color)
                }
                onObjectAdded: (index, object) => tabColorMenu.insertItem(index + 2, object)
                onObjectRemoved: (index, object) => tabColorMenu.removeItem(object)
            }
            MenuSeparator { }
            MenuItem { text: qsTr("Custom…"); onTriggered: terminalTabs.chooseCustomColor(terminalTabs.currentIndex) }
        }
        MenuItem { action: closeTabAction }
        MenuSeparator { }
        MenuItem { action: quitAction }
    }
    Menu {
        title: qsTr("Edit")
        MenuItem { action: copyAction }
        MenuItem { action: pasteAction }
        MenuSeparator {}
        MenuItem { action: showsettingsAction }
    }
    Menu {
        id: viewMenu
        title: qsTr("View")
        Instantiator {
            model: !appSettings.isMacOS ? 1 : 0
            delegate: MenuItem { action: fullscreenAction }
            onObjectAdded: (index, object) => viewMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => viewMenu.removeItem(object)
        }
        MenuItem { action: zoomIn }
        MenuItem { action: zoomOut }
        MenuSeparator { }
        MenuItem {
            text: qsTr("Blinking Cursor")
            checkable: true
            checked: appSettings.blinkingCursor
            onTriggered: appSettings.blinkingCursor = checked
        }
        Menu {
            title: qsTr("Cursor Shape")
            MenuItem { text: qsTr("Solid Block"); checkable: true; checked: appSettings.cursorShape === 0; onTriggered: appSettings.cursorShape = 0 }
            MenuItem { text: qsTr("Underline"); checkable: true; checked: appSettings.cursorShape === 1; onTriggered: appSettings.cursorShape = 1 }
            MenuItem { text: qsTr("Bar"); checkable: true; checked: appSettings.cursorShape === 2; onTriggered: appSettings.cursorShape = 2 }
        }
        Menu {
            title: qsTr("Office Mode")
            MenuItem { text: qsTr("Off"); checkable: true; checked: appSettings.officeScene === ""; onTriggered: appSettings.officeScene = "" }
            MenuItem { text: qsTr("80s Den"); checkable: true; checked: appSettings.officeScene === "80s"; onTriggered: appSettings.officeScene = "80s" }
            MenuItem { text: qsTr("90s Cubicle"); checkable: true; checked: appSettings.officeScene === "90s"; onTriggered: appSettings.officeScene = "90s" }
            MenuSeparator { }
            MenuItem { text: qsTr("Standard Monitor (4:3)"); checkable: true; checked: appSettings.officeMonitor === "standard"; onTriggered: appSettings.officeMonitor = "standard" }
            MenuItem { text: qsTr("Widescreen Monitor (16:10)"); checkable: true; checked: appSettings.officeMonitor === "wide"; onTriggered: appSettings.officeMonitor = "wide" }
            MenuSeparator { }
            MenuItem { text: qsTr("Close Up"); checkable: true; checked: appSettings.officeZoom === "close"; onTriggered: appSettings.officeZoom = "close" }
            MenuItem { text: qsTr("At the Desk"); checkable: true; checked: appSettings.officeZoom === "desk"; onTriggered: appSettings.officeZoom = "desk" }
            MenuItem { text: qsTr("Whole Room"); checkable: true; checked: appSettings.officeZoom === "room"; onTriggered: appSettings.officeZoom = "room" }
            MenuSeparator { }
            MenuItem { text: qsTr("Sticky Notes"); checkable: true; checked: appSettings.officeStickyNotes; onTriggered: appSettings.officeStickyNotes = checked }
            MenuItem { text: qsTr("3D Room"); checkable: true; checked: appSettings.office3D; onTriggered: appSettings.office3D = checked }
            MenuItem { text: qsTr("Look Around"); checkable: true; enabled: appSettings.office3D; checked: appSettings.officeLookAround; onTriggered: appSettings.officeLookAround = checked }
            MenuSeparator { }
            MenuItem { text: qsTr("Edit Notes and Calendar…"); onTriggered: officeDeskWindow.openAt("", "") }
            MenuItem { text: qsTr("Copy Agent (MCP) Setup Command"); onTriggered: officeDesk.copyToClipboard(officeDesk.mcpCommand) }
            MenuItem { text: qsTr("Reset View"); enabled: appSettings.officeScene !== "" && appSettings.office3D; onTriggered: terminalTabs.resetOfficeView() }
        }
    }
    Menu {
        id: profilesMenu
        title: qsTr("Profiles")
        Instantiator {
            model: appSettings.profilesList
            delegate: MenuItem {
                text: model.text
                onTriggered: {
                    appSettings.loadProfileString(obj_string)
                }
            }
            onObjectAdded: function(index, object) { profilesMenu.insertItem(index, object) }
            onObjectRemoved: function(object) { profilesMenu.removeItem(object) }
        }
    }
    Menu {
        title: qsTr("Help")
        MenuItem {
            action: showAboutAction
        }
    }
}
