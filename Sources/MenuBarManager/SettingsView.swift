import AppKit
import Combine
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @State private var apps: [MenuBarApp] = []
    @State private var isLoadingApps = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var hasAccessibility = Permissions.hasAccessibility
    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                if apps.isEmpty {
                    Text(isLoadingApps ? "Looking for menu bar apps…" : "No apps found.")
                        .foregroundStyle(.secondary)
                }
                ForEach(apps) { app in
                    Toggle(isOn: hiddenBinding(for: app.bundleID)) {
                        HStack(spacing: 8) {
                            Image(nsImage: app.icon)
                            Text(app.name)
                            if !app.isRunning {
                                Text("not running")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Hide icons of these apps")
                    Spacer()
                    Button("Refresh") { Task { await loadApps() } }
                        .disabled(isLoadingApps)
                }
            } footer: {
                Text("macOS 27 hides menu bar icons app by app, so an app's icons are all hidden or all shown. Apple's own items, like the clock, Wi-Fi and Control Center, always stay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Permissions") {
                LabeledContent {
                    if hasAccessibility {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow…") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                } label: {
                    Text("Accessibility")
                    Text(hasAccessibility
                        ? "The list shows only apps with menu bar icons."
                        : "Without it the list shows every running app, including some with no icons.")
                }
            }
            .onReceive(permissionTimer) { _ in
                let granted = Permissions.hasAccessibility
                if granted != hasAccessibility {
                    hasAccessibility = granted
                    Task { await loadApps() }
                }
            }

            Section("Hiding") {
                LabeledContent("Hide again after") {
                    Stepper(value: $settings.rehideDelay, in: 2...60, step: 1) {
                        Text("\(Int(settings.rehideDelay)) seconds")
                            .monospacedDigit()
                    }
                }
                Toggle("Hide again when I switch apps", isOn: $settings.rehideOnAppSwitch)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Click the arrow in the menu bar to show or hide icons, right-click it for Settings and Quit. Command-drag icons to rearrange them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .frame(minHeight: 360, maxHeight: 640)
        .task { await loadApps() }
    }

    private func hiddenBinding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { settings.hiddenBundleIDs.contains(bundleID) },
            set: { hidden in
                if hidden {
                    settings.hiddenBundleIDs.insert(bundleID)
                } else {
                    settings.hiddenBundleIDs.remove(bundleID)
                }
            }
        )
    }

    private func loadApps() async {
        isLoadingApps = true
        apps = await MenuBarApps.list(alsoInclude: settings.hiddenBundleIDs)
        isLoadingApps = false
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Hosts SettingsView in a plain window, since an agent app has no Settings scene.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onShow: (() -> Void)?
    var onClose: (() -> Void)?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: .shared)))
            window.title = "MenuBar Manager Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        onShow?()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        // Build a fresh view next time, so the app list is read again.
        window = nil
    }
}
