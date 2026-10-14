import AppKit
import Combine

/// Owns the arrow in the menu bar and hides or shows the chosen apps' icons.
///
/// On macOS 27 hiding goes through `Concealer`, which works per app and on
/// every display at once. Left-click the arrow to toggle; right-click or
/// Control-click it for Settings and Quit.
@MainActor
final class SectionController: NSObject {
    enum State { case revealed, hidden }

    let toggleItem: NSStatusItem

    private(set) var state: State = .revealed
    var onStateChange: ((State) -> Void)?

    /// Called when the user left-clicks the arrow.
    var onToggleClick: (() -> Void)?

    private let settings: Settings
    private let concealer = Concealer()
    private let menu: NSMenu
    private var lastToggleClick = Date.distantPast
    private var hiddenAppsObserver: AnyCancellable?

    init(settings: Settings, menu: NSMenu) {
        self.settings = settings
        self.menu = menu
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Keeps the arrow where the user Command-drags it.
        toggleItem.autosaveName = "MBMToggle"
        super.init()

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Click to show or hide icons. Right-click for Settings."
        }
        // Deliberately no expandedInterfaceDelegate: on macOS 27, setting it
        // stops clicks from sending the button action, and the session it
        // opens swallows the next click, so the arrow only works once.

        DebugLog.write("concealment available: \(Concealer.isAvailable)")
        hiddenAppsObserver = settings.$hiddenBundleIDs
            .dropFirst()
            .sink { [weak self] _ in
                // @Published fires before the new value is stored.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.hiddenAppsChanged() }
                }
            }
        updateImage()
    }

    // MARK: Public

    func toggle() {
        if state == .hidden {
            reveal()
        } else {
            hide()
        }
    }

    func reveal() {
        guard state != .revealed else { return }
        state = .revealed
        concealer.release()
        updateImage()
        DebugLog.write("revealed")
        onStateChange?(state)
    }

    func hide() {
        guard state != .hidden else { return }
        guard Concealer.isAvailable else {
            DebugLog.write("not hiding: MenuBarClientCore is unavailable on this macOS build")
            return
        }
        state = .hidden
        apply()
        updateImage()
        onStateChange?(state)
    }

    // MARK: Private

    private func hiddenAppsChanged() {
        if state == .hidden { apply() }
    }

    private func apply() {
        if settings.hiddenBundleIDs.isEmpty {
            // A live assertion also removes Control Center's camera and
            // microphone indicator, so don't hold one for nothing.
            concealer.release()
        } else {
            concealer.conceal(settings.hiddenBundleIDs)
        }
    }

    @objc private func toggleClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
            return
        }
        // Ignore a double fire from one click.
        let now = Date()
        guard now.timeIntervalSince(lastToggleClick) > 0.3 else { return }
        lastToggleClick = now
        DebugLog.write("arrow clicked while \(state == .hidden ? "hidden" : "revealed")")
        onToggleClick?()
    }

    private func showMenu() {
        guard let button = toggleItem.button else { return }
        let y = button.isFlipped ? button.bounds.maxY + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: button)
    }

    private func updateImage() {
        let image = state == .hidden
            ? Self.symbol("chevron.left", "Show hidden icons")
            : Self.symbol("chevron.right", "Hide icons")
        toggleItem.button?.image = image
    }

    private static func symbol(_ name: String, _ description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }
}
