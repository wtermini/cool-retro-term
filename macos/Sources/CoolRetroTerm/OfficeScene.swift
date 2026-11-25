/*
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
 */

import AppKit
import Metal
import SceneKit
import simd

/// Office mode: the terminal is the screen of a monitor on a desk in a 3D
/// room, drawn with SceneKit on Metal (OfficeSceneView), or, with 3D turned
/// off, over a picture of the same room (OfficePictureView). Shared with the Qt app (`officeScene` in its settings, and
/// app/qml/OfficeScene.qml, which builds the same rooms with Qt Quick 3D).
///
/// The rooms are described in office/office-<scene>.json, made by
/// scripts/generate-office-scenes.py.
enum OfficeScene: String, CaseIterable {
    case off = ""
    case eighties = "80s"
    case nineties = "90s"

    var title: String {
        switch self {
        case .off: return "Off"
        case .eighties: return "80s Den"
        case .nineties: return "90s Cubicle"
        }
    }
}

/// A room, as written by scripts/generate-office-scenes.py.
struct OfficeRoom: Decodable {
    struct Camera: Decodable {
        var target: [Float]
        var distance, yaw, pitch, fov, near, far: Float
        var minDistance, maxDistance, minYaw, maxYaw, minPitch, maxPitch: Float
    }
    struct Ambient: Decodable { var color: String; var intensity: Float }
    struct Light: Decodable {
        var type: String
        var color: String
        var intensity: Float
        var rotation: [Float]?
        var position: [Float]?
        var range: Float?
        var shadows: Bool?
    }
    struct Screen: Decodable { var position: [Float]; var size: [Float]; var rotation: [Float] }
    struct Glow: Decodable { var position: [Float]; var intensity: Float; var range: Float }
    /// The room seen straight on, for 2D: rectangles are in the picture's
    /// pixels, from the top left.
    struct Picture: Decodable {
        var image: String
        var size: [CGFloat]
        var fill: String
        var screen: [CGFloat]
        var monitor: [CGFloat]
    }
    struct Object: Decodable {
        var shape: String
        var position: [Float]
        var size: [Float]
        var rotation: [Float]
        var color: String
        var roughness: Float
        var metalness: Float
        var shadows: Bool
        var texture: String?
        var repeats: [Float]?
        var emissive: String?

        enum CodingKeys: String, CodingKey {
            case shape, position, size, rotation, color, roughness, metalness, shadows, texture, emissive
            case repeats = "repeat"
        }
    }

    var background: String
    var ambient: Ambient
    var camera: Camera
    var screen: Screen
    var screenGlow: Glow
    var picture: Picture
    var lights: [Light]
    var objects: [Object]

    static func load(_ scene: OfficeScene) -> OfficeRoom? {
        guard scene != .off else { return nil }
        return AppResources.decode(OfficeRoom.self, from: "Office/office-\(scene.rawValue).json")
    }
}

/// Office mode in 2D: a picture of the room (rendered from the 3D room,
/// straight on) behind the terminal, which goes over the monitor's screen.
final class OfficePictureView: NSView {
    private(set) var officeScene: OfficeScene = .off
    private var picture: OfficeRoom.Picture?
    private let imageLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isHidden = true
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        imageLayer.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// For snapshots: the picture and where it's drawn.
    var imageFrame: CGRect { imageLayer.frame }
    var image: CGImage? { (imageLayer.contents as? NSImage)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    var fillColor: NSColor { picture.map { NSColor(hex: $0.fill) } ?? .black }

    func show(_ scene: OfficeScene) {
        guard scene != officeScene else { return }
        officeScene = scene
        picture = OfficeRoom.load(scene)?.picture
        isHidden = picture == nil
        if let picture {
            imageLayer.contents = NSImage(contentsOf: AppResources.url("Office/\(picture.image)"))
            layer?.backgroundColor = NSColor(hex: picture.fill).cgColor
        }
        needsLayout = true
    }

    /// Fills the view with the picture, centred on the monitor, zooming out
    /// further if needed so the whole monitor stays in view. Returns where
    /// the terminal goes, in this view's coordinates.
    func layoutPicture() -> CGRect? {
        guard let picture else { return nil }
        let size = bounds.size
        let imageSize = CGSize(width: picture.size[0], height: picture.size[1])
        let m = CGRect(x: picture.monitor[0], y: picture.monitor[1], width: picture.monitor[2], height: picture.monitor[3])
        var scale = max(size.width / imageSize.width, size.height / imageSize.height)
        scale = min(scale, size.width / m.width, size.height / m.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        func offset(_ view: CGFloat, _ image: CGFloat, _ centre: CGFloat) -> CGFloat {
            guard image >= view else { return (view - image) / 2 }
            return min(max(view / 2 - centre * scale, view - image), 0)
        }
        let x = offset(size.width, w, m.midX)
        let top = offset(size.height, h, m.midY)
        imageLayer.frame = CGRect(x: x, y: size.height - top - h, width: w, height: h)
        let s = picture.screen
        return CGRect(x: x + s[0] * scale, y: size.height - top - (s[1] + s[3]) * scale,
                      width: s[2] * scale, height: s[3] * scale).integral
    }
}

/// Draws the room with SceneKit, over the terminal, and turns clicks on the
/// monitor's screen into clicks on the terminal. Option-drag looks around,
/// Option-scroll or pinch zooms, and Option-double-click goes back to the
/// starting view.
final class OfficeSceneView: SCNView {
    weak var host: CRTTerminalView?

    private(set) var officeScene: OfficeScene = .off
    private var room: OfficeRoom?
    private let cameraNode = SCNNode()
    private var screenNode: SCNNode?
    private var glowLight: SCNLight?

    // Orbit around the screen, plus a gentle drift and pointer parallax.
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var distance: Float = 100
    private var pointer = SIMD2<Float>(0, 0)
    private var time: Float = 0
    private var orbitStart: (point: NSPoint, yaw: Float, pitch: Float)?

    /// Let the user move the camera, with the gentle drift and parallax.
    var lookAround = true {
        didSet {
            guard lookAround != oldValue else { return }
            if !lookAround {
                pointer = .zero
                orbitStart = nil
                resetView()
            }
        }
    }

    init(frame: NSRect, device: MTLDevice?) {
        var options: [String: Any] = [
            SCNView.Option.preferredRenderingAPI.rawValue: NSNumber(value: SCNRenderingAPI.metal.rawValue)
        ]
        if let device { options[SCNView.Option.preferredDevice.rawValue] = device }
        super.init(frame: frame, options: options)
        antialiasingMode = .multisampling4X
        isPlaying = false
        rendersContinuously = false
        isHidden = true
        allowsCameraControl = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Building the room

    func show(_ newScene: OfficeScene) {
        guard newScene != officeScene else { return }
        officeScene = newScene
        isHidden = newScene == .off
        guard let room = OfficeRoom.load(newScene) else {
            scene = nil
            self.room = nil
            screenNode = nil
            return
        }
        self.room = room
        scene = build(room)
        pointOfView = cameraNode
        resetView()
    }

    var screenTexture: MTLTexture? {
        didSet { screenNode?.geometry?.firstMaterial?.diffuse.contents = screenTexture }
    }

    var glowColor: NSColor = .white {
        didSet { glowLight?.color = glowColor }
    }

    func setRunning(_ running: Bool, framesPerSecond: Int) {
        preferredFramesPerSecond = framesPerSecond
        rendersContinuously = running
        isPlaying = running
    }

    func resetView() {
        guard let camera = room?.camera else { return }
        yaw = camera.yaw
        pitch = camera.pitch
        distance = camera.distance
        updateCamera()
    }

    /// Called at the effects frame rate, with seconds since launch.
    func tick(time: Double) {
        self.time = Float(time)
        updateCamera()
    }

    private func build(_ room: OfficeRoom) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor(hex: room.background)
        var textures: [String: NSImage] = [:]
        func texture(_ name: String) -> NSImage? {
            if let cached = textures[name] { return cached }
            let image = NSImage(contentsOf: AppResources.url("Office/\(name)"))
            textures[name] = image
            return image
        }

        for object in room.objects {
            let geometry: SCNGeometry
            switch object.shape {
            case "box": geometry = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
            case "cylinder": geometry = SCNCylinder(radius: 0.5, height: 1)
            case "sphere":
                let sphere = SCNSphere(radius: 0.5)
                sphere.segmentCount = 32
                geometry = sphere
            default: geometry = SCNPlane(width: 1, height: 1)
            }
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            let color = NSColor(hex: object.color)
            if let name = object.texture, let image = texture(name) {
                material.diffuse.contents = image
                let scale = object.repeats ?? [1, 1]
                material.diffuse.contentsTransform = SCNMatrix4MakeScale(CGFloat(scale[0]), CGFloat(scale[1]), 1)
                material.diffuse.wrapS = .repeat
                material.diffuse.wrapT = .repeat
                material.diffuse.mipFilter = .linear
                if object.color.lowercased() != "#ffffff" { material.multiply.contents = color }
                if object.emissive != nil {
                    material.emission.contents = image
                    material.emission.contentsTransform = material.diffuse.contentsTransform
                }
            } else {
                material.diffuse.contents = color
                if let emissive = object.emissive { material.emission.contents = NSColor(hex: emissive) }
            }
            material.roughness.contents = NSNumber(value: object.roughness)
            material.metalness.contents = NSNumber(value: object.metalness)
            geometry.materials = [material]

            let node = SCNNode(geometry: geometry)
            node.simdPosition = vector(object.position)
            node.simdScale = vector(object.size)
            node.simdOrientation = quaternion(object.rotation)
            node.castsShadow = object.shadows
            scene.rootNode.addChildNode(node)
        }

        // The monitor's screen: unlit, so it shows the CRT's own colours.
        let screenMaterial = SCNMaterial()
        screenMaterial.lightingModel = .constant
        screenMaterial.diffuse.contents = screenTexture ?? NSColor.black
        let plane = SCNPlane(width: 1, height: 1)
        plane.materials = [screenMaterial]
        let screen = SCNNode(geometry: plane)
        screen.simdPosition = vector(room.screen.position)
        screen.simdScale = SIMD3(room.screen.size[0], room.screen.size[1], 1)
        screen.simdOrientation = quaternion(room.screen.rotation)
        screen.castsShadow = false
        scene.rootNode.addChildNode(screen)
        screenNode = screen

        // Lights. Intensities in the scene files are in Qt Quick 3D's units,
        // where 1 is about SceneKit's default of 1000.
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = NSColor(hex: room.ambient.color)
        ambient.intensity = CGFloat(room.ambient.intensity * 1000)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        for info in room.lights {
            let light = SCNLight()
            light.color = NSColor(hex: info.color)
            light.intensity = CGFloat(info.intensity * 1000)
            let node = SCNNode()
            if info.type == "directional" {
                light.type = .directional
                light.castsShadow = info.shadows ?? false
                light.shadowMapSize = CGSize(width: 2048, height: 2048)
                light.shadowRadius = 3
                light.shadowSampleCount = 8
                light.shadowColor = NSColor(white: 0, alpha: 0.6)
                light.automaticallyAdjustsShadowProjection = true
                node.simdOrientation = quaternion(info.rotation ?? [0, 0, 0, 1])
            } else {
                Self.configurePoint(light, range: info.range ?? 200)
                node.simdPosition = vector(info.position ?? [0, 0, 0])
            }
            node.light = light
            scene.rootNode.addChildNode(node)
        }

        let glow = SCNLight()
        Self.configurePoint(glow, range: room.screenGlow.range)
        glow.color = glowColor
        glow.intensity = CGFloat(room.screenGlow.intensity * 1000)
        let glowNode = SCNNode()
        glowNode.light = glow
        glowNode.simdPosition = vector(room.screenGlow.position)
        scene.rootNode.addChildNode(glowNode)
        glowLight = glow

        let camera = SCNCamera()
        camera.projectionDirection = .vertical
        camera.fieldOfView = CGFloat(room.camera.fov)
        camera.zNear = Double(room.camera.near)
        camera.zFar = Double(room.camera.far)
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        return scene
    }

    /// Point lights fade to about half their brightness at half their range,
    /// as in the Qt app.
    private static func configurePoint(_ light: SCNLight, range: Float) {
        light.type = .omni
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = CGFloat(range * 1.7)
        light.attenuationFalloffExponent = 2
    }

    private func updateCamera() {
        guard let camera = room?.camera else { return }
        let motion: Float = lookAround ? 1 : 0
        let effectiveYaw = yaw + (1.2 * sin(time * 0.11) + pointer.x * 3) * motion
        let effectivePitch = pitch + (0.6 * sin(time * 0.17) - pointer.y * 2) * motion
        let yawRad = effectiveYaw * .pi / 180
        let pitchRad = effectivePitch * .pi / 180
        let target = vector(camera.target)
        cameraNode.simdPosition = target + SIMD3(distance * sin(yawRad) * cos(pitchRad),
                                                 -distance * sin(pitchRad),
                                                 distance * cos(yawRad) * cos(pitchRad))
        cameraNode.simdOrientation = simd_quatf(angle: yawRad, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: pitchRad, axis: SIMD3(1, 0, 0))
    }

    // MARK: Input

    /// Where `event` points on the screen, as texture coordinates (0 to 1,
    /// origin at the top left), even outside the screen, as when dragging.
    func screenUV(for event: NSEvent) -> SIMD2<Float>? {
        guard let screenNode else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let near = unprojectPoint(SCNVector3(point.x, point.y, 0))
        let far = unprojectPoint(SCNVector3(point.x, point.y, 1))
        let a = screenNode.simdConvertPosition(SIMD3(Float(near.x), Float(near.y), Float(near.z)), from: nil)
        let b = screenNode.simdConvertPosition(SIMD3(Float(far.x), Float(far.y), Float(far.z)), from: nil)
        let dz = b.z - a.z
        guard abs(dz) > 1e-6 else { return nil }
        let t = -a.z / dz
        guard t > 0 else { return nil }
        let hit = a + (b - a) * t
        return SIMD2(hit.x + 0.5, 0.5 - hit.y)
    }

    private func isOverScreen(_ event: NSEvent) -> Bool {
        guard let uv = screenUV(for: event) else { return false }
        return uv.x >= 0 && uv.x <= 1 && uv.y >= 0 && uv.y <= 1
    }

    private func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float { min(max(v, lo), hi) }

    override func mouseDown(with event: NSEvent) {
        if lookAround, event.modifierFlags.contains(.option) {
            if event.clickCount == 2 {
                resetView()
            } else {
                orbitStart = (convert(event.locationInWindow, from: nil), yaw, pitch)
            }
            return
        }
        forward(event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let start = orbitStart, let camera = room?.camera {
            let point = convert(event.locationInWindow, from: nil)
            yaw = clamp(start.yaw - Float(point.x - start.point.x) * 0.25, camera.minYaw, camera.maxYaw)
            pitch = clamp(start.pitch + Float(point.y - start.point.y) * 0.2, camera.minPitch, camera.maxPitch)
            updateCamera()
            return
        }
        forward(event)
    }

    override func mouseUp(with event: NSEvent) {
        if orbitStart != nil {
            orbitStart = nil
            return
        }
        forward(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let host, !host.programUsesMouse, let menu = host.terminal.menu {
            NSMenu.popUpContextMenu(menu, with: event, for: host.terminal)
        } else {
            forward(event)
        }
    }
    override func rightMouseDragged(with event: NSEvent) { forward(event) }
    override func rightMouseUp(with event: NSEvent) { forward(event) }
    override func otherMouseDown(with event: NSEvent) { forward(event) }
    override func otherMouseDragged(with event: NSEvent) { forward(event) }
    override func otherMouseUp(with event: NSEvent) { forward(event) }

    override func scrollWheel(with event: NSEvent) {
        if lookAround, event.modifierFlags.contains(.option), let camera = room?.camera {
            let delta = Float(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 30 : event.scrollingDeltaY)
            distance = clamp(distance * pow(0.9, delta), camera.minDistance, camera.maxDistance)
            updateCamera()
            return
        }
        host?.terminal.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        guard lookAround, let camera = room?.camera else { return }
        distance = clamp(distance / Float(1 + event.magnification), camera.minDistance, camera.maxDistance)
        updateCamera()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if lookAround {
            pointer = SIMD2(clamp(Float(point.x / max(bounds.width, 1)) * 2 - 1, -1, 1),
                            clamp(1 - Float(point.y / max(bounds.height, 1)) * 2, -1, 1))
            updateCamera()
        }
        let textCursor = isOverScreen(event) && !(host?.programUsesMouse ?? false)
        (textCursor ? NSCursor.iBeam : NSCursor.arrow).set()
    }

    private func forward(_ event: NSEvent) {
        guard let uv = screenUV(for: event) else { return }
        host?.forwardMouse(event, screenUV: uv)
    }
}

private func vector(_ a: [Float]) -> SIMD3<Float> { SIMD3(a[0], a[1], a[2]) }
private func quaternion(_ a: [Float]) -> simd_quatf { simd_quatf(ix: a[0], iy: a[1], iz: a[2], r: a[3]) }

extension NSColor {
    /// "#rrggbb", as used in the scene files.
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                  blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }
}
