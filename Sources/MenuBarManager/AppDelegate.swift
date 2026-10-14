import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private var section: SectionController!
    private var rehide: RehideController!
    private let settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.write("launched, macOS \(ProcessInfo.processInfo.operatingSystemVersionString), screens \(NSScreen.screens.map { NSStringFromRect($0.frame) })")
        section = SectionController(settings: settings, menu: makeMenu())
        rehide = RehideController(section: section, settings: settings)

        section.onToggleClick = { [weak self] in self?.toggleClicked() }
        section.onStateChange = { [weak self] state in
            self?.rehide.sectionDidChange(to: state)
        }

        // Everything stays shown while choosing apps, then hides on close.
        settingsWindow.onShow = { [weak self] in
            self?.section.reveal()
            self?.rehide.isSuspended = true
        }
        settingsWindow.onClose = { [weak self] in
            guard let self else { return }
            self.rehide.isSuspended = false
            self.section.hide()
        }

        if settings.hasLaunchedBefore {
            section.hide()
        } else {
            settings.hasLaunchedBefore = true
            showWelcome()
            openSettings()
        }
    }

    /// Opening the app again (from Spotlight or Finder) shows everything and
    /// opens Settings. That's the way back if the arrow itself ever goes
    /// missing from the menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DebugLog.write("reopened")
        openSettings()
        return false
    }

    private func toggleClicked() {
        if settings.hiddenBundleIDs.isEmpty {
            // Nothing chosen yet, so there's nothing to hide.
            openSettings()
        } else {
            section.toggle()
        }
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit MenuBar Manager", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func quit() {
        section.reveal()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // MenuBarAgent drops the assertion when this process exits anyway;
        // releasing it here just makes that immediate.
        section?.reveal()
    }

    // MARK: First launch

    private func showWelcome() {
        let alert = NSAlert()
        alert.messageText = "Welcome to MenuBar Manager"
        alert.informativeText = """
        An arrow is now in your menu bar. Click it to hide or show the icons \
        you choose. Right-click it for Settings and Quit.

        On macOS 27 hiding works app by app. In Settings, tick the apps whose \
        icons you want hidden. Allowing Accessibility lets Settings list only \
        apps that actually have menu bar icons.

        If the arrow ever goes missing, open MenuBar Manager again from \
        Spotlight to show everything and get back to Settings.
        """
        alert.addButton(withTitle: "Choose Apps")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
