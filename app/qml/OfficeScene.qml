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

/// Office mode: the terminal is shown as the screen of a monitor on a desk,
/// zoomed out, in an 80s or 90s office. Shared with Cool Retro Term SE
/// (macos/Sources/CoolRetroTerm/OfficeScene.swift).
///
/// Put the terminal inside this item at `screenRect`. The pictures come from
/// scripts/generate-office-scenes.py, which also defines the layout numbers
/// below; keep them in step.
Item {
    id: office

    /// "" (off), "80s" or "90s".
    property string scene: ""
    readonly property bool active: scene === "80s" || scene === "90s"

    // Layout of the pictures, in their pixels.
    readonly property size imageSize: Qt.size(2400, 1500)
    readonly property rect screen: Qt.rect(720, 250, 960, 720)
    readonly property rect monitor: Qt.rect(620, 150, 1160, 1000)

    // Fill the item with the picture, centred on the monitor, zooming out
    // further if needed so the whole monitor stays in view.
    readonly property real imageScale: Math.min(
        Math.max(width / imageSize.width, height / imageSize.height),
        width / monitor.width, height / monitor.height)
    readonly property real imageX: placement(width, imageSize.width * imageScale, monitor.x + monitor.width / 2)
    readonly property real imageY: placement(height, imageSize.height * imageScale, monitor.y + monitor.height / 2)

    /// Where the terminal goes: the whole item, or the monitor's screen.
    readonly property rect screenRect: active
        ? Qt.rect(Math.round(imageX + screen.x * imageScale),
                  Math.round(imageY + screen.y * imageScale),
                  Math.round(screen.width * imageScale),
                  Math.round(screen.height * imageScale))
        : Qt.rect(0, 0, width, height)

    function placement(view, image, centre) {
        if (image < view)
            return (view - image) / 2
        return Math.min(Math.max(view / 2 - centre * imageScale, view - image), 0)
    }

    Rectangle {
        anchors.fill: parent
        visible: office.active
        color: office.scene === "80s" ? "#482d19" : "#404653"
    }

    Image {
        visible: office.active
        source: office.active ? "images/office-" + office.scene + ".jpg" : ""
        x: office.imageX
        y: office.imageY
        width: office.imageSize.width * office.imageScale
        height: office.imageSize.height * office.imageScale
        smooth: true
        mipmap: true
        cache: true
    }
}
