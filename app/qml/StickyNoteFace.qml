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

/// A sticky note's paper, drawn into its texture in the 3D office.
/// The text comes from the desk (officeDesk), which agents can write, so
/// it's only ever shown as plain text.
Rectangle {
    id: note
    width: 256
    height: 256
    property string text: ""
    property string paper: "yellow"

    readonly property var papers: ({ yellow: "#faec78", pink: "#ffaabe", green: "#b4e6a0",
                                     blue: "#a8d0f8", orange: "#ffc078" })
    color: papers[paper] || papers.yellow


    // A slightly darker strip where the glue is.
    Rectangle {
        width: parent.width
        height: 26
        color: Qt.darker(note.color, 1.06)
    }

    Text {
        anchors.fill: parent
        anchors.margins: 20
        anchors.topMargin: 34
        text: note.text
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        fontSizeMode: Text.Fit
        minimumPixelSize: 14
        font.pixelSize: 46
        font.family: Qt.platform.os === "osx" ? "Marker Felt" : "Comic Sans MS"
        color: "#2b2d6e"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
