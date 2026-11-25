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
/// The rooms are described in office/office-<scene>.json, made by
/// scripts/generate-office-scenes.py and shared with Cool Retro Term SE,
/// which builds the same rooms with SceneKit (OfficeScene.swift).
View3D {
    id: view

    /// "80s" or "90s".
    property string scene: "80s"
    /// The item shown on the monitor's screen (the terminal).
    property Item screenItem
    /// Seconds, for the gentle camera drift.
    property real time: 0
    property color glowColor: "white"
    /// Let the user move the camera (and the gentle drift and parallax).
    property bool lookAround: true
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
        pitch = viewInfo.pitch
        distance = viewInfo.distance
    }
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
        request.open("GET", Qt.resolvedUrl("office/office-" + scene + ".json"))
        request.send()
    }
    onSceneChanged: load()
    Component.onCompleted: load()

    function vec(a) { return Qt.vector3d(a[0], a[1], a[2]) }
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
        readonly property real effectiveYaw: view.yaw + drift + view.pointerX * 3 * motion
        readonly property real effectivePitch: view.pitch + driftPitch - view.pointerY * 2 * motion
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
            readonly property var shapes: ({ "box": "#Cube", "cylinder": "#Cylinder",
                                             "sphere": "#Sphere", "plane": "#Rectangle" })
            source: shapes[modelData.shape]
            position: view.vec(modelData.position)
            // The built-in meshes are 100 units across.
            scale: Qt.vector3d(modelData.size[0] / 100, modelData.size[1] / 100, modelData.size[2] / 100)
            rotation: view.quat(modelData.rotation)
            castsShadows: modelData.shadows
            receivesShadows: true
            materials: PrincipledMaterial {
                baseColor: object.modelData.color
                roughness: object.modelData.roughness
                metalness: object.modelData.metalness
                baseColorMap: object.modelData.texture ? texture : null
                emissiveMap: object.modelData.emissive && object.modelData.texture ? texture : null
                emissiveFactor: object.modelData.emissive
                                ? Qt.vector3d(Qt.color(object.modelData.emissive).r, Qt.color(object.modelData.emissive).g,
                                              Qt.color(object.modelData.emissive).b)
                                : Qt.vector3d(0, 0, 0)
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
    HoverHandler {
        enabled: view.moving
        id: hover
        onPointChanged: {
            view.pointerX = view.clamp(point.position.x / Math.max(view.width, 1) * 2 - 1, -1, 1)
            view.pointerY = view.clamp(point.position.y / Math.max(view.height, 1) * 2 - 1, -1, 1)
        }
    }
}
