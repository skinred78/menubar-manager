import AppKit
import ServiceManagement
import Combine
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var hasAccessibility = Permissions.hasAccessibility
    @State private var hasScreenRecording = Permissions.hasScreenRecording
    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Hiding") {
                LabeledContent("Hide again after") {
                    Stepper(value: $settings.rehideDelay, in: 2...60, step: 1) {
                        Text("\(Int(settings.rehideDelay)) seconds")
                            .monospacedDigit()
                    }
                }
                Toggle("Hide again when I switch apps", isOn: $settings.rehideOnAppSwitch)
            }

            Section("Bar below the menu bar") {
                Picker("Show hidden icons in a bar", selection: $settings.barMode) {
                    ForEach(Settings.BarMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                permissionRow(
                    "Accessibility",
                    detail: "Lets a click in the bar open the real icon's menu.",
                    granted: hasAccessibility,
                    pane: "Privacy_Accessibility",
                    request: Permissions.requestAccessibility
                )
                permissionRow(
                    "Screen Recording",
                    detail: "Shows the real icons. Without it the bar shows app icons.",
                    granted: hasScreenRecording,
                    pane: "Privacy_ScreenCapture",
                    request: Permissions.requestScreenRecording
                )
            }
            .onReceive(permissionTimer) { _ in
                hasAccessibility = Permissions.hasAccessibility
                hasScreenRecording = Permissions.hasScreenRecording
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
            }

            Section("Arranging icons") {
                Text("Hold Command and drag icons in the menu bar. Icons left of the thin divider line are hidden; icons to its right stay visible. Choose Edit Layout from the divider's menu to keep everything shown while you arrange. macOS remembers the positions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }

    private func permissionRow(
        _ title: String,
        detail: String,
        granted: Bool,
        pane: String,
        request: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow…") {
                    request()
                    Permissions.openPrivacySettings(pane)
                }
            }
        } label: {
            Text(title)
            Text(detail)
        }
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
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: .shared)))
            window.title = "MenuBar Manager Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
