import Cocoa

/// A hold-to-talk modifier key, watched through a CGEventTap.
///
/// A session-level event tap sees every keyboard event system-wide (this
/// needs the Accessibility permission). We watch `flagsChanged` for the
/// chosen modifier. The tap can also swallow events: we eat Esc while
/// recording so it cancels dictation instead of reaching the focused app.
///
/// The tap runs on its own thread. Every key the user types waits for this
/// callback, so it must not queue behind work on the main thread. A watchdog
/// turns the tap back on if macOS disabled it without telling us.
enum Hotkey: String, CaseIterable {
    case rightOption, rightCommand, rightControl, fn

    var keyCode: Int64 {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        case .fn: return 63
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        case .fn: return .maskSecondaryFn
        }
    }

    var label: String {
        switch self {
        case .rightOption: return "Right ⌥ Option"
        case .rightCommand: return "Right ⌘ Command"
        case .rightControl: return "Right ⌃ Control"
        case .fn: return "fn / 🌐"
        }
    }
}

final class HotkeyTap {
    var hotkey: Hotkey {
        get { lock.lock(); defer { lock.unlock() }; return key }
        set { lock.lock(); key = newValue; lock.unlock() }
    }
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    /// Another key was pressed while the hotkey was held, so it is a chord
    /// (like ⌥+arrow), not dictation.
    var onChord: () -> Void = {}
    var onEscape: () -> Void = {}
    /// Set from the main thread while recording, so Esc should be swallowed.
    var isActive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return active }
        set { lock.lock(); active = newValue; lock.unlock() }
    }

    private var tap: CFMachPort?
    private var held = false // touched only on the tap thread
    private var active = false
    private var key: Hotkey
    private let lock = NSLock()
    private var watchdog: Timer?

    init(hotkey: Hotkey) { key = hotkey }

    /// Callbacks run on the main thread.
    func start() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            let me = Unmanaged<HotkeyTap>.fromOpaque(userInfo!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap, // active tap, so we can drop events
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "keytalk.eventTap"
        thread.qualityOfService = .userInteractive
        thread.start()

        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            if !CGEvent.tapIsEnabled(tap: tap) {
                NSLog("keytalk: event tap was disabled, turning it back on")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return true
    }

    private func main(_ f: @escaping () -> Void) { DispatchQueue.main.async(execute: f) }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns off a tap whose callback is slow. Turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let hotkey = self.hotkey
            if code == hotkey.keyCode {
                let down = event.flags.contains(hotkey.flag)
                if down && !held { held = true; main(onPress) }
                else if !down && held { held = false; main(onRelease) }
            }

        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if code == 53, isActive { // Esc
                held = false
                main(onEscape)
                return nil // swallow
            }
            if held { held = false; main(onChord) }

        default: break
        }
        return Unmanaged.passUnretained(event)
    }
}
