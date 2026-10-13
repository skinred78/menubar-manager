import AppKit

/// A slim panel just under the menu bar that shows the hidden icons, for
/// displays where revealing them inline would push some behind the notch.
///
/// Clicking an icon in the bar reveals the hidden section and presses the real
/// item through Accessibility, so its own menu or window opens as usual.
@MainActor
final class NotchBarController {
    private let section: SectionController
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private var appObserver: NSObjectProtocol?
    private var captureTask: Task<Void, Never>?
    private var buttons: [CGWindowID: NSButton] = [:]

    var isVisible: Bool { panel?.isVisible ?? false }

    init(section: SectionController) {
        self.section = section
    }

    /// Whether clicking the arrow on `screen` should open the bar instead of
    /// revealing icons inline.
    func shouldUseBar(on screen: NSScreen, mode: Settings.BarMode) -> Bool {
        switch mode {
        case .never: return false
        case .always: return true
        case .automatic: return screen.safeAreaInsets.top > 0
        }
    }

    func show(on screen: NSScreen) {
        close()
        guard let dividerFrame = section.dividerFrame else { return }
        let items = ItemScanner.hiddenItems(dividerFrame: dividerFrame)

        if !Permissions.hasAccessibility {
            once("didRequestAccessibility", Permissions.requestAccessibility)
        }
        if !Permissions.hasScreenRecording {
            once("didRequestScreenRecording", Permissions.requestScreenRecording)
        }

        let panel = makePanel(items: items)
        position(panel, on: screen)
        panel.orderFrontRegardless()
        self.panel = panel
        startClosingTriggers()

        // Show app icons straight away, then swap in real captures as they arrive.
        let scale = screen.backingScaleFactor
        captureTask = Task { [weak self] in
            let images = await ItemImageCapturer.capture(items, scale: scale)
            guard !Task.isCancelled else { return }
            self?.apply(images)
        }
    }

    func close() {
        captureTask?.cancel()
        captureTask = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        appObserver = nil
        panel?.orderOut(nil)
        panel = nil
        buttons = [:]
    }

    // MARK: Building the panel

    private func makePanel(items: [MenuBarItem]) -> NSPanel {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)

        if items.isEmpty {
            let label = NSTextField(labelWithString: "No hidden icons")
            label.font = .menuFont(ofSize: 0)
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label)
        }

        for item in items {
            let button = ItemButton(item: item) { [weak self] item in
                self?.itemClicked(item)
            }
            buttons[item.windowID] = button
            stack.addArrangedSubview(button)
        }

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true

        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: stack.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = background
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.setContentSize(stack.fittingSize)
        return panel
    }

    /// Right-aligns the bar under the arrow, on whichever display was clicked.
    private func position(_ panel: NSPanel, on screen: NSScreen) {
        let size = panel.frame.size
        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)

        var rightEdge = screen.frame.maxX - 8
        if let toggle = section.toggleFrame, let toggleScreen = section.toggleScreen {
            let offsetFromRight = toggleScreen.frame.maxX - toggle.maxX
            rightEdge = screen.frame.maxX - offsetFromRight
        }
        var x = rightEdge - size.width
        x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let y = screen.frame.maxY - menuBarHeight - size.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func apply(_ images: [CGWindowID: NSImage]) {
        for (windowID, image) in images {
            buttons[windowID]?.image = image
        }
    }

    // MARK: Closing

    private func startClosingTriggers() {
        // A click anywhere else, or switching apps, closes the bar.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    // MARK: Clicking an item

    private func itemClicked(_ item: MenuBarItem) {
        close()
        // Bring the hidden icons back so the item's menu or window opens in a
        // sensible place; the usual auto-rehide collapses them afterwards.
        section.reveal()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            MainActor.assumeIsolated {
                let current = ItemScanner.refreshed(item) ?? item
                if !ItemPresser.press(current) {
                    // Without Accessibility we can't press it for you; the
                    // icons are revealed, so it can be clicked directly.
                    NSSound.beep()
                }
            }
        }
    }

    // MARK: Permissions

    /// Asks macOS for a permission the first time only; after that the
    /// Settings window shows what's missing.
    private func once(_ key: String, _ request: () -> Void) {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        request()
    }
}

/// One icon in the bar. Accepts the first click even though the panel never
/// becomes active.
private final class ItemButton: NSButton {
    private let item: MenuBarItem
    private let onClick: (MenuBarItem) -> Void

    init(item: MenuBarItem, onClick: @escaping (MenuBarItem) -> Void) {
        self.item = item
        self.onClick = onClick
        super.init(frame: NSRect(origin: .zero, size: item.frame.size))
        image = item.appIcon
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        isBordered = false
        toolTip = item.displayName
        setAccessibilityLabel(item.displayName)
        target = self
        action = #selector(clicked)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: max(item.frame.width, 22)).isActive = true
        heightAnchor.constraint(equalToConstant: max(item.frame.height, 22)).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func clicked() { onClick(item) }
}
