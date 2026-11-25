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
        guard ProfileStore.shared.newLineKeys,
              event.keyCode == 36 || event.keyCode == 76,   // Return, keypad Enter
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

    /// When the CRT image covers the terminal, SwiftTerm drawing it on screen
    /// as well is wasted work: it is drawn only when captured instead.
    var suppressesOwnDrawing = false {
        didSet {
            if !suppressesOwnDrawing && oldValue { super.needsDisplay = true }
        }
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        if !suppressesOwnDrawing { super.setNeedsDisplay(invalidRect) }
        onInvalidate?()
    }

    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            if !suppressesOwnDrawing || !newValue { super.needsDisplay = newValue }
            if newValue { onInvalidate?() }
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
    override func rightMouseDown(with event: NSEvent) {
        // Programs using the mouse get the click; otherwise show the menu.
        if let host, !host.programUsesMouse, let menu = host.terminal.menu {
            NSMenu.popUpContextMenu(menu, with: event, for: host.terminal)
        } else {
            host?.forwardMouse(event)
        }
    }
    override func rightMouseDragged(with event: NSEvent) { host?.forwardMouse(event) }
    override func rightMouseUp(with event: NSEvent) { host?.forwardMouse(event) }
    override func otherMouseDown(with event: NSEvent) { host?.forwardMouse(event) }
    override func otherMouseDragged(with event: NSEvent) { host?.forwardMouse(event) }
    override func otherMouseUp(with event: NSEvent) { host?.forwardMouse(event) }
    override func scrollWheel(with event: NSEvent) { host?.terminal.scrollWheel(with: event) }

    /// A text cursor over the text, an arrow over the bezel and margins, and
    /// an arrow everywhere when the program has taken over the mouse.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
        if let host, !host.programUsesMouse {
            addCursorRect(host.convert(host.terminal.frame, to: self), cursor: .iBeam)
        }
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
    private var capturedPixelSize: (width: Int, height: Int) = (1, 1)

    // Efficiency: see draw(in:) and noteActivity().
    private var lastActivity = CACurrentMediaTime()
    private var pausedForIdle = false
    private var drawScheduled = false
    private var powerObserver: NSObjectProtocol?
    private var keyWindowObserver: NSObjectProtocol?
    private let startTime = CACurrentMediaTime()
    private var occlusionObserver: NSObjectProtocol?
    private var framesDrawn = 0
    private var lastProgramUsesMouse = false
    private var lastRender: CFTimeInterval = 0
    private var cursorBlinkVisible = true
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

        terminal.optionAsMetaKey = ProfileStore.shared.optionAsMeta
        terminal.installSecurityPolicy()
        terminal.menu = (NSApp.delegate as? AppDelegate)?.makeContextMenu()
        addSubview(terminal)

        overlay.host = self
        overlay.delegate = self
        overlay.colorPixelFormat = .bgra8Unorm
        overlay.framebufferOnly = true
        overlay.preferredFramesPerSecond = 60
        overlay.autoResizeDrawable = false
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
            self.noteActivity()
        }

        powerObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteActivity() }
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
        if let powerObserver {
            NotificationCenter.default.removeObserver(powerObserver)
        }
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
        }
    }

    // MARK: Appearance

    func update(profile: Profile, effectsEnabled: Bool, zoom: Double) {
        terminal.optionAsMetaKey = ProfileStore.shared.optionAsMeta
        self.profile = profile
        self.effectsEnabled = effectsEnabled
        self.zoom = zoom
        applyAppearance()
    }

    private var showsEffects: Bool { effectsEnabled && renderer != nil }

    /// Whether the program in the terminal is receiving mouse events
    /// (mouse reporting), in which case the pointer is an arrow.
    var programUsesMouse: Bool {
        terminal.terminal.mouseMode != .off
    }

    private func applyAppearance() {
        fontEntry = profile.fontSource == 0 ? FontLibrary.shared.entry(for: profile.fontName) : nil
        var font = FontLibrary.shared.font(for: profile, pointSize: fontSize)
        // Font width stretches the glyphs (and so the cells) horizontally.
        if abs(profile.fontWidth - 1) > 0.001 {
            let matrix = AffineTransform(scaleByX: CGFloat(min(max(profile.fontWidth, 0.5), 1.5)), byY: 1)
            font = NSFont(descriptor: font.fontDescriptor.withMatrix(matrix), size: fontSize) ?? font
        }
        if terminal.font != font { terminal.font = font }
        let spacing = 1 + CGFloat(min(max(profile.lineSpacing, 0), 1))
        if abs(terminal.lineSpacing - spacing) > 0.001 { terminal.lineSpacing = spacing }

        // With effects on, the cursor is blinked when capturing (the caret's
        // own animation isn't captured); with them off, SwiftTerm blinks it.
        let blink = profile.blinkingCursor && !showsEffects
        let style: CursorStyle
        switch ProfileStore.shared.cursorShape {
        case 1: style = blink ? .blinkUnderline : .steadyUnderline
        case 2: style = blink ? .blinkBar : .steadyBar
        default: style = blink ? .blinkBlock : .steadyBlock
        }
        terminal.terminal.setCursorStyle(style)
        // Keep the cursor solid when the window isn't focused (SwiftTerm
        // would draw a hollow block), as the Qt app does.
        terminal.caretViewTracksFocus = false

        let store = ProfileStore.shared
        renderer?.bloomQuality = store.bloomQuality
        renderer?.burnInQuality = store.burnInQuality

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
        terminal.suppressesOwnDrawing = showsEffects
        updatePaused()
        layoutSubviewsNow()
        contentDirty = true
    }

    // MARK: Size overlay

    private var sizeLabel: NSTextField?
    private var sizeLabelHide: DispatchWorkItem?
    private var knownSize: (cols: Int, rows: Int)?

    /// Shows "cols × rows" in the middle of the screen briefly after the
    /// terminal is resized, as the Qt app does.
    func terminalSizeChanged(cols: Int, rows: Int) {
        defer { knownSize = (cols, rows) }
        guard let known = knownSize, known.cols != cols || known.rows != rows,
              ProfileStore.shared.showTerminalSize else { return }

        let label = sizeLabel ?? {
            let field = NSTextField(labelWithString: "")
            field.font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
            field.textColor = .white
            field.alignment = .center
            field.wantsLayer = true
            field.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
            field.layer?.cornerRadius = 8
            addSubview(field)
            sizeLabel = field
            return field
        }()
        label.stringValue = "  \(cols) × \(rows)  "
        label.sizeToFit()
        label.frame = NSRect(x: (bounds.width - label.frame.width) / 2, y: (bounds.height - label.frame.height - 12) / 2,
                             width: label.frame.width, height: label.frame.height + 12)
        label.alphaValue = 1
        label.isHidden = false

        sizeLabelHide?.cancel()
        let hide = DispatchWorkItem { [weak label] in
            NSAnimationContext.runAnimationGroup { $0.duration = 0.3; label?.animator().alphaValue = 0 }
        }
        sizeLabelHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: hide)
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

    /// The effects render at the display's resolution times the texture
    /// quality setting (the Qt app's window scaling).
    private func updateDrawableSize() {
        let scale = (window?.backingScaleFactor ?? 2) * CGFloat(ProfileStore.shared.windowScaling)
        let size = CGSize(width: max(bounds.width * scale, 1).rounded(), height: max(bounds.height * scale, 1).rounded())
        if overlay.drawableSize != size { overlay.drawableSize = size }
    }

    private func layoutSubviewsNow() {
        overlay.frame = bounds
        updateDrawableSize()
        let margin = showsEffects ? profile.marginPoints : 4
        terminal.frame = bounds.insetBy(dx: min(margin, bounds.width / 4), dy: min(margin, bounds.height / 4))
        window?.invalidateCursorRects(for: overlay)
        contentDirty = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
            self.keyWindowObserver = nil
        }
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in self?.updatePaused() }
            // Coming back to a window resumes paused effects.
            keyWindowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.noteActivity() }
            }
        }
        updatePaused()
        contentDirty = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
        contentDirty = true
    }

    /// Stop rendering when the effects are off or the window can't be seen,
    /// so a hidden terminal costs no GPU time or battery.
    private func updatePaused() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        overlay.isPaused = !showsEffects || !visible || pausedForIdle
        overlay.preferredFramesPerSecond = effectsFramesPerSecond
    }

    // MARK: Efficiency
    //
    // The CRT image is redrawn:
    // - straight away when the terminal's contents change (typing, output);
    // - otherwise at the effects frame rate (60 fps / the Qt app's frame
    //   skip, or 12 fps in Low Power Mode), to animate noise, flicker and
    //   the like;
    // - not at all while the window is minimised or hidden;
    // - optionally (off by default), not once nothing has happened for a few
    //   seconds, when "pause effects when idle" is on (except twice a second
    //   for a blinking cursor); any activity resumes it.

    private var lowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    private var effectsFramesPerSecond: Int {
        lowPowerMode ? 12 : max(60 / max(ProfileStore.shared.effectsFrameSkip, 1), 1)
    }

    private var idleDelay: CFTimeInterval { lowPowerMode ? 2 : 5 }

    /// Output, typing or returning to the window: resume and redraw promptly.
    private func noteActivity() {
        lastActivity = CACurrentMediaTime()
        if pausedForIdle || overlay.preferredFramesPerSecond != effectsFramesPerSecond {
            pausedForIdle = false
            updatePaused()
        }
        guard !drawScheduled, !overlay.isPaused else { return }
        drawScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.drawScheduled = false
            if !self.overlay.isPaused { self.overlay.draw() }
        }
    }

    // MARK: Rendering

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        contentDirty = true
    }

    func draw(in view: MTKView) {
        guard let renderer, let drawable = view.currentDrawable else { return }
        if programUsesMouse != lastProgramUsesMouse {
            lastProgramUsesMouse = programUsesMouse
            window?.invalidateCursorRects(for: overlay)
        }
        let now = CACurrentMediaTime()

        // Blink the cursor in the captured image (about twice a second).
        if profile.blinkingCursor {
            let phase = Int(now / 0.53) % 2 == 0
            if phase != cursorBlinkVisible {
                cursorBlinkVisible = phase
                contentDirty = true
            }
        } else if !cursorBlinkVisible {
            cursorBlinkVisible = true
            contentDirty = true
        }

        lastRender = now

        // Recapture only when the contents changed (or the cursor blinked).
        if contentDirty {
            captureTerminal(into: renderer)
            lastCapture = now
            contentDirty = false
        }
        let uniforms = makeUniforms(time: Float(now - startTime), drawableSize: view.drawableSize)
        renderer.render(to: drawable, uniforms: uniforms)

        framesDrawn += 1
        if now - startTime > 4, !debugSnapshotWritten {
            debugSnapshotWritten = true
            writeDebugSnapshot(renderer: renderer, uniforms: uniforms, size: view.drawableSize)
        }

        // Idle: stop animating, or just blink the cursor.
        if ProfileStore.shared.pauseEffectsWhenIdle && now - lastActivity > idleDelay {
            if profile.blinkingCursor {
                if view.preferredFramesPerSecond != 4 { view.preferredFramesPerSecond = 4 }
            } else if !pausedForIdle {
                pausedForIdle = true
                DispatchQueue.main.async { [weak self] in self?.updatePaused() }
            }
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

        // Leave SwiftTerm's scroll bar out of the CRT image; it's still
        // there for the mouse, just not drawn on the "glass".
        var hidden = terminal.subviews.filter { $0 is NSScroller && !$0.isHidden }
        // In the "off" half of a cursor blink, leave the caret out too.
        if !cursorBlinkVisible {
            hidden += terminal.subviews.filter { String(describing: type(of: $0)) == "CaretView" && !$0.isHidden }
        }

        // Apple silicon: draw straight into memory the GPU reads (no copy).
        if let context = renderer.beginContentCapture(width: width, height: height) {
            capturedPixelSize = (width, height)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            capturing = true
            hidden.forEach { $0.isHidden = true }
            terminal.displayIgnoringOpacity(terminal.bounds, in: NSGraphicsContext(cgContext: context, flipped: false))
            hidden.forEach { $0.isHidden = false }
            capturing = false
            renderer.endContentCapture()
            return
        }

        if snapshot?.pixelsWide != width || snapshot?.pixelsHigh != height {
            snapshot = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)
        }
        guard let snapshot, let data = snapshot.bitmapData else { return }
        snapshot.size = size
        capturedPixelSize = (width, height)

        capturing = true
        hidden.forEach { $0.isHidden = true }
        terminal.cacheDisplay(in: terminal.bounds, to: snapshot)
        hidden.forEach { $0.isHidden = false }
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

        let snapshotPixels = SIMD2<Float>(Float(capturedPixelSize.width), Float(capturedPixelSize.height))
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
