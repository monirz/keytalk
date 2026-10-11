import Cocoa

/// A small floating pill at the bottom of the screen that shows what Keytalk
/// is doing. It is the main feedback: the menu bar icon can end up hidden
/// behind the notch.
///
/// The panel is non-activating and ignores the mouse, so it never takes focus
/// away from the app the text is going into.
final class Indicator {
    enum State {
        case listening, transcribing
        case failed            // text left on the clipboard
        case blocked(String?)  // secure input, held by this app
        case needsAccessibility

        var symbol: String {
            switch self {
            case .listening: return "mic.fill"
            case .transcribing: return "ellipsis"
            case .failed: return "doc.on.clipboard"
            case .blocked: return "lock.fill"
            case .needsAccessibility: return "exclamationmark.triangle.fill"
            }
        }

        var text: String {
            switch self {
            case .listening: return "Listening…"
            case .transcribing: return "Transcribing…"
            case .failed: return "No text field. Press ⌘V to paste."
            case .blocked(let app): return "Secure input is on\(app.map { " in \($0)" } ?? ""). Not pasted."
            case .needsAccessibility: return "Keytalk needs Accessibility. Turn it on in System Settings → Privacy & Security."
            }
        }

        var tint: NSColor {
            switch self {
            case .listening: return .systemRed
            case .transcribing: return .secondaryLabelColor
            case .failed, .blocked, .needsAccessibility: return .systemOrange
            }
        }
    }

    private let panel: NSPanel
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        icon.symbolConfiguration = .init(pointSize: 14, weight: .semibold)

        let stack = NSStackView(views: [icon, label])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
    }

    /// Shows a state until the next call to `show` or `hide`.
    func show(_ state: State) {
        hideWork?.cancel()
        icon.image = NSImage(systemSymbolName: state.symbol, accessibilityDescription: nil)
        icon.contentTintColor = state.tint
        label.stringValue = state.text

        let size = panel.contentView!.fittingSize
        // The screen with the menu bar focus, where the user is working.
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        panel.setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.minY + 24,
                              width: size.width, height: 36), display: true)
        panel.orderFrontRegardless()
    }

    /// Shows a state, then hides it after a few seconds.
    func flash(_ state: State, for seconds: Double = 2.5) {
        show(state)
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }
}
