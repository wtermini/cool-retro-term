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
import MetalKit
import SwiftTerm

/// SwiftTerm's local-process terminal, with a hook that reports when its
/// contents need to be captured again.
final class RetroTerminalView: LocalProcessTerminalView {
    var onInvalidate: (() -> Void)?

    /// Shift-Return and Control-Return insert a new line in programs that
    /// support it (such as Claude Code) instead of submitting.
    ///
    /// Terminals normally send the same byte for Return with or without
    /// these modifiers. When the program has turned on the extended keyboard
    /// protocol, SwiftTerm already reports them distinctly, so this leaves
    /// them alone. Otherwise:
    /// - Shift-Return sends ESC followed by Return, the same as Option-Return
    ///   with Option as Meta (zsh inserts a line break for it);
    /// - Control-Return sends a line feed, the same as Control-J (shells
    ///   treat it like Return).
    /// Returns true if it handled the key.
    func handleModifiedReturn(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])
        guard event.keyCode == 36 || event.keyCode == 76,   // Return, keypad Enter
              flags == .shift || flags == .control,
              !hasMarkedText(),
              terminal.keyboardEnhancementFlags.isEmpty else { return false }
        send(data: flags == .shift ? ArraySlice([0x1b, 0x0d]) : ArraySlice([0x0a]))
        return true
    }

    /// SwiftTerm holds its delegate weakly, so keep it alive here.
    private var securityDelegate: TerminalSecurityDelegate?

    /// Routes SwiftTerm's callbacks through this app's security policy
    /// (see TerminalSecurity.swift).
    func installSecurityPolicy() {
        let delegate = TerminalSecurityDelegate(view: self)
        securityDelegate = delegate
        terminalDelegate = delegate
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
        onInvalidate?()
    }

    override var needsDisplay: Bool {
        didSet {
            if needsDisplay { onInvalidate?() }
        }
    }
}

/// The Metal view drawn over the terminal. It shows the CRT image and passes
/// mouse input through to the terminal underneath.
final class CRTOverlayView: MTKView {
    weak var host: CRTTerminalView?

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { host?.forwardMouse(event) }
    override func mouseDragged(with event: NSEvent) { host?.forwardMouse(event) }
    override func mouseUp(with event: NSEvent) { host?.forwardMouse(event) }
    override func rightMouseDown(with event: NSEvent) { host?.forwardMouse(event) }
    override func rightMouseDragged(with event: NSEvent) { host?.forwardMouse(event) }
    override func rightMouseUp(with event: NSEvent) { host?.forwardMouse(event) }
    override func otherMouseDown(with event: NSEvent) { host?.forwardMouse(event) }
    override func otherMouseDragged(with event: NSEvent) { host?.forwardMouse(event) }
    override func otherMouseUp(with event: NSEvent) { host?.forwardMouse(event) }
    override func scrollWheel(with event: NSEvent) { host?.terminal.scrollWheel(with: event) }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }
}

/// A terminal session drawn as a CRT screen.
///
/// SwiftTerm draws the terminal as usual, in white on black. Whenever its
/// contents change, it is captured into a texture, and the Metal overlay
/// renders that texture through the CRT shaders (colour, glow, scanlines,
/// curvature, bezel). With effects turned off, the overlay is hidden and the
/// terminal is shown directly in the profile's colours.
final class CRTTerminalView: NSView, MTKViewDelegate {
    let terminal: RetroTerminalView
    private let overlay: CRTOverlayView
    private var renderer: CRTRenderer?

    private var profile: Profile
    private var fontEntry: BundledFont?
    private var effectsEnabled: Bool
    private var zoom: Double

    /// The window's tab colour, used to tint the bezel.
    var accentColor: NSColor? {
        didSet { contentDirty = true }
    }

    private var snapshot: NSBitmapImageRep?
    private var contentDirty = true
    private var capturing = false
    private var lastCapture: CFTimeInterval = 0
    private let startTime = CACurrentMediaTime()
    private var occlusionObserver: NSObjectProtocol?
    private var framesDrawn = 0
    private var debugSnapshotWritten = false

    /// Text size, in points, at the Qt app's default font scaling (1.0).
    private static let baseFontSize: CGFloat = 16

    init(frame: NSRect, profile: Profile, effectsEnabled: Bool, zoom: Double) {
        self.profile = profile
        self.effectsEnabled = effectsEnabled
        self.zoom = zoom
        terminal = RetroTerminalView(frame: frame)
        overlay = CRTOverlayView(frame: frame, device: MTLCreateSystemDefaultDevice())
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        terminal.optionAsMetaKey = true
        terminal.installSecurityPolicy()
        addSubview(terminal)

        overlay.host = self
        overlay.delegate = self
        overlay.colorPixelFormat = .bgra8Unorm
        overlay.framebufferOnly = true
        overlay.preferredFramesPerSecond = 60
        overlay.enableSetNeedsDisplay = false
        addSubview(overlay)

        if let device = overlay.device {
            do {
                renderer = try CRTRenderer(device: device, pixelFormat: overlay.colorPixelFormat)
            } catch {
                NSLog("cool-retro-term: CRT effects unavailable: %@", String(describing: error))
            }
        }

        terminal.onInvalidate = { [weak self] in
            guard let self, !self.capturing else { return }
            self.contentDirty = true
        }

        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }

    // MARK: Appearance

    func update(profile: Profile, effectsEnabled: Bool, zoom: Double) {
        self.profile = profile
        self.effectsEnabled = effectsEnabled
        self.zoom = zoom
        applyAppearance()
    }

    private var showsEffects: Bool { effectsEnabled && renderer != nil }

    private func applyAppearance() {
        fontEntry = profile.fontSource == 0 ? FontLibrary.shared.entry(for: profile.fontName) : nil
        terminal.font = FontLibrary.shared.font(for: profile, pointSize: fontSize)

        if showsEffects {
            // The shaders map brightness to the profile's colours.
            terminal.nativeForegroundColor = .white
            terminal.nativeBackgroundColor = .black
            terminal.caretColor = .white
        } else {
            terminal.nativeForegroundColor = NSColor(rgb: profile.effectiveFontColor)
            terminal.nativeBackgroundColor = NSColor(rgb: profile.effectiveBackgroundColor)
            terminal.caretColor = NSColor(rgb: profile.effectiveFontColor)
        }
        layer?.backgroundColor = showsEffects
            ? NSColor.black.cgColor
            : NSColor(rgb: profile.effectiveBackgroundColor).cgColor

        overlay.isHidden = !showsEffects
        updatePaused()
        layoutSubviewsNow()
        contentDirty = true
    }

    private var fontSize: CGFloat { Self.baseFontSize * CGFloat(zoom) }

    /// Pixels per point used when capturing the terminal. Bitmap-style fonts
    /// are captured at their native pixel size and scaled up by the shaders,
    /// which gives them their chunky look; other fonts use the full display
    /// resolution.
    private var snapshotScale: CGFloat {
        let backing = window?.backingScaleFactor ?? 2
        guard let fontEntry, fontEntry.lowResolution else { return backing }
        return min(max(CGFloat(fontEntry.pixelSize) / fontSize, 0.25), backing)
    }

    // MARK: Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutSubviewsNow()
    }

    private func layoutSubviewsNow() {
        overlay.frame = bounds
        let margin = showsEffects ? profile.marginPoints : 4
        terminal.frame = bounds.insetBy(dx: min(margin, bounds.width / 4), dy: min(margin, bounds.height / 4))
        contentDirty = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in self?.updatePaused() }
        }
        updatePaused()
        contentDirty = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        contentDirty = true
    }

    /// Stop rendering when the effects are off or the window can't be seen,
    /// so a hidden terminal costs no GPU time or battery.
    private func updatePaused() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        overlay.isPaused = !showsEffects || !visible
    }

    // MARK: Rendering

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        contentDirty = true
    }

    func draw(in view: MTKView) {
        guard let renderer, let drawable = view.currentDrawable else { return }
        let now = CACurrentMediaTime()
        // Recapture on change, and periodically for the blinking cursor.
        if contentDirty || now - lastCapture > 0.5 {
            captureTerminal(into: renderer)
            lastCapture = now
            contentDirty = false
        }
        let uniforms = makeUniforms(time: Float(now - startTime), drawableSize: view.drawableSize)
        renderer.render(to: drawable, uniforms: uniforms)

        framesDrawn += 1
        if framesDrawn >= 240, !debugSnapshotWritten {
            debugSnapshotWritten = true
            writeDebugSnapshot(renderer: renderer, uniforms: uniforms, size: view.drawableSize)
        }
    }

    /// For checking the effects without looking at a screen (used by CI):
    /// with CRT_SNAPSHOT_PATH set, saves a PNG of the rendered screen a few
    /// seconds after launch, and quits afterwards if CRT_SNAPSHOT_QUIT=1.
    private func writeDebugSnapshot(renderer: CRTRenderer, uniforms: CRTUniforms, size: CGSize) {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["CRT_SNAPSHOT_PATH"] else { return }
        if let image = renderer.renderImage(width: Int(size.width), height: Int(size.height),
                                            pixelFormat: overlay.colorPixelFormat, uniforms: uniforms),
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            do {
                try png.write(to: URL(fileURLWithPath: path))
                NSLog("cool-retro-term: wrote snapshot to %@", path)
            } catch {
                NSLog("cool-retro-term: could not write snapshot: %@", String(describing: error))
            }
        } else {
            NSLog("cool-retro-term: could not render snapshot")
        }
        if environment["CRT_SNAPSHOT_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private func captureTerminal(into renderer: CRTRenderer) {
        let size = terminal.bounds.size
        guard size.width >= 1, size.height >= 1 else { return }
        let scale = snapshotScale
        let width = max(Int((size.width * scale).rounded()), 1)
        let height = max(Int((size.height * scale).rounded()), 1)

        if snapshot?.pixelsWide != width || snapshot?.pixelsHigh != height {
            snapshot = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)
        }
        guard let snapshot, let data = snapshot.bitmapData else { return }
        snapshot.size = size

        // Leave SwiftTerm's scroll bar out of the CRT image; it's still
        // there for the mouse, just not drawn on the "glass".
        let scrollers = terminal.subviews.filter { $0 is NSScroller && !$0.isHidden }
        capturing = true
        scrollers.forEach { $0.isHidden = true }
        terminal.cacheDisplay(in: terminal.bounds, to: snapshot)
        scrollers.forEach { $0.isHidden = false }
        capturing = false

        renderer.updateContent(bytes: data, width: width, height: height, bytesPerRow: snapshot.bytesPerRow)
    }

    private func makeUniforms(time: Float, drawableSize: CGSize) -> CRTUniforms {
        let p = profile
        var u = CRTUniforms()
        let viewSize = SIMD2<Float>(Float(max(bounds.width, 1)), Float(max(bounds.height, 1)))

        u.fontColor = opaque(p.effectiveFontColor)
        u.backgroundColor = opaque(p.effectiveBackgroundColor)
        u.frameColor = opaque(p.effectiveFrameColor)
        if let accent = accentColor?.usingColorSpace(.sRGB) {
            let tint = RGB(Float(accent.redComponent), Float(accent.greenComponent), Float(accent.blueComponent))
            let frame = p.effectiveFrameColor
            u.frameColor = opaque(frame + (tint * 0.85 - frame) * 0.7)
        }

        // Where the terminal sits on the screen, in UV space (origin top left).
        let content = terminal.frame
        u.contentRect = SIMD4(Float(content.minX) / viewSize.x,
                              Float(bounds.height - content.maxY) / viewSize.y,
                              Float(content.width) / viewSize.x,
                              Float(content.height) / viewSize.y)
        u.viewportSize = viewSize

        let snapshotPixels = SIMD2<Float>(Float(snapshot?.pixelsWide ?? 1), Float(snapshot?.pixelsHigh ?? 1))
        u.virtualResolution = snapshotPixels / SIMD2(u.contentRect.z, u.contentRect.w)
        let drawablePixels = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        let density = (drawablePixels / u.virtualResolution).min()
        // Scanlines alias when the terminal is close to display resolution,
        // so fade them in from 2x to 4x (as the Qt app does).
        u.rasterizationIntensity = smoothStep(2, 4, density)
        u.rasterization = Float(p.rasterization)
        u.pixelated = (fontEntry?.lowResolution ?? false) ? 1 : 0

        u.time = time
        u.staticNoise = Float(p.staticNoise)
        u.glowingLine = Float(p.glowingLine * 0.2)
        u.chromaColor = Float(p.chromaColor)
        u.jitter = Float(p.jitter)
        u.jitterDisplacement = SIMD2(0.007, 0.002) * Float(p.jitter)
        u.horizontalSync = Float(p.horizontalSync)
        u.horizontalSyncStrength = lint(0.05, 0.35, Float(p.horizontalSync))
        u.flickering = Float(p.flickering)
        u.noiseScale = viewSize * 0.75 / 512

        u.burnIn = Float(p.burnIn)
        u.burnInTime = 1 / lint(0.16, 1.6, Float(p.burnIn))

        u.screenCurvature = Float(p.screenCurvature * 0.6)
        u.frameSize = Float(p.frameSize * 0.05)
        u.rgbShift = Float(p.rgbShift) * 4 / viewSize.x
        u.bloom = Float(p.bloom * 2.5)
        u.brightness = lint(0.5, 1.5, Float(p.brightness))
        u.frameShininess = Float(p.frameShininess * 0.5)
        u.screenRadius = Float(p.screenRadiusPoints)
        u.ambientLight = Float(p.ambientLight)
        return u
    }

    // MARK: Mouse

    /// Sends a mouse event to the terminal, moved to where the pointer
    /// appears on the curved screen.
    func forwardMouse(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            window?.makeFirstResponder(terminal)
        }
        let mapped = remap(event)
        switch event.type {
        case .leftMouseDown: terminal.mouseDown(with: mapped)
        case .leftMouseDragged: terminal.mouseDragged(with: mapped)
        case .leftMouseUp: terminal.mouseUp(with: mapped)
        case .rightMouseDown: terminal.rightMouseDown(with: mapped)
        case .rightMouseDragged: terminal.rightMouseDragged(with: mapped)
        case .rightMouseUp: terminal.rightMouseUp(with: mapped)
        case .otherMouseDown: terminal.otherMouseDown(with: mapped)
        case .otherMouseDragged: terminal.otherMouseDragged(with: mapped)
        case .otherMouseUp: terminal.otherMouseUp(with: mapped)
        default: break
        }
    }

    private func remap(_ event: NSEvent) -> NSEvent {
        let size = overlay.bounds.size
        guard size.width > 0, size.height > 0 else { return event }
        let point = overlay.convert(event.locationInWindow, from: nil)
        let uv = SIMD2<Float>(Float(point.x / size.width), Float(1 - point.y / size.height))
        let distorted = CRTRenderer.distort(uv, curvature: Float(profile.screenCurvature * 0.6),
                                            frameSize: Float(profile.frameSize * 0.05))
        let local = NSPoint(x: CGFloat(distorted.x) * size.width, y: (1 - CGFloat(distorted.y)) * size.height)
        let location = overlay.convert(local, to: nil)
        return NSEvent.mouseEvent(
            with: event.type, location: location, modifierFlags: event.modifierFlags,
            timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
            eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: event.pressure
        ) ?? event
    }
}

private func smoothStep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

private func opaque(_ c: RGB) -> SIMD4<Float> { SIMD4(c.x, c.y, c.z, 1) }
