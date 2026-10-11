import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private let transcriber = Transcriber()
    private let indicator = Indicator()
    private var tap: HotkeyTap!
    private var recording = false { didSet { tap.isActive = recording } }
    private var pressedAt = Date()
    private var focus: FocusTarget?

    private var hotkey: Hotkey {
        get { Hotkey(rawValue: UserDefaults.standard.string(forKey: "hotkey") ?? "") ?? .rightOption }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "hotkey"); tap.hotkey = newValue; buildMenu() }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon("mic")

        tap = HotkeyTap(hotkey: hotkey)
        tap.onPress = { [unowned self] in startRecording() }
        tap.onRelease = { [unowned self] in stopRecording() }
        tap.onChord = { [unowned self] in cancelRecording() }
        tap.onEscape = { [unowned self] in cancelRecording() }
        buildMenu()

        // Accessibility covers both the active event tap and posting ⌘V.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSLog("keytalk: waiting for Accessibility permission")
        }
        startTapWhenTrusted()

        Transcriber.requestPermissions { ok in
            if !ok { NSLog("keytalk: microphone or speech recognition permission denied") }
        }
    }

    /// The tap fails until Accessibility is granted, so retry until it works.
    /// Until then, say so on screen: otherwise the hotkey silently does nothing.
    /// (An ad-hoc signed rebuild loses the grant even though System Settings
    /// still shows Keytalk switched on.)
    private func startTapWhenTrusted() {
        if AXIsProcessTrusted(), tap.start() {
            indicator.hide()
            return
        }
        indicator.show(.needsAccessibility)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startTapWhenTrusted() }
    }

    private func startRecording() {
        guard !recording else { return }
        do {
            try transcriber.start()
            recording = true
            pressedAt = Date()
            focus = TextInserter.captureFocus()
            setIcon("mic.fill")
            indicator.show(.listening)
        } catch {
            NSLog("keytalk: could not start audio: \(error)")
        }
    }

    private func stopRecording() {
        guard recording else { return }
        recording = false
        setIcon("ellipsis")
        indicator.show(.transcribing)
        // Ignore taps shorter than 250 ms (an accidental modifier press).
        if Date().timeIntervalSince(pressedAt) < 0.25 { cancelRecording(); return }
        transcriber.stop { [weak self] text in
            guard let self else { return }
            setIcon("mic")
            indicator.hide()
            guard !text.isEmpty else { return }
            TextInserter.insert(text + " ", into: focus) { [weak self] outcome in
                self?.report(outcome)
            }
        }
    }

    private func report(_ outcome: PasteOutcome) {
        switch outcome {
        case .pasted:
            break
        case .failed:
            NSLog("keytalk: no app took the paste, text left on the clipboard")
            flashIcon("doc.on.clipboard")
            indicator.flash(.failed)
        case .blocked(let owner):
            NSLog("keytalk: secure input is on (held by \(owner ?? "unknown app")), not pasting")
            flashIcon("lock")
            indicator.flash(.blocked(owner))
        }
    }

    /// Shows a status icon for 2 seconds, then goes back to the idle mic.
    private func flashIcon(_ symbol: String) {
        NSSound.beep()
        setIcon(symbol)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !recording else { return }
            setIcon("mic")
        }
    }

    private func cancelRecording() {
        recording = false
        transcriber.cancel()
        setIcon("mic")
        indicator.hide()
    }

    private func setIcon(_ symbol: String) {
        status.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Keytalk")
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Hold \(hotkey.label) to dictate. Esc cancels.", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        for key in Hotkey.allCases {
            let item = NSMenuItem(title: key.label, action: #selector(pickHotkey(_:)), keyEquivalent: "")
            item.representedObject = key.rawValue
            item.state = key == hotkey ? .on : .off
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Keytalk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
    }

    @objc private func pickHotkey(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let k = Hotkey(rawValue: raw) { hotkey = k }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
