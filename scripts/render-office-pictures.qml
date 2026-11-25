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
// Renders the office mode fallback pictures; see render-office-pictures.sh.
import QtQuick
import QtQuick.Window
import "../app/qml" as App

Window {
    id: window
    width: 2400
    height: 1500
    visible: true

    // [room, monitor, sticky notes]
    readonly property var scenes: [["80s", "standard", true], ["80s", "wide", true],
                                   ["90s", "standard", true], ["90s", "wide", true],
                                   ["90s", "standard", false], ["90s", "wide", false]]
    property int index: 0
    readonly property string outDir: Qt.application.arguments[Qt.application.arguments.length - 1]

    Rectangle { id: tube; width: 400; height: 300; color: "black" }

    App.OfficeScene {
        id: office
        anchors.fill: parent
        scene: window.scenes[window.index][0]
        monitor: window.scenes[window.index][1]
        stickyNotes: window.scenes[window.index][2]
        screenItem: tube
        pictureView: true
        lookAround: false
        glowColor: "black"
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: office.grabToImage(function(result) {
            const s = window.scenes[window.index]
            const path = window.outDir + "/office-" + s[0] + "-" + s[1] + (s[2] ? "" : "-nonotes") + ".png"
            result.saveToFile(path)
            console.log("rendered", path)
            if (window.index + 1 >= window.scenes.length)
                Qt.quit()
            else
                window.index++
        })
    }
}
