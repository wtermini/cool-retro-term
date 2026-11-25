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
import QtQuick3D

/// Office mode: the terminal is the screen of a monitor on a desk in a 3D
/// room, drawn on the GPU (Metal on macOS, OpenGL elsewhere). With "look
/// around" on, Option/Alt-drag looks around, Option/Alt-scroll (or pinch)
/// zooms, Option/Alt-double-click goes back to the starting view, and the
/// view drifts gently and follows the pointer a little.
///
/// Where 3D isn't available, or it's turned off, OfficePicture.qml shows a
/// picture of the same room instead.
///
/// The rooms are described in office/office-<scene>-<monitor>.json, made by
/// scripts/generate-office-scenes.py and shared with Cool Retro Term SE,
/// which builds the same rooms with SceneKit (OfficeScene.swift).
View3D {
    id: view

    /// "80s" or "90s".
    property string scene: "80s"
    /// "standard" (4:3) or "wide" (16:10).
    property string monitor: "wide"
    /// The screen's width over its height, for laying out the terminal.
    readonly property real screenAspect: room.screen ? room.screen.size[0] / room.screen.size[1] : 4 / 3
    // False if the room has a smooth mesh (the 70s terminal) and this Qt
    // can't draw one (ProceduralMesh needs Qt 6.6); the picture is shown instead.
    property bool meshFailed: false
    readonly property bool meshesSupported: !meshFailed || !(room.objects || []).some(o => o.shape === "mesh")
    /// The item shown on the monitor's screen (the terminal).
    property Item screenItem
    /// Seconds, for the gentle camera drift.
    property real time: 0
    property color glowColor: "white"
    /// Let the user move the camera (and the gentle drift and parallax).
    property bool lookAround: true
    /// Show the sticky notes.
    property bool stickyNotes: true

    // Idle orbit: after idleOrbitMinutes with no typing or mouse use (0 =
    // never), the camera swings slowly back and forth around the monitor,
    // and glides back on the next key press or mouse movement.
    property int idleOrbitMinutes: 0
    /// "slow", "normal" or "fast".
    property string idleOrbitSpeed: "normal"
    /// When the user last typed or used the mouse (ms since the epoch).
    property real lastUserInput: Date.now()
    /// Called on mouse use in the room; key presses come from the terminal.
    signal userInput()
    readonly property bool idleOrbiting: idleOrbitMinutes > 0 && !pictureView && orbitClock.idle
    /// 0 at rest, 1 while orbiting; eases between the two.
    property real orbitAmount: idleOrbiting ? 1 : 0
    Behavior on orbitAmount { NumberAnimation { duration: 2500; easing.type: Easing.InOutSine } }
    property real orbitPhase: 0
    property real lastOrbitTime: 0
    /// How far it swings: less when the camera is far back, so it stays
    /// inside the room (the cubicle's walls are about 90 cm to each side).
    readonly property real orbitAmplitude: Math.min(35, Math.asin(Math.min(1, 75 / Math.max(distance, 1))) * 180 / Math.PI)
    onTimeChanged: {
        const dt = Math.min(Math.max(time - lastOrbitTime, 0), 0.5)
        lastOrbitTime = time
        if (orbitAmount > 0) {
            const peak = idleOrbitSpeed === "slow" ? 2 : idleOrbitSpeed === "fast" ? 8 : 4   // degrees a second
            // yaw = amplitude * sin(phase), so the peak speed is amplitude * dphase/dt.
            orbitPhase += dt * peak / Math.max(orbitAmplitude, 1)
        }
    }
    Timer {
        id: orbitClock
        property bool idle: false
        interval: 1000
        repeat: true
        running: view.idleOrbitMinutes > 0 && !view.pictureView
        onTriggered: {
            idle = Date.now() - view.lastUserInput > view.idleOrbitMinutes * 60000
            // Keep the effects (and so the room) animating while the orbit
            // is due, even with "pause effects when idle" on.
            if (typeof timeManager !== "undefined")
                timeManager.noteActivity()
        }
        onRunningChanged: if (!running) idle = false
    }
    onLastUserInputChanged: orbitClock.idle = false
    /// The desk (officeDesk.notes and officeDesk.events). When set, the
    /// sticky notes go on the room's note places in order, and the calendar
    /// shows the events; otherwise (the 2D pictures) the first three places
    /// get scribbled notes and the calendar its picture.
    property var deskNotes
    property var deskEvents: []
    readonly property bool deskLive: deskNotes !== undefined && deskNotes !== null
    /// Double-clicking a note (what: "note:<id>") or a day on the calendar
    /// (what: "calendar", date: "YYYY-MM-DD", or "" between the days).
    signal editRequested(string what, string date)

    property Item calendarFace: CalendarFace {
        events: view.deskEvents || []
    }
    /// How far back the camera starts: "close" (the screen fills most of the
    /// window), "desk" or "room".
    property string zoom: "desk"
    // Computed here rather than in bindings, so a change of zoom always
    // uses the new value.
    function zoomFactor() { return pictureView ? 1 : zoom === "close" ? 0.55 : zoom === "room" ? 1.9 : 1 }
    function zoomPitch() { return !pictureView && zoom === "room" ? -8 : 0 }
    onZoomChanged: resetView()
    /// Show the room straight on, as in the 2D picture (used to render it).
    property bool pictureView: false
    readonly property bool moving: lookAround && !pictureView

    property var room: ({})
    readonly property var cameraInfo: room.camera || null
    readonly property var viewInfo: pictureView && room.picture ? room.picture.camera : cameraInfo

    // Where the camera is: an orbit around the screen.
    property real yaw: 0
    property real pitch: 0
    property real distance: 100
    // Pointer position for parallax, -1 to 1 from the centre.
    property real pointerX: 0
    property real pointerY: 0

    function resetView() {
        if (!viewInfo)
            return
        yaw = viewInfo.yaw
        pitch = viewInfo.pitch + zoomPitch()
        distance = viewInfo.distance * zoomFactor()
    }
    Behavior on distance { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
    Behavior on pitch { enabled: !orbit.active; NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
    onMovingChanged: if (!moving) resetView()
    onPictureViewChanged: resetView()

    function clamp(v, lo, hi) { return Math.min(Math.max(v, lo), hi) }

    function load() {
        const request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState === XMLHttpRequest.DONE && request.responseText) {
                view.room = JSON.parse(request.responseText)
                view.resetView()
            }
        }
        request.open("GET", Qt.resolvedUrl("office/office-" + scene + "-" + monitor + ".json"))
        request.send()
    }
    onSceneChanged: load()
    onMonitorChanged: load()
    Component.onCompleted: load()

    function vec(a) { return Qt.vector3d(a[0], a[1], a[2]) }
    // A "mesh" object's geometry. Created by name, so this file still loads
    // where QtQuick3D.Helpers (or ProceduralMesh in it) isn't available.
    function makeMesh(data, parent) {
        if (!data || !data.positions || !data.normals || !data.indices
                || data.positions.length % 3 !== 0 || data.normals.length !== data.positions.length)
            return null
        let mesh
        try {
            mesh = Qt.createQmlObject("import QtQuick3D.Helpers; ProceduralMesh {}", parent, "OfficeMesh")
        } catch (error) {
            console.warn("Office mode: can't draw smooth meshes with this Qt (needs 6.6), showing the picture instead.")
            meshFailed = true
            return null
        }
        const count = data.positions.length / 3
        let positions = [], normals = []
        for (let i = 0; i < count; ++i) {
            positions.push(Qt.vector3d(data.positions[3 * i], data.positions[3 * i + 1], data.positions[3 * i + 2]))
            normals.push(Qt.vector3d(data.normals[3 * i], data.normals[3 * i + 1], data.normals[3 * i + 2]))
        }
        mesh.positions = positions
        mesh.normals = normals
        mesh.indexes = data.indices.filter(i => Number.isInteger(i) && i >= 0 && i < count)
        return mesh
    }
    function quat(a) { return Qt.quaternion(a[3], a[0], a[1], a[2]) }

    // Quaternion product a * b, as [x, y, z, w].
    function mul(a, b) {
        return [a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
                a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
                a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
                a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]]
    }
    function axisAngle(axis, degrees) {
        const h = degrees * Math.PI / 360
        const q = [0, 0, 0, Math.cos(h)]
        q[axis] = Math.sin(h)
        return q
    }
    function colorScaled(c, s) { return Qt.rgba(c.r * s, c.g * s, c.b * s, 1) }

    // Point lights fade to about half their brightness at half their range.
    function quadraticFade(range) { return 40000 / (range * range) }

    environment: SceneEnvironment {
        clearColor: view.room.background || "black"
        backgroundMode: SceneEnvironment.Color
        antialiasingMode: SceneEnvironment.MSAA
        antialiasingQuality: SceneEnvironment.High
    }

    PerspectiveCamera {
        id: camera
        readonly property real motion: view.moving ? 1 : 0
        readonly property real drift: 1.2 * Math.sin(view.time * 0.11) * motion
        readonly property real driftPitch: 0.6 * Math.sin(view.time * 0.17) * motion
        readonly property real orbitYaw: view.orbitAmount * view.orbitAmplitude * Math.sin(view.orbitPhase)
        readonly property real orbitPitch: view.orbitAmount * 5 * Math.sin(view.orbitPhase * 0.62)
        readonly property real effectiveYaw: view.yaw + drift + view.pointerX * 3 * motion + orbitYaw
        readonly property real effectivePitch: view.pitch + driftPitch - view.pointerY * 2 * motion + orbitPitch
        readonly property var orientation: view.mul(view.axisAngle(1, effectiveYaw), view.axisAngle(0, effectivePitch))
        readonly property var target: view.viewInfo ? view.viewInfo.target : [0, 0, 0]
        readonly property real yawRad: effectiveYaw * Math.PI / 180
        readonly property real pitchRad: effectivePitch * Math.PI / 180

        fieldOfView: view.cameraInfo ? view.cameraInfo.fov : 40
        clipNear: view.cameraInfo ? view.cameraInfo.near : 1
        clipFar: view.cameraInfo ? view.cameraInfo.far : 5000
        position: Qt.vector3d(target[0] + view.distance * Math.sin(yawRad) * Math.cos(pitchRad),
                              target[1] - view.distance * Math.sin(pitchRad),
                              target[2] + view.distance * Math.cos(yawRad) * Math.cos(pitchRad))
        rotation: view.quat(orientation)
    }

    // Ambient light rides on an otherwise dark light.
    DirectionalLight {
        brightness: 0
        ambientColor: view.room.ambient ? view.colorScaled(view.room.ambient.color, view.room.ambient.intensity)
                                        : "black"
    }

    Repeater3D {
        model: view.room.lights || []
        delegate: Node {
            id: lightNode
            required property var modelData
            DirectionalLight {
                visible: lightNode.modelData.type === "directional"
                rotation: view.quat(lightNode.modelData.rotation || [0, 0, 0, 1])
                color: lightNode.modelData.color
                brightness: lightNode.modelData.intensity
                castsShadow: lightNode.modelData.shadows === true
                shadowMapQuality: Light.ShadowMapQualityHigh
                shadowFactor: 60
                shadowBias: 2
                shadowMapFar: 1200
            }
            PointLight {
                visible: lightNode.modelData.type === "point"
                position: view.vec(lightNode.modelData.position || [0, 0, 0])
                color: lightNode.modelData.color
                brightness: lightNode.modelData.intensity
                constantFade: 1
                linearFade: 0
                quadraticFade: view.quadraticFade(lightNode.modelData.range || 200)
            }
        }
    }

    // Light from the screen, in the profile's text colour.
    PointLight {
        visible: view.room.screenGlow !== undefined
        position: view.room.screenGlow ? view.vec(view.room.screenGlow.position) : Qt.vector3d(0, 0, 0)
        color: view.glowColor
        brightness: view.room.screenGlow ? view.room.screenGlow.intensity : 0
        constantFade: 1
        linearFade: 0
        quadraticFade: view.quadraticFade(view.room.screenGlow ? view.room.screenGlow.range : 100)
    }

    Repeater3D {
        model: view.room.objects || []
        delegate: Model {
            id: object
            required property var modelData
            visible: modelData.group !== "sticky-notes" || view.stickyNotes
            // Notes and the calendar show the desk's contents.
            readonly property string live: modelData.live || ""
            readonly property Item liveFace: view.deskLive && live === "calendar" ? view.calendarFace : null
            readonly property var shapes: ({ "box": "#Cube", "cylinder": "#Cylinder",
                                             "sphere": "#Sphere", "plane": "#Rectangle" })
            readonly property bool isMesh: modelData.shape === "mesh"
            source: isMesh ? "" : shapes[modelData.shape]
            geometry: isMesh ? view.makeMesh(modelData.mesh, object) : null
            position: view.vec(modelData.position)
            // The built-in meshes are 100 units across; a "mesh" is in centimetres.
            readonly property real unit: isMesh ? 1 : 100
            scale: Qt.vector3d(modelData.size[0] / unit, modelData.size[1] / unit, modelData.size[2] / unit)
            rotation: view.quat(modelData.rotation)
            castsShadows: modelData.shadows
            receivesShadows: true
            materials: PrincipledMaterial {
                baseColor: object.modelData.color
                // See-through objects (glass, water, bubbles).
                opacity: object.modelData.opacity !== undefined ? object.modelData.opacity : 1
                roughness: object.modelData.roughness
                metalness: object.modelData.metalness
                baseColorMap: object.liveFace ? liveTexture : object.modelData.texture ? texture : null
                emissiveMap: object.modelData.emissive && object.modelData.texture ? texture : null
                emissiveFactor: object.modelData.emissive
                                ? Qt.vector3d(Qt.color(object.modelData.emissive).r, Qt.color(object.modelData.emissive).g,
                                              Qt.color(object.modelData.emissive).b)
                                : Qt.vector3d(0, 0, 0)
                Texture {
                    id: liveTexture
                    sourceItem: object.liveFace
                }
                Texture {
                    id: texture
                    source: object.modelData.texture ? "office/" + object.modelData.texture : ""
                    scaleU: object.modelData.repeat ? object.modelData.repeat[0] : 1
                    scaleV: object.modelData.repeat ? object.modelData.repeat[1] : 1
                    tilingModeHorizontal: Texture.Repeat
                    tilingModeVertical: Texture.Repeat
                    generateMipmaps: true
                    mipFilter: Texture.Linear
                }
            }
        }
    }

    // The sticky notes, on the room's note places in order.
    Repeater3D {
        model: view.room.noteSpots || []
        delegate: Model {
            id: noteModel
            required property var modelData
            required property int index
            readonly property var note: view.deskLive && index < view.deskNotes.length ? view.deskNotes[index] : null
            property Item face: StickyNoteFace {
                text: noteModel.note ? noteModel.note.text : ""
                paper: noteModel.note ? noteModel.note.color : "yellow"
            }
            visible: view.stickyNotes && (view.deskLive ? noteModel.note !== null : !!modelData.texture)
            source: "#Rectangle"
            position: view.vec(modelData.position)
            scale: Qt.vector3d(modelData.size / 100, modelData.size / 100, 1)
            rotation: view.quat(modelData.rotation)
            castsShadows: false
            receivesShadows: true
            materials: PrincipledMaterial {
                roughness: 0.7
                baseColorMap: view.deskLive ? noteFaceTexture : noteScribble
                Texture { id: noteFaceTexture; sourceItem: view.deskLive ? noteModel.face : null }
                Texture { id: noteScribble; source: noteModel.modelData.texture ? "office/" + noteModel.modelData.texture : "" }
            }
        }
    }

    // The monitor's screen, showing the terminal. Unlit, so it shows the
    // CRT's own colours; pickable, so clicks reach the terminal.
    Model {
        id: screenModel
        visible: view.room.screen !== undefined
        source: "#Rectangle"
        pickable: true
        position: view.room.screen ? view.vec(view.room.screen.position) : Qt.vector3d(0, 0, 0)
        scale: view.room.screen ? Qt.vector3d(view.room.screen.size[0] / 100, view.room.screen.size[1] / 100, 1)
                                : Qt.vector3d(1, 1, 1)
        rotation: view.room.screen ? view.quat(view.room.screen.rotation) : Qt.quaternion(1, 0, 0, 0)
        materials: DefaultMaterial {
            lighting: DefaultMaterial.NoLighting
            diffuseMap: Texture { sourceItem: view.screenItem }
        }
    }

    /// The note or calendar under a point in the view, if it's the nearest
    /// thing there: {what: "note:<id>" or "calendar" or "", date: the
    /// calendar day under the point, if any}. Worked out here
    /// rather than with pick(), so that clicks on the room's objects aren't
    /// taken by the view and still reach the double-click handler below.
    function liveObjectAt(x, y) {
        if (!room.objects)
            return { what: "", date: "" }
        const p0 = camera.mapFromViewport(Qt.vector3d(x / width, y / height, 0))
        const p1 = camera.mapFromViewport(Qt.vector3d(x / width, y / height, 100))
        let found = "", nearest = Infinity, hitU = 0, hitV = 0
        let candidates = room.objects.concat(room.screen ? [{ shape: "plane", position: room.screen.position,
            size: [room.screen.size[0], room.screen.size[1], 1], rotation: room.screen.rotation }] : [])
        if (deskLive && stickyNotes) {
            const spots = room.noteSpots || []
            for (let i = 0; i < Math.min(spots.length, deskNotes.length); ++i)
                candidates.push({ shape: "plane", position: spots[i].position, size: [spots[i].size, spots[i].size, 1],
                                  rotation: spots[i].rotation, live: "note:" + deskNotes[i].id })
        }
        for (const o of candidates) {
            if (o.shape === "mesh")
                continue
            // The ray in the object's own unit space: a 1 x 1 square at z = 0
            // for a plane, a 1 x 1 x 1 box for anything else.
            const inverse = quat(o.rotation).inverted()
            const a = inverse.times(p0.minus(vec(o.position)))
            const b = inverse.times(p1.minus(vec(o.position)))
            const o0 = [a.x / o.size[0], a.y / o.size[1], a.z / o.size[2]]
            const d = [(b.x - a.x) / o.size[0], (b.y - a.y) / o.size[1], (b.z - a.z) / o.size[2]]
            let t
            if (o.shape === "plane") {
                if (Math.abs(b.z - a.z) < 1e-9)
                    continue
                t = -a.z / (b.z - a.z)
                if (Math.abs(o0[0] + d[0] * t) > 0.5 || Math.abs(o0[1] + d[1] * t) > 0.5)
                    continue
            } else {
                let enter = -Infinity, leave = Infinity
                for (let i = 0; i < 3; ++i) {
                    if (Math.abs(d[i]) < 1e-12) {
                        if (Math.abs(o0[i]) > 0.5) { enter = Infinity; break }
                        continue
                    }
                    const t1 = (-0.5 - o0[i]) / d[i], t2 = (0.5 - o0[i]) / d[i]
                    enter = Math.max(enter, Math.min(t1, t2))
                    leave = Math.min(leave, Math.max(t1, t2))
                }
                if (enter > leave || leave < 0)
                    continue
                t = Math.max(enter, 0)
            }
            if (t >= 0 && t < nearest) {
                nearest = t
                found = o.live || ""
                hitU = o0[0] + d[0] * t + 0.5
                hitV = 0.5 - (o0[1] + d[1] * t)
            }
        }
        return { what: found, date: found === "calendar" ? calendarFace.dateAt(hitU, hitV) : "" }
    }

    // Double-click a sticky note or the calendar to edit it.
    TapHandler {
        acceptedModifiers: Qt.NoModifier
        onDoubleTapped: (eventPoint) => {
            const hit = view.liveObjectAt(eventPoint.position.x, eventPoint.position.y)
            if (hit.what)
                view.editRequested(hit.what, hit.date)
        }
    }

    // Looking around: Option/Alt-drag, Option/Alt-scroll or pinch, and
    // Option/Alt-double-click to reset. Everything else goes to the terminal.
    DragHandler {
        id: orbit
        enabled: view.moving
        target: null
        acceptedModifiers: Qt.AltModifier
        property real startYaw: 0
        property real startPitch: 0
        onActiveChanged: if (active) { startYaw = view.yaw; startPitch = view.pitch }
        onTranslationChanged: {
            if (!active || !view.cameraInfo)
                return
            view.yaw = view.clamp(startYaw - translation.x * 0.25, view.cameraInfo.minYaw, view.cameraInfo.maxYaw)
            view.pitch = view.clamp(startPitch - translation.y * 0.2, view.cameraInfo.minPitch, view.cameraInfo.maxPitch)
        }
    }
    WheelHandler {
        enabled: view.moving
        acceptedModifiers: Qt.AltModifier
        onWheel: (event) => {
            if (!view.cameraInfo)
                return
            const steps = (event.angleDelta.y || event.angleDelta.x) / 120
            view.distance = view.clamp(view.distance * Math.pow(0.9, steps),
                                       view.cameraInfo.minDistance, view.cameraInfo.maxDistance)
        }
    }
    PinchHandler {
        enabled: view.moving
        target: null
        property real startDistance: 100
        onActiveChanged: if (active) startDistance = view.distance
        onActiveScaleChanged: if (view.cameraInfo) view.distance = view.clamp(startDistance / activeScale,
                                  view.cameraInfo.minDistance, view.cameraInfo.maxDistance)
    }
    TapHandler {
        enabled: view.moving
        acceptedModifiers: Qt.AltModifier
        onDoubleTapped: view.resetView()
    }
    // Any mouse use in the room ends the idle orbit.
    HoverHandler {
        onPointChanged: view.userInput()
    }
    HoverHandler {
        enabled: view.moving
        id: hover
        onPointChanged: {
            view.pointerX = view.clamp(point.position.x / Math.max(view.width, 1) * 2 - 1, -1, 1)
            view.pointerY = view.clamp(point.position.y / Math.max(view.height, 1) * 2 - 1, -1, 1)
        }
    }
}
