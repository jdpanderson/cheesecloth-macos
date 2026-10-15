// The app's state: what the menu and the pages show, and the actions. It
// asks the daemon only when the menu or a page opens, and every few seconds
// while the status window is open; nothing runs while no window is open.

import AppKit
import CheeseclothKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var state: MenuState = .starting
    private(set) var peers: [Peer] = []
    private(set) var proposals: [Proposal] = []
    private(set) var invite: Invite?
    /// The result of the last action, for people.
    private(set) var notice: String?
    /// The last action's error, as the daemon wrote it.
    private(set) var error: String?
    private(set) var busy = false

    private let client: Client
    private let daemon = DaemonService()
    private var registeredAt: Date?

    init() {
        let env = ProcessInfo.processInfo.environment
        client = Client(socket: env["CHEESECLOTH_SOCKET"] ?? Client.defaultSocket)
    }

    /// At launch: start at login, and start the daemon.
    func launch() {
        do {
            try daemon.registerApp()
        } catch {
            self.error = "Can't start Cheesecloth at login: \(error.localizedDescription)"
        }
        startDaemon()
    }

    private func startDaemon() {
        do {
            try daemon.register()
            if daemon.registration == .enabled { registeredAt = Date() }
        } catch {
            self.error = "Can't start the daemon: \(error.localizedDescription)"
        }
    }

    /// The status and the proposals waiting for approval, when the menu or
    /// a page asks.
    func refresh() async {
        if state == .quitting { return }
        var registration = daemon.registration
        if registration == .notRegistered || registration == .requiresApproval {
            // Allowed in System Settings since the last look: register again,
            // which now starts it.
            startDaemon()
            registration = daemon.registration
        }
        let status: Result<Status, APIError>
        let pending: [Proposal]?
        do {
            let (s, p) = try await client.session { session -> (Status, [Proposal]?) in
                let status: Status = try session.send(.status)
                // Only an admin may approve or reject; ask only then.
                let pending: [Proposal]? = status.isAdmin ? try session.send(.pending) : nil
                return (status, pending)
            }
            status = .success(s)
            pending = p
        } catch let error as APIError {
            status = .failure(error)
            pending = nil
        } catch {
            status = .failure(.protocolError(error.localizedDescription))
            pending = nil
        }
        proposals = pending ?? []
        state = MenuState(
            registration: registration, status: status,
            sinceRegistered: registeredAt.map { Date().timeIntervalSince($0) })
    }

    /// Drops the invite shown last, so the invite page starts empty.
    func forgetInvite() {
        invite = nil
    }

    func clearMessages() {
        error = nil
        notice = nil
    }

    func loadPeers() async {
        await run { client in
            let peers: [Peer] = try await client.call(.peers)
            self.peers = peers.sorted { ($0.thisNode ? 0 : 1, $0.name) < ($1.thisNode ? 0 : 1, $1.name) }
        }
    }

    func createInvite(permissions: Permissions) async {
        invite = nil
        await run { client in
            self.invite = try await client.call(.invite(permissions: permissions))
        }
    }

    func join(token: String) async {
        await run { client in
            let joined: Joined = try await client.call(.join(token: token))
            if joined.joined {
                self.notice = "Joined. This Mac's address is \(joined.ipv4 ?? "?")."
            } else {
                self.notice =
                    "Waiting for approval. Members check this node ID: \(joined.nodeId ?? "?")"
            }
            await self.refresh()
        }
    }

    func create(ipv4Range: String, strictSecurity: Bool) async {
        let range = ipv4Range.trimmingCharacters(in: .whitespaces)
        await run { client in
            let created: Created = try await client.call(
                .initialize(ipv4Range: range.isEmpty ? nil : range, strictSecurity: strictSecurity))
            self.notice = "Created network \(shortID(created.clusterId)), \(created.ipv4Range)."
            await self.refresh()
        }
    }

    /// Leaves the network, or cancels a join. With `force`, goes on past
    /// steps that fail.
    func leave(force: Bool) async {
        await run { client in
            let left: Left = try await client.call(.leave(force: force))
            switch left {
            case let .left(_, problems) where problems.isEmpty:
                self.notice = "Left the network."
            case let .left(_, problems):
                self.notice = "Left the network, but some steps failed:\n"
                    + problems.map { "• \($0)" }.joined(separator: "\n")
            case .joinCancelled:
                self.notice =
                    "Join cancelled on this Mac. A member may still need to reject the request."
            }
            await self.refresh()
        }
    }

    func remove(_ peer: Peer) async {
        await run { client in
            let change: Change = try await client.call(.remove(node: peer.nodeId))
            self.notice = AppModel.describe(change, name: peer.name)
            await self.loadPeers()
        }
    }

    func vote(_ proposal: Proposal, approve: Bool) async {
        await run { client in
            let change: Change = try await client.call(
                approve ? .approve(proposal: proposal.id) : .reject(proposal: proposal.id))
            self.notice = AppModel.describe(change, name: proposal.name)
            await self.refresh()
        }
    }

    /// Asks before leaving the network, or cancelling a join. If a step of
    /// leaving fails, offers to leave anyway.
    func confirmLeave(cancelJoin: Bool) {
        let ask = NSAlert()
        if cancelJoin {
            ask.messageText = "Cancel the join?"
            ask.informativeText =
                "This cancels the join on this Mac only. A member may still need to reject the request."
            ask.addButton(withTitle: "Cancel Join")
            ask.addButton(withTitle: "Keep Waiting")
        } else {
            ask.messageText = "Leave the network?"
            ask.informativeText =
                "This Mac leaves the network and removes its WireGuard interface. To come back, it needs a new invite."
            ask.addButton(withTitle: "Leave")
            ask.addButton(withTitle: "Cancel")
        }
        ask.buttons[0].hasDestructiveAction = true
        guard AppModel.confirm(ask) else { return }
        Task {
            await leave(force: false)
            guard !cancelJoin, let error else { return }
            let retry = NSAlert()
            retry.messageText = "A step of leaving failed."
            retry.informativeText =
                "\(error)\n\nLeave anyway? The other members may then need repair."
            retry.addButton(withTitle: "Leave Anyway")
            retry.addButton(withTitle: "Cancel")
            retry.buttons[0].hasDestructiveAction = true
            if AppModel.confirm(retry) {
                await leave(force: true)
            }
        }
    }

    /// Asks before removing `peer`.
    func confirmRemove(_ peer: Peer) {
        let ask = NSAlert()
        ask.messageText = "Remove \(peer.name) from the network?"
        ask.informativeText = "Node ID \(peer.nodeId)"
        ask.addButton(withTitle: "Remove")
        ask.addButton(withTitle: "Cancel")
        ask.buttons[0].hasDestructiveAction = true
        guard AppModel.confirm(ask) else { return }
        Task { await remove(peer) }
    }

    /// Shows `alert` above the menu windows, and says if its first button
    /// was chosen.
    static func confirm(_ alert: NSAlert) -> Bool {
        NSApp.activate()
        alert.window.level = NSWindow.Level(NSWindow.Level.popUpMenu.rawValue + 1)
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func describe(_ change: Change, name: String?) -> String {
        let who = name ?? "the node"
        return switch change {
        case .pending: "Waiting for approvals from other members."
        case let .approved(_, remaining): "Approved. \(remaining) more approval(s) needed."
        case .rejected: "Rejected."
        case .joined: "Approved: \(who) joined."
        case .removed: "Removed \(who)."
        case .settingChanged: "Setting changed."
        }
    }

    /// Runs an action, and keeps its error for the page to show.
    private func run(_ action: @MainActor (Client) async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await action(client)
        } catch {
            self.error = String(describing: error)
        }
    }

    func openSettings() {
        daemon.openSettings()
    }

    func openLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Library/Logs/cheesecloth.log"))
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notice = "Copied."
    }

    /// Stops the daemon, then quits. A logout or shutdown quits the app
    /// without coming here, so the daemon then starts again at boot.
    func quit() {
        let before = state
        state = .quitting
        error = nil
        Task {
            do {
                try await daemon.unregister()
                NSApp.terminate(nil)
            } catch {
                // Stay open, so the user knows the daemon still runs.
                self.state = before
                self.error = "Can't stop the daemon: \(error.localizedDescription)"
            }
        }
    }
}
