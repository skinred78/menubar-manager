import AppKit
import ApplicationServices
import ScreenCaptureKit

/// Another app's icon in the menu bar.
struct MenuBarItem {
    let windowID: CGWindowID
    let pid: pid_t
    /// Window bounds in global display coordinates (origin top-left of the
    /// main display, y grows downward), as Core Graphics and Accessibility use.
    let frame: CGRect

    var app: NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }

    var appIcon: NSImage? {
        guard let icon = app?.icon?.copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    var displayName: String { app?.localizedName ?? "Menu bar item" }
}

/// Finds menu bar items from the window list. Reading window bounds and owners
/// needs no permission.
@MainActor
enum ItemScanner {
    /// Items currently in the hidden section, left to right.
    static func hiddenItems(dividerFrame: CGRect) -> [MenuBarItem] {
        // Only x matters, and x is the same in AppKit and Core Graphics space.
        let boundary = dividerFrame.minX
        return allItems().filter { $0.frame.maxX <= boundary + 1 }
    }

    static func allItems() -> [MenuBarItem] {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var items: [MenuBarItem] = []
        for info in windows {
            guard
                (info[kCGWindowLayer as String] as? Int) == statusLevel,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                let number = info[kCGWindowNumber as String] as? CGWindowID,
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                bounds.width > 0, bounds.width < 600,
                bounds.height > 0, bounds.height <= 50
            else { continue }
            items.append(MenuBarItem(windowID: number, pid: pid, frame: bounds))
        }
        return items.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Finds the item again by window ID, with its current frame.
    static func refreshed(_ item: MenuBarItem) -> MenuBarItem? {
        allItems().first { $0.windowID == item.windowID }
    }
}

/// Grabs each icon's real pixels with ScreenCaptureKit. Needs Screen Recording.
enum ItemImageCapturer {
    static func capture(_ items: [MenuBarItem], scale: CGFloat) async -> [CGWindowID: NSImage] {
        guard CGPreflightScreenCaptureAccess(), !items.isEmpty else { return [:] }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            return [:]
        }
        let windowsByID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })

        var images: [CGWindowID: NSImage] = [:]
        for item in items {
            guard let window = windowsByID[item.windowID] else { continue }
            if let image = await captureWithTimeout(window: window, size: item.frame.size, scale: scale) {
                images[item.windowID] = image
            }
        }
        return images
    }

    private static func captureWithTimeout(window: SCWindow, size: CGSize, scale: CGFloat) async -> NSImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(size.width * scale))
        config.height = max(1, Int(size.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        // A capture can hang on macOS 27; never let one block the bar.
        let cgImage: CGImage? = await withTaskGroup(of: CGImage?.self) { group in
            group.addTask {
                try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 800_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let cgImage, !isBlank(cgImage) else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }

    /// A fully transparent capture means macOS refused to give us the pixels.
    /// Captures are premultiplied, so transparent pixels are all zero bytes.
    private static func isBlank(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return false }
        let length = CFDataGetLength(data)
        for index in 0..<length where bytes[index] != 0 {
            return false
        }
        return true
    }
}

/// Opens an item's menu through Accessibility, without moving the pointer.
/// Needs Accessibility permission.
@MainActor
enum ItemPresser {
    /// Presses the menu bar extra of `item`'s app whose position matches the
    /// item's window. Returns false if it couldn't.
    static func press(_ item: MenuBarItem) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(app, 0.5)

        guard
            let bar: AXUIElement = attribute(app, kAXExtrasMenuBarAttribute),
            let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute),
            !children.isEmpty
        else { return false }

        let target: AXUIElement?
        if children.count == 1 {
            target = children.first
        } else {
            target = children.min { distance($0, to: item.frame) < distance($1, to: item.frame) }
        }
        guard let target else { return false }
        return AXUIElementPerformAction(target, kAXPressAction as CFString) == .success
    }

    private static func distance(_ element: AXUIElement, to frame: CGRect) -> CGFloat {
        guard let position = point(element) else { return .greatestFiniteMagnitude }
        return abs(position.x - frame.minX) + abs(position.y - frame.minY)
    }

    private static func point(_ element: AXUIElement) -> CGPoint? {
        guard let value: AXValue = attribute(element, kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

/// The two permissions the bar uses, and how to ask for them.
@MainActor
enum Permissions {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
