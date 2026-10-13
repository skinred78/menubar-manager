import AppKit

/// Owns the two status items this app adds to the menu bar and hides or
/// reveals everything left of the divider.
///
/// The trick: the divider is an ordinary status item. Stretching it to a huge
/// length pushes every item to its left off the edge of the screen. Shrinking
/// it back brings them into view. Other apps' items are never touched, and
/// macOS mirrors the divider to every display's menu bar, so this works on all
/// displays at once.
@MainActor
final class SectionController: NSObject {
    enum State { case revealed, hidden }

    private static let toggleName = "MBMToggle"
    private static let dividerName = "MBMDivider"
    private static let hiddenLength: CGFloat = 10_000

    let toggleItem: NSStatusItem
    let dividerItem: NSStatusItem

    private(set) var state: State = .revealed
    var onStateChange: ((State) -> Void)?

    /// Called when the user clicks the toggle icon.
    var onToggleClick: (() -> Void)?

    private let dividerMenu: NSMenu
    private var lastToggleClick = Date.distantPast

    init(dividerMenu: NSMenu) {
        self.dividerMenu = dividerMenu

        // Give each item a starting position (in points from the right edge)
        // the first time it is created. After that, macOS remembers wherever
        // the user Command-drags it, keyed by autosaveName.
        Self.seedPreferredPosition(for: Self.toggleName, position: 0)
        Self.seedPreferredPosition(for: Self.dividerName, position: 1)

        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggleItem.autosaveName = Self.toggleName

        dividerItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        dividerItem.autosaveName = Self.dividerName

        super.init()

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleClicked)
            button.toolTip = "Show or hide menu bar icons"
        }
        if #available(macOS 27, *) {
            // On macOS 27 a click on a status item without a menu starts an
            // "expanded interface session" instead of reliably sending the
            // button's action, so listen for that too.
            toggleItem.expandedInterfaceDelegate = self
        }

        dividerItem.button?.toolTip = "MenuBar Manager: icons left of this line are hidden"
        applyState()
    }

    // MARK: Public

    func toggle() {
        state == .hidden ? reveal() : hide()
    }

    func reveal() {
        guard state != .revealed else { return }
        state = .revealed
        applyState()
        onStateChange?(state)
    }

    /// Hides the section. Returns false if the divider is in the wrong place.
    @discardableResult
    func hide() -> Bool {
        guard state != .hidden else { return true }
        guard dividerIsLeftOfToggle else {
            showMisplacedDividerAlert()
            return false
        }
        state = .hidden
        applyState()
        onStateChange?(state)
        return true
    }

    // MARK: Private

    @objc private func toggleClicked() {
        handleToggleClick()
    }

    fileprivate func handleToggleClick() {
        // The button action and the macOS 27 session callback can both fire
        // for one click; treat them as a single click.
        let now = Date()
        guard now.timeIntervalSince(lastToggleClick) > 0.3 else { return }
        lastToggleClick = now
        onToggleClick?()
    }

    private func applyState() {
        switch state {
        case .revealed:
            dividerItem.length = NSStatusItem.variableLength
            dividerItem.button?.image = Self.dividerImage
            dividerItem.menu = dividerMenu
            toggleItem.button?.image = Self.symbol("chevron.right", "Hide icons")
        case .hidden:
            dividerItem.menu = nil
            dividerItem.button?.image = nil
            dividerItem.length = Self.hiddenLength
            toggleItem.button?.image = Self.symbol("chevron.left", "Show hidden icons")
        }
    }

    /// The divider must sit left of the toggle, or stretching it would hide
    /// the toggle too and leave no way to get the icons back.
    private var dividerIsLeftOfToggle: Bool {
        guard
            let divider = dividerItem.button?.window?.frame,
            let toggle = toggleItem.button?.window?.frame
        else { return true }
        // Not laid out yet: don't block hiding on a frame we can't trust.
        if divider.width == 0 || toggle.width == 0 || divider.midX == toggle.midX { return true }
        return divider.midX < toggle.midX
    }

    private func showMisplacedDividerAlert() {
        let alert = NSAlert()
        alert.messageText = "The divider is on the wrong side"
        alert.informativeText = "Hold Command and drag the thin divider line so it sits to the left of the arrow icon. Icons left of the divider are the ones that get hidden."
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    private static func seedPreferredPosition(for autosaveName: String, position: CGFloat) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(position, forKey: key)
        }
    }

    private static func symbol(_ name: String, _ description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    private static let dividerImage: NSImage = {
        let size = NSSize(width: 6, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: rect.midX - 1, y: 1, width: 2, height: rect.height - 2),
                xRadius: 1, yRadius: 1
            ).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Divider"
        return image
    }()
}

@available(macOS 27, *)
extension SectionController: NSStatusItemExpandedInterfaceDelegate {
    nonisolated func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        MainActor.assumeIsolated {
            handleToggleClick()
        }
    }

    nonisolated func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {}
}
