import AppKit
import SwiftTerm

/// One terminal window (or tab) running the user's login shell.
final class TerminalWindowController: NSWindowController, NSWindowDelegate, LocalProcessTerminalViewDelegate {
    let crtView: CRTTerminalView
    var onClose: ((TerminalWindowController) -> Void)?
    private var appearanceObserver: NSObjectProtocol?

    init() {
        let store = ProfileStore.shared
        let frame = NSRect(x: 0, y: 0, width: 960, height: 640)
        crtView = CRTTerminalView(frame: frame, profile: store.current,
                                  effectsEnabled: store.effectsEnabled, zoom: store.zoom)

        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Cool Retro Term"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.titlebarAppearsTransparent = true
        window.tabbingIdentifier = "CoolRetroTerm"
        window.tabbingMode = .automatic
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.minSize = NSSize(width: 320, height: 200)
        window.contentView = crtView
        window.initialFirstResponder = crtView.terminal
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        crtView.terminal.processDelegate = self
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .terminalAppearanceDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            let store = ProfileStore.shared
            self?.crtView.update(profile: store.current, effectsEnabled: store.effectsEnabled, zoom: store.zoom)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    /// Starts the user's login shell in their home directory.
    func startShell() {
        let shell = Self.loginShell
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "cool-retro-term"
        // Apps launched from Finder or the Dock get no LANG, which makes
        // shells and tools fall back to ASCII and garble Unicode output.
        if environment["LANG"] == nil && environment["LC_ALL"] == nil && environment["LC_CTYPE"] == nil {
            environment["LANG"] = Self.utf8Locale
        }
        crtView.terminal.startProcess(
            executable: shell,
            args: [],
            environment: environment.map { "\($0.key)=\($0.value)" },
            execName: "-" + (shell as NSString).lastPathComponent,
            currentDirectory: NSHomeDirectory())

        // Debug aid for CI screenshots: type a command once the shell is up.
        if let command = ProcessInfo.processInfo.environment["CRT_SNAPSHOT_COMMAND"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.crtView.terminal.send(data: ArraySlice(Array((command + "\n").utf8)))
            }
        }
    }

    private static var loginShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    private static var utf8Locale: String {
        let locale = Locale.current
        if let language = locale.language.languageCode?.identifier,
           let region = locale.region?.identifier {
            return "\(language)_\(region).UTF-8"
        }
        return "en_US.UTF-8"
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        crtView.terminal.terminate()
        onClose?(self)
    }

    // MARK: LocalProcessTerminalViewDelegate
    //
    // SwiftTerm's delegate protocol isn't actor-isolated, so these hop to the
    // main actor before touching the window.

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in
            self?.window?.title = title.isEmpty ? "Cool Retro Term" : title
        }
    }

    /// Shells that report their directory (OSC 7, which macOS's zsh does by
    /// default) get a proxy icon in the title bar.
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        let url: URL? = directory.map { value in
            if let parsed = URL(string: value), parsed.isFileURL {
                return URL(fileURLWithPath: parsed.path)
            }
            return URL(fileURLWithPath: value)
        }
        Task { @MainActor [weak self] in
            self?.window?.representedURL = url
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            self?.window?.close()
        }
    }
}
