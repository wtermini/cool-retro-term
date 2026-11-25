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
import QtQuick.Controls 2.0
import QtQuick.Layouts 1.1
import QtQml 2.0

import "Components"

ColumnLayout {
    GroupBox {
        Layout.fillWidth: true
        Layout.fillHeight: true
        title: qsTr("Miscellaneous")
        padding: appSettings.defaultMargin

        ColumnLayout {
            anchors.fill: parent
            CheckBox {
                id: useCustomCommand
                text: qsTr("Use custom command instead of shell at startup")
                checked: appSettings.useCustomCommand
                onCheckedChanged: appSettings.useCustomCommand = checked
            }
            TextField {
                id: customCommand
                Layout.fillWidth: true
                text: appSettings.customCommand
                enabled: useCustomCommand.checked
                onEditingFinished: appSettings.customCommand = text

                // Save text even if user forgets to press enter or unfocus
                function saveSetting() {
                    appSettings.customCommand = text
                }
                Component.onCompleted: settings_window.closing.connect(
                                           saveSetting)
            }
            CheckBox {
                id: blinkingCursor
                text: qsTr("Blinking Cursor")
                checked: appSettings.blinkingCursor
                onCheckedChanged: appSettings.blinkingCursor = checked
            }
            RowLayout {
                Label { text: qsTr("Cursor Shape") }
                ComboBox {
                    model: [qsTr("Solid block"), qsTr("Underline"), qsTr("Bar")]
                    currentIndex: appSettings.cursorShape
                    onActivated: (index) => appSettings.cursorShape = index
                }
            }
            CheckBox {
                text: qsTr("Shift-Return and Control-Return insert a new line")
                checked: appSettings.newLineKeys
                onCheckedChanged: appSettings.newLineKeys = checked
            }
            RowLayout {
                Label { text: qsTr("Office Mode") }
                ComboBox {
                    readonly property var scenes: ["", "70s", "80s", "90s", "2000s", "gloss"]
                    model: [qsTr("Off"), qsTr("70s Mainframe"), qsTr("80s Den"), qsTr("90s Cubicle"), qsTr("2000s Office"), qsTr("Glossy 2000s")]
                    currentIndex: Math.max(scenes.indexOf(appSettings.officeScene), 0)
                    onActivated: (index) => appSettings.officeScene = scenes[index]
                }
            }
            RowLayout {
                Label { text: qsTr("Office Monitor") }
                ComboBox {
                    readonly property var monitors: ["standard", "wide"]
                    model: [qsTr("Standard (4:3)"), qsTr("Widescreen (16:10)")]
                    currentIndex: Math.max(monitors.indexOf(appSettings.officeMonitor), 0)
                    onActivated: (index) => appSettings.officeMonitor = monitors[index]
                }
            }
            RowLayout {
                Label { text: qsTr("Office View") }
                ComboBox {
                    readonly property var zooms: ["close", "desk", "room"]
                    model: [qsTr("Close up"), qsTr("At the desk"), qsTr("Whole room")]
                    currentIndex: Math.max(zooms.indexOf(appSettings.officeZoom), 0)
                    onActivated: (index) => appSettings.officeZoom = zooms[index]
                }
            }
            RowLayout {
                Label { text: qsTr("Orbit When Idle") }
                ComboBox {
                    readonly property var minutes: [0, 1, 2, 5, 10, 15, 30]
                    model: [qsTr("Never"), qsTr("After 1 minute"), qsTr("After 2 minutes"), qsTr("After 5 minutes"),
                            qsTr("After 10 minutes"), qsTr("After 15 minutes"), qsTr("After 30 minutes")]
                    currentIndex: Math.max(minutes.indexOf(appSettings.officeIdleOrbit), 0)
                    onActivated: (index) => appSettings.officeIdleOrbit = minutes[index]
                }
                ComboBox {
                    readonly property var speeds: ["slow", "normal", "fast"]
                    enabled: appSettings.officeIdleOrbit > 0
                    model: [qsTr("Slow"), qsTr("Normal"), qsTr("Fast")]
                    currentIndex: Math.max(speeds.indexOf(appSettings.officeIdleOrbitSpeed), 0)
                    onActivated: (index) => appSettings.officeIdleOrbitSpeed = speeds[index]
                }
            }
            CheckBox {
                text: qsTr("Sticky notes")
                checked: appSettings.officeStickyNotes
                onCheckedChanged: appSettings.officeStickyNotes = checked
            }
            CheckBox {
                text: qsTr("Office Mode in 3D (a picture of the room when off)")
                checked: appSettings.office3D
                onCheckedChanged: appSettings.office3D = checked
            }
            CheckBox {
                text: qsTr("Look around the room (Option/Alt-drag, Option/Alt-scroll)")
                enabled: appSettings.office3D
                checked: appSettings.officeLookAround
                onCheckedChanged: appSettings.officeLookAround = checked
            }
            CheckBox {
                text: qsTr("Always show the tab bar")
                checked: appSettings.alwaysShowTabBar
                onCheckedChanged: appSettings.alwaysShowTabBar = checked
            }
            CheckBox {
                text: qsTr("Secure Keyboard Entry")
                visible: appSettings.isMacOS
                checked: appSettings.secureKeyboardEntry
                onCheckedChanged: appSettings.secureKeyboardEntry = checked
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Stops other apps from reading what you type while this app is in front.")
            }
            CheckBox {
                id: showMenubar
                text: qsTr("Show Menubar")
                enabled: !appSettings.isMacOS
                checked: appSettings.showMenubar
                onCheckedChanged: appSettings.showMenubar = checked
            }
        }
    }

    GroupBox {
        title: qsTr("Performance")
        Layout.fillWidth: true
        Layout.fillHeight: true
        padding: appSettings.defaultMargin
        GridLayout {
            anchors.fill: parent
            columns: 4

            Label {
                text: qsTr("Effects FPS")
            }
            Slider {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                id: effectsFpsSlider
                onValueChanged: appSettings.effectsFrameSkip = Math.round(value)
                stepSize: 1
                enabled: true
                from: 5
                to: 1
                value: appSettings.effectsFrameSkip
            }

            SizedLabel {
                text: Math.round(100 / Math.max(1, Math.round(effectsFpsSlider.value))) + "%"
            }
            Label {
                text: qsTr("Texture Quality")
            }
            Slider {
                id: txtslider
                Layout.fillWidth: true
                Layout.columnSpan: 2
                onValueChanged: appSettings.windowScaling = value
                stepSize: 0.05
                enabled: true
                from: 0.25
                value: appSettings.windowScaling
            }
            SizedLabel {
                text: Math.round(txtslider.value * 100) + "%"
            }

            Label {
                text: qsTr("Bloom Quality")
            }
            Slider {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                id: bloomSlider
                onValueChanged: appSettings.bloomQuality = value
                stepSize: 0.05
                enabled: true
                from: 0.25
                value: appSettings.bloomQuality
            }
            SizedLabel {
                text: Math.round(bloomSlider.value * 100) + "%"
            }

            Label {
                text: qsTr("BurnIn Quality")
            }
            Slider {
                Layout.fillWidth: true
                id: burnInSlider
                Layout.columnSpan: 2
                onValueChanged: appSettings.burnInQuality = value
                stepSize: 0.05
                enabled: true
                from: 0.25
                value: appSettings.burnInQuality
            }
            SizedLabel {
                text: Math.round(burnInSlider.value * 100) + "%"
            }
            CheckBox {
                Layout.columnSpan: 4
                text: qsTr("Pause effects when idle")
                checked: appSettings.pauseEffectsWhenIdle
                onCheckedChanged: appSettings.pauseEffectsWhenIdle = checked
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Off by default. Stops animating the effects a few seconds after the last output or key press, to save CPU, GPU and battery. Effects always pause while every window is minimised or hidden.")
            }
        }
    }
}
