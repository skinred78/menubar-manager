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
    /// Wide enough to push everything to its left off the widest display.
    /// macOS 27 may refuse absurd lengths, so stay close to real screen sizes.
    private static var hiddenLength: CGFloat {
        let widest = NSScreen.screens.map(\.frame.width).max() ?? 2000
        return widest + 200
    }

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
        // Deliberately no expandedInterfaceDelegate: on macOS 27, setting it
        // stops left clicks from sending the button action, and the session
        // it opens swallows the next click, so the arrow only works once.

        dividerItem.button?.toolTip = "MenuBar Manager: icons left of this line are hidden"
        applyState()
    }

    // MARK: Public

    /// The divider's frame in AppKit screen coordinates. Its left edge is the
    /// boundary: items further left are in the hidden section.
    var dividerFrame: CGRect? { dividerItem.button?.window?.frame }

    /// The toggle's frame and the screen it sits on.
    var toggleFrame: CGRect? { toggleItem.button?.window?.frame }
    var toggleScreen: NSScreen? { toggleItem.button?.window?.screen }

    func toggle() {
        if state == .hidden {
            reveal()
        } else {
            hide(userInitiated: true)
        }
    }

    func reveal() {
        guard state != .revealed else { return }
        state = .revealed
        applyState()
        onStateChange?(state)
    }

    /// Hides the section. Returns false if the divider is in the wrong place.
    /// Only a hide the user asked for explains the problem; automatic hides
    /// (rehide timer, app switches, launch) fail quietly so they can't pop up
    /// the same warning over and over.
    @discardableResult
    func hide(userInitiated: Bool = false) -> Bool {
        guard state != .hidden else { return true }
        guard dividerIsLeftOfToggle else {
            NSLog("MenuBarManager: not hiding, divider %@ is not left of toggle %@",
                  String(describing: dividerFrame), String(describing: toggleFrame))
            if userInitiated { showMisplacedDividerAlert() }
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

    private func handleToggleClick() {
        // Ignore a double fire from one click.
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
        logLayout(after: state)
    }

    /// Writes what macOS actually did with the divider, so problems can be
    /// read with: log show --last 5m --predicate 'process == "MenuBarManager"'
    private func logLayout(after state: State) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let divider = self.dividerFrame ?? .zero
                let items = ItemScanner.allItems()
                let leftOfDivider = items.filter { $0.frame.maxX <= divider.minX + 1 }
                let names = leftOfDivider.map(\.displayName).joined(separator: ", ")
                NSLog("MenuBarManager layout [%@]: requested length %.0f, divider %@, toggle %@, %d of %d items left of divider: %@",
                      state == .hidden ? "hidden" : "revealed",
                      self.dividerItem.length,
                      NSStringFromRect(divider),
                      NSStringFromRect(self.toggleFrame ?? .zero),
                      leftOfDivider.count, items.count, names)
            }
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

    private var isShowingAlert = false

    private func showMisplacedDividerAlert() {
        guard !isShowingAlert else { return }
        isShowingAlert = true
        defer { isShowingAlert = false }
        let alert = NSAlert()
        alert.messageText = "The divider is on the wrong side"
        alert.informativeText = "Hold Command and drag the thin divider line so it sits to the left of the arrow icon. Icons left of the divider are the ones that get hidden."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
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
