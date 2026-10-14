import AppKit

/// Hides other apps' menu bar icons on macOS 27.
///
/// macOS 27 draws the whole menu bar in one window owned by MenuBarAgent, so
/// the old trick of stretching a divider to push icons off screen does
/// nothing. MenuBarAgent does offer an "assessment mode" through the private
/// MenuBarClientCore framework: while an assertion is live, only the system
/// items and the apps on its allowlist keep their icons. Hiding is therefore
/// per app, not per icon. Technique learned from Thaw's PlatformRuntimeKit and
/// Ice's macOS 27 work (jordanbaird/Ice#995, #1001).
///
/// An allowlist only covers apps running when it was made, so the assertion is
/// remade whenever an app launches or quits.
@MainActor
final class Concealer {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configureSelector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")

    /// MenuBarAgent numbers its own items (battery, clock, Wi-Fi, Control
    /// Center and so on). Keep all of them; this app only hides other apps.
    private static let systemItems = (0...63).map { NSNumber(value: $0) } as NSArray

    private static let classes: (configuration: NSObject.Type, assertion: NSObject.Type)? = {
        guard
            dlopen(frameworkPath, RTLD_NOW) != nil,
            let configuration = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
            let assertion = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
            configuration.instancesRespond(to: configureSelector),
            assertion.instancesRespond(to: activateSelector),
            assertion.instancesRespond(to: invalidateSelector)
        else { return nil }
        return (configuration, assertion)
    }()

    /// Whether this macOS build offers the assertion.
    static var isAvailable: Bool { classes != nil }

    private var assertion: NSObject?
    private var hiddenBundleIDs: Set<String> = []
    private(set) var isConcealing = false
    /// Bumped on every change, so a slow activation that's been superseded
    /// gets thrown away instead of replacing a newer one.
    private var generation = 0
    private var terminationObserver: NSObjectProtocol?
    private var launchObservation: NSKeyValueObservation?
    /// Hidden apps that just launched, shown for a moment while they create
    /// their icons. An icon created under a live assertion can come out
    /// squashed (seen with AlDente, jordanbaird/Ice#1007).
    private var launching: Set<String> = []
    private static let launchGrace: TimeInterval = 5

    init() {
        // The running list changes as soon as a process checks in, earlier
        // than didLaunchApplication, which may come after the icon exists.
        launchObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, change in
            guard change.kind == .insertion else { return }
            let bundleIDs = (change.newValue ?? []).compactMap(\.bundleIdentifier)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.appsLaunched(bundleIDs) }
            }
        }
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isConcealing else { return }
                self.apply()
            }
        }
    }

    /// Hides every app in `bundleIDs` and keeps it hidden until `release()`.
    func conceal(_ bundleIDs: Set<String>) {
        hiddenBundleIDs = bundleIDs
        isConcealing = true
        apply()
    }

    /// Shows everything again.
    func release() {
        isConcealing = false
        generation += 1
        invalidate(assertion)
        assertion = nil
    }

    private func apply() {
        generation += 1
        let thisGeneration = generation
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var allowed = running.subtracting(hiddenBundleIDs.subtracting(launching))
        if let own = Bundle.main.bundleIdentifier { allowed.insert(own) }

        Task {
            do {
                let new = try await Self.activate(allowed: Array(allowed))
                guard thisGeneration == generation, isConcealing else {
                    invalidate(new)
                    return
                }
                // Activate the new assertion before dropping the old one, so
                // apps hidden under both don't flicker back for a moment.
                invalidate(assertion)
                assertion = new
                DebugLog.write("concealing \(hiddenBundleIDs.sorted()) with \(allowed.count) apps allowed")
            } catch {
                DebugLog.write("could not conceal: \(error)")
            }
        }
    }

    private func appsLaunched(_ bundleIDs: [String]) {
        guard isConcealing, !bundleIDs.isEmpty else { return }
        let hiddenLaunches = Set(bundleIDs).intersection(hiddenBundleIDs)
        launching.formUnion(hiddenLaunches)
        // Every launch needs a fresh allowlist: one only covers apps that
        // were running when it was made.
        apply()
        guard !hiddenLaunches.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchGrace) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.launching.subtract(hiddenLaunches)
                if self.isConcealing { self.apply() }
            }
        }
    }

    private func invalidate(_ assertion: NSObject?) {
        _ = assertion?.perform(Self.invalidateSelector)
    }

    /// Lets either the completion handler or the timeout finish, never both.
    private final class OneShot: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { claimed = true; lock.unlock() }
            return !claimed
        }
    }

    private enum Failure: Error {
        case unavailable, timedOut
        case rejected(String)
    }

    private static func activate(allowed: [String]) async throws -> NSObject {
        guard
            let classes,
            let configuration = allocate(classes.configuration)?
                .perform(configureSelector, with: systemItems, with: allowed as NSArray)?
                .takeUnretainedValue() as? NSObject,
            let assertion = allocate(classes.assertion)?
                .perform(NSSelectorFromString("init"))?
                .takeUnretainedValue() as? NSObject
        else { throw Failure.unavailable }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let once = OneShot()
                let finish: @Sendable (Error?) -> Void = { error in
                    guard once.claim() else { return }
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
                // MenuBarAgent may answer on any queue, or not at all.
                let completion: @convention(block) (Any?) -> Void = { error in
                    finish(error.map { Failure.rejected(String(describing: $0)) })
                }
                _ = assertion.perform(activateSelector, with: configuration, with: completion)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    finish(Failure.timedOut)
                }
            }
        } catch {
            _ = assertion.perform(invalidateSelector)
            throw error
        }
        return assertion
    }

    /// `+alloc` without `-init`, so the private class's own initializer runs exactly once.
    private static func allocate(_ type: NSObject.Type) -> NSObject? {
        (type as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject
    }
}
