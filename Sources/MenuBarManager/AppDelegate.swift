import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private var section: SectionController!
    private var rehide: RehideController!
    private var notchBar: NotchBarController!
    private let settingsWindow = SettingsWindowController()
    private var editLayoutItem: NSMenuItem!

    private var isEditingLayout = false {
        didSet {
            editLayoutItem.state = isEditingLayout ? .on : .off
            rehide.isSuspended = isEditingLayout
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        section = SectionController(dividerMenu: makeDividerMenu())
        rehide = RehideController(section: section, settings: settings)
        notchBar = NotchBarController(section: section)

        section.onToggleClick = { [weak self] in self?.toggleClicked() }
        section.onStateChange = { [weak self] state in
            self?.rehide.sectionDidChange(to: state)
        }

        if settings.hasLaunchedBefore {
            // Give macOS a moment to place the status items before checking
            // where the divider sits.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                MainActor.assumeIsolated { _ = self?.section.hide() }
            }
        } else {
            settings.hasLaunchedBefore = true
            isEditingLayout = true
            showWelcome()
        }
    }

    private func toggleClicked() {
        if isEditingLayout {
            // Finishing an edit by clicking the arrow hides straight away.
            isEditingLayout = false
            section.hide(userInitiated: true)
        } else if notchBar.isVisible {
            notchBar.close()
        } else if section.state == .hidden,
                  let screen = screenUnderPointer,
                  notchBar.shouldUseBar(on: screen, mode: settings.barMode) {
            notchBar.show(on: screen)
        } else {
            section.toggle()
        }
    }

    private var screenUnderPointer: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    // MARK: Divider menu

    private func makeDividerMenu() -> NSMenu {
        let menu = NSMenu()
        editLayoutItem = NSMenuItem(title: "Edit Layout", action: #selector(toggleEditLayout), keyEquivalent: "")
        editLayoutItem.target = self
        menu.addItem(editLayoutItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit MenuBar Manager", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func toggleEditLayout() {
        notchBar.close()
        if isEditingLayout {
            isEditingLayout = false
        } else {
            section.reveal()
            isEditingLayout = true
        }
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func quit() {
        notchBar.close()
        // Leave the bar in its normal state so nothing stays pushed off screen.
        section.reveal()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        section?.reveal()
    }

    // MARK: First launch

    private func showWelcome() {
        let alert = NSAlert()
        alert.messageText = "Welcome to MenuBar Manager"
        alert.informativeText = """
        Two new items are in your menu bar: an arrow and a thin divider line.

        Hold Command and drag icons you rarely use to the left of the divider. \
        Then click the arrow to hide them, and click it again to bring them back.

        You're in Edit Layout mode now, so nothing hides until you click the arrow. \
        Click the divider any time for Edit Layout, Settings and Quit.
        """
        alert.addButton(withTitle: "Got it")
        NSApp.activate()
        alert.runModal()
    }
}
