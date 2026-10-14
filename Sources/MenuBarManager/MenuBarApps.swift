import AppKit
import ApplicationServices

/// An app that can be hidden: on macOS 27 hiding works per app, not per icon.
struct MenuBarApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let isRunning: Bool
    var id: String { bundleID }

    var icon: NSImage {
        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

/// Finds the apps that have icons in the menu bar.
///
/// On macOS 27 the window list no longer shows status items, but every
/// process still publishes its icons under AXExtrasMenuBar, so asking each
/// running app through Accessibility tells which ones have any.
enum MenuBarApps {
    /// Apple's own processes that draw the clock, Control Center and other
    /// system items. Those are never hidden, so they aren't offered.
    private static let excluded: Set<String> = [
        "com.apple.MenuBarAgent",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
    ]

    /// Running apps with menu bar icons, plus `alsoInclude` (apps already
    /// chosen for hiding, which may not be running), sorted by name.
    ///
    /// Accessibility calls block, so this runs off the main thread. Without
    /// Accessibility it falls back to every running background or regular
    /// app, which includes some without icons.
    @MainActor
    static func list(alsoInclude: Set<String>) async -> [MenuBarApp] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> (String, String, pid_t, Bool)? in
            guard
                let bundleID = app.bundleIdentifier,
                app.processIdentifier != ownPID,
                !excluded.contains(bundleID),
                // macOS runs dozens of hidden Apple helpers; none has icons.
                !(app.activationPolicy == .prohibited && bundleID.hasPrefix("com.apple."))
            else { return nil }
            let name = app.localizedName ?? bundleID
            return (bundleID, name, app.processIdentifier, app.activationPolicy == .prohibited)
        }
        let trusted = AXIsProcessTrusted()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var apps: [String: MenuBarApp] = [:]
                for (bundleID, name, pid, isBackgroundOnly) in running {
                    let hasIcons = trusted ? hasMenuBarIcons(pid: pid) : !isBackgroundOnly
                    if hasIcons {
                        apps[bundleID] = MenuBarApp(bundleID: bundleID, name: name, isRunning: true)
                    }
                }
                for bundleID in alsoInclude where apps[bundleID] == nil {
                    let isRunning = running.contains { $0.0 == bundleID }
                    apps[bundleID] = MenuBarApp(bundleID: bundleID, name: displayName(for: bundleID), isRunning: isRunning)
                }
                let sorted = apps.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                continuation.resume(returning: sorted)
            }
        }
    }

    private static func hasMenuBarIcons(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var bar: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &bar) == .success,
            let bar, CFGetTypeID(bar) == AXUIElementGetTypeID()
        else { return false }
        var count: CFIndex = 0
        return AXUIElementGetAttributeValueCount(bar as! AXUIElement, kAXChildrenAttribute as CFString, &count) == .success
            && count > 0
    }

    private static func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
