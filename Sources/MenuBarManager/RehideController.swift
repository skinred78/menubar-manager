import AppKit

/// Hides the chosen icons again after a delay, or when another app
/// becomes active, unless the user is still using the menu bar.
@MainActor
final class RehideController {
    private let section: SectionController
    private let settings: Settings
    private var timer: Timer?
    private var appObserver: NSObjectProtocol?

    /// While true (Settings is open), nothing rehides automatically.
    var isSuspended = false {
        didSet {
            if isSuspended { cancel() } else { schedule() }
        }
    }

    init(section: SectionController, settings: Settings) {
        self.section = section
        self.settings = settings

        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.appDidActivate() }
        }
    }

    func sectionDidChange(to state: SectionController.State) {
        switch state {
        case .revealed: schedule()
        case .hidden: cancel()
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    private func schedule(after delay: TimeInterval? = nil) {
        cancel()
        guard !isSuspended, section.state == .revealed else { return }
        let interval = delay ?? settings.rehideDelay
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFired() }
        }
    }

    private func timerFired() {
        guard !isSuspended, section.state == .revealed else { return }
        if MenuBarActivity.userIsInMenuBar {
            // Check again shortly rather than pulling icons out from under the pointer.
            schedule(after: 1)
        } else {
            section.hide()
        }
    }

    private func appDidActivate() {
        guard settings.rehideOnAppSwitch, !isSuspended, section.state == .revealed else { return }
        // Clicking a revealed icon can activate its app; don't collapse then.
        guard !MenuBarActivity.userIsInMenuBar else { return }
        section.hide()
    }
}

/// Signals that the user is still working in the menu bar.
@MainActor
enum MenuBarActivity {
    static var userIsInMenuBar: Bool {
        pointerIsInMenuBar || aMenuIsOpen
    }

    /// True when the pointer is over the menu bar of any display.
    static var pointerIsInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let frame = screen.frame
            guard mouse.x >= frame.minX, mouse.x <= frame.maxX else { continue }
            var height = frame.maxY - screen.visibleFrame.maxY
            if height <= 0 { height = NSStatusBar.system.thickness }
            if mouse.y >= frame.maxY - height, mouse.y <= frame.maxY {
                return true
            }
        }
        return false
    }

    /// True when any app has a menu open (for example a revealed icon's menu).
    /// Reads only window levels, which needs no permission.
    static var aMenuIsOpen: Bool {
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }
        return windows.contains { ($0[kCGWindowLayer as String] as? Int) == menuLevel }
    }
}
