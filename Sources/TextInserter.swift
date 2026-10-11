import Cocoa
import Carbon.HIToolbox

/// The app and text field that had focus when dictation started.
struct FocusTarget {
    let app: NSRunningApplication
    let element: AXUIElement?
}

enum PasteOutcome {
    case pasted
    /// No app asked for the text. It stays on the clipboard so the user can ⌘V it.
    case failed
    /// Secure input is on, so ⌘V would be ignored. Holds the app that turned it on.
    case blocked(String?)
}

/// Inserts text into whichever app has focus.
///
/// 1. Remember the focused app and element when dictation starts, and bring
///    them back before pasting if focus moved meanwhile.
/// 2. Put a *promise* on the clipboard (NSPasteboardItemDataProvider) instead
///    of the text itself, then post a synthetic ⌘V with CGEventPost.
/// 3. The target app asking for the promised data proves the paste landed.
///    If nobody asks within a second, the paste failed: leave the text on the
///    clipboard instead of losing it.
/// 4. After a paste, restore the old clipboard about 500 ms later.
///
/// Pasting works in almost every app (native, Electron, browsers, terminals),
/// where writing through the Accessibility API often fails without an error.
enum TextInserter {
    /// Keeps the promise alive while it is on the clipboard.
    private static var pending: Promise?

    static func captureFocus() -> FocusTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25) // a hung app must not stall us
        var value: CFTypeRef?
        let ok = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success
        return FocusTarget(app: app, element: ok ? (value as! AXUIElement) : nil)
    }

    static func insert(_ text: String, into target: FocusTarget?, done: @escaping (PasteOutcome) -> Void) {
        guard !text.isEmpty else { return }
        if IsSecureEventInputEnabled() {
            done(.blocked(secureInputOwner()))
            return
        }
        refocus(target) { paste(text, done: done) }
    }

    /// Brings back the app and field that had focus when dictation started.
    private static func refocus(_ target: FocusTarget?, then: @escaping () -> Void) {
        guard let target, !target.app.isTerminated,
              NSWorkspace.shared.frontmostApplication != target.app else { return then() }
        target.app.activate(options: [.activateIgnoringOtherApps])
        waitUntilFrontmost(target.app, tries: 10) {
            if let element = target.element {
                AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            }
            then()
        }
    }

    /// Waits for app activation without blocking the main thread: up to
    /// 10 × 50 ms, and no longer than needed.
    private static func waitUntilFrontmost(_ app: NSRunningApplication, tries: Int, then: @escaping () -> Void) {
        if NSWorkspace.shared.frontmostApplication == app || tries == 0 { return then() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            waitUntilFrontmost(app, tries: tries - 1, then: then)
        }
    }

    private static func paste(_ text: String, done: @escaping (PasteOutcome) -> Void) {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)

        let promise = Promise(text: text)
        let item = NSPasteboardItem()
        // nspasteboard.org markers so clipboard managers skip this entry
        // (and do not request the promise, which would look like a paste).
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        item.setDataProvider(promise, forTypes: [.string])
        pb.clearContents()
        pb.writeObjects([item])
        let ourChange = pb.changeCount
        pending = promise

        promise.onRequest = {
            done(.pasted)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if pending === promise { pending = nil }
                // Leave the clipboard alone if the user copied something meanwhile.
                guard pb.changeCount == ourChange else { return }
                restore(pb, saved)
            }
        }

        postCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard !promise.requested else { return }
            promise.onRequest = nil
            if pending === promise { pending = nil }
            if pb.changeCount == ourChange {
                // Swap the promise for the real text, without the transient
                // markers, so it survives and the user can paste it by hand.
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
            done(.failed)
        }
    }

    private static func postCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let v = keyCode(for: "v") ?? CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        // Set the flags explicitly. A modifier the user is still holding
        // (the hotkey) would otherwise turn this into ⌘⌥V and so on.
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        usleep(5_000) // some apps drop a key down and up that arrive together
        up?.post(tap: .cghidEventTap)
    }

    /// The app that turned on secure input, usually for a password field.
    private static func secureInputOwner() -> String? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    /// Finds the key that types `char` in the current layout, so ⌘V
    /// still works on Dvorak, AZERTY and other layouts.
    private static func keyCode(for char: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<128 {
                var dead: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var len = 0
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &dead, chars.count, &len, &chars)
                if status == noErr, len == 1, String(utf16CodeUnits: chars, count: 1) == String(char) {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }

    private typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    private static func snapshot(_ pb: NSPasteboard) -> Snapshot {
        (pb.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let data = item.data(forType: t) { d[t] = data } }
            return d
        }
    }

    private static func restore(_ pb: NSPasteboard, _ snap: Snapshot) {
        pb.clearContents()
        guard !snap.isEmpty else { return }
        let items = snap.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (t, data) in dict { item.setData(data, forType: t) }
            return item
        }
        pb.writeObjects(items)
    }
}

/// Hands over the text only when an app actually reads the clipboard.
private final class Promise: NSObject, NSPasteboardItemDataProvider {
    let text: String
    private(set) var requested = false
    var onRequest: (() -> Void)?

    init(text: String) { self.text = text }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        item.setString(text, forType: type)
        guard !requested else { return }
        requested = true
        onRequest?()
    }
}
