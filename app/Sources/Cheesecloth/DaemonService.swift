// The daemon as a launchd daemon in the app bundle, through SMAppService.

import CheeseclothKit
import Foundation
import ServiceManagement

/// Registers and unregisters the LaunchDaemon that runs the bundled
/// `cheesecloth daemon`.
@MainActor
struct DaemonService {
    /// In Contents/Library/LaunchDaemons.
    static let plist = "ca.janderson.cheesecloth.plist"

    private let service = SMAppService.daemon(plistName: DaemonService.plist)

    /// Whether the app runs from its bundle. Run with `swift run`, it does
    /// not, and talks to a daemon started by hand instead.
    nonisolated static var inBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var registration: Registration {
        guard DaemonService.inBundle else { return .unmanaged }
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .notRegistered
        @unknown default: return .notRegistered
        }
    }

    /// Registers the daemon, which starts it. The first time, macOS asks the
    /// user to allow it, and the status is `requiresApproval` until then.
    func register() throws {
        guard DaemonService.inBundle, service.status != .enabled else { return }
        do {
            try service.register()
        } catch where service.status == .requiresApproval {
            // Registered, and waiting for the user's approval:
            // `registration` says so.
        }
    }

    /// Unregisters the daemon. launchd stops it with SIGTERM, and the daemon
    /// shuts down cleanly.
    func unregister() async throws {
        guard DaemonService.inBundle, service.status == .enabled else { return }
        let service = self.service
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
            service.unregister { error in
                if let error { done.resume(throwing: error) } else { done.resume() }
            }
        }
    }

    /// Opens System Settings > General > Login Items, where the user allows
    /// the daemon.
    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Starts the app at login.
    func registerApp() throws {
        guard DaemonService.inBundle, SMAppService.mainApp.status != .enabled else { return }
        try SMAppService.mainApp.register()
    }
}
