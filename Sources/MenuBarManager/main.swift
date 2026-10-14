import AppKit

// Top-level code isn't main-actor isolated in Swift 5 mode, but it does run
// on the main thread, so say so explicitly.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
