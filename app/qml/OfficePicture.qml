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

/// Office mode in 2D, used when 3D isn't available or is turned off: a
/// picture of the room (rendered from the 3D room, straight on), with the
/// terminal placed over the monitor's screen at `screenRect`. Shared with
/// Cool Retro Term SE (OfficePictureView in OfficeScene.swift).
Item {
    id: picture

    /// "80s" or "90s".
    property string scene: "80s"
    /// "standard" (4:3) or "wide" (16:10).
    property string monitor: "wide"
    property var info: null   // the "picture" part of office/office-<scene>-<monitor>.json
    /// Show the sticky notes.
    property bool stickyNotes: true
    /// "close" (the monitor fills the window), "desk" (the picture fills the
    /// window, around the monitor) or "room" (the whole picture).
    property string zoom: "desk"

    function load() {
        const request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState === XMLHttpRequest.DONE && request.responseText)
                picture.info = JSON.parse(request.responseText).picture
        }
        request.open("GET", Qt.resolvedUrl("office/office-" + scene + "-" + monitor + ".json"))
        request.send()
    }
    onSceneChanged: load()
    onMonitorChanged: load()
    Component.onCompleted: load()

    readonly property size imageSize: info ? Qt.size(info.size[0], info.size[1]) : Qt.size(1, 1)
    readonly property rect monitor: info ? Qt.rect(info.monitor[0], info.monitor[1], info.monitor[2], info.monitor[3])
                                         : Qt.rect(0, 0, 1, 1)

    // At "desk", fill the item with the picture, centred on the monitor,
    // zooming out further if needed so the whole monitor stays in view.
    readonly property real fitMonitor: Math.min(width / monitor.width, height / monitor.height)
    readonly property real imageScale: zoom === "close" ? fitMonitor
        : zoom === "room" ? Math.min(width / imageSize.width, height / imageSize.height)
        : Math.min(Math.max(width / imageSize.width, height / imageSize.height), fitMonitor)
    readonly property real imageX: placement(width, imageSize.width * imageScale, monitor.x + monitor.width / 2)
    readonly property real imageY: placement(height, imageSize.height * imageScale, monitor.y + monitor.height / 2)

    /// Where the terminal goes.
    readonly property rect screenRect: info
        ? Qt.rect(Math.round(imageX + info.screen[0] * imageScale),
                  Math.round(imageY + info.screen[1] * imageScale),
                  Math.round(info.screen[2] * imageScale),
                  Math.round(info.screen[3] * imageScale))
        : Qt.rect(0, 0, width, height)

    function placement(view, image, centre) {
        if (image < view)
            return (view - image) / 2
        return Math.min(Math.max(view / 2 - centre * imageScale, view - image), 0)
    }

    Rectangle {
        anchors.fill: parent
        color: picture.info ? picture.info.fill : "black"
    }

    Image {
        source: !picture.info ? ""
              : "office/" + (!picture.stickyNotes && picture.info.imageWithoutNotes ? picture.info.imageWithoutNotes
                                                                                   : picture.info.image)
        x: picture.imageX
        y: picture.imageY
        width: picture.imageSize.width * picture.imageScale
        height: picture.imageSize.height * picture.imageScale
        smooth: true
        mipmap: true
    }
}
