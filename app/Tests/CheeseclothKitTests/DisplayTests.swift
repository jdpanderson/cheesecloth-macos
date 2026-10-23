// What the app shows for each answer (mockups/macos-brief.md).

import Foundation
import Testing

@testable import CheeseclothKit

/// The status example from LOCAL-API.md, changed by `edit`.
func status(_ edit: (inout Status) -> Void = { _ in }) throws -> Status {
    let json = try #require(try examples().first { $0.kind == "status" }?.json)
    var s = try decoder.decode(Status.self, from: Data(json.utf8))
    edit(&s)
    return s
}

@Test func theMenuStateFollowsThePhase() throws {
    func state(_ phase: Status.Phase) throws -> MenuState {
        MenuState(
            registration: .enabled, status: .success(try status { $0.phase = phase }),
            sinceRegistered: nil)
    }
    #expect(try state(.member).title == "Connected")
    #expect(try state(.member).level == .good)
    #expect(try state(.none).title == "Not in a network")
    #expect(try state(.pending).title == "Waiting for approval")
    #expect(try state(.stopping).title == "Leaving")
    let warned = MenuState(
        registration: .enabled,
        status: .success(try status { $0.warnings = ["Current quorum unavailable; changes paused"] }),
        sinceRegistered: nil)
    #expect(warned.level == .attention)
    #expect(warned.detail == "artemis.local • 1 warning")
}

@Test func theMenuStateExplainsAnUnreachableDaemon() {
    let unreachable = Result<Status, APIError>.failure(.unreachable("no such file"))
    #expect(
        MenuState(registration: .requiresApproval, status: unreachable, sinceRegistered: nil)
            == .allowInSettings)
    #expect(MenuState(registration: .enabled, status: unreachable, sinceRegistered: 2) == .starting)
    #expect(
        MenuState(registration: .enabled, status: unreachable, sinceRegistered: 60)
            == .notResponding("no such file"))
    #expect(
        MenuState(registration: .unmanaged, status: unreachable, sinceRegistered: nil)
            == .notResponding("no such file"))
    #expect(
        MenuState(registration: .enabled, status: .failure(.refused("only root")), sinceRegistered: nil)
            == .administratorsOnly("only root"))
    let version = MenuState(
        registration: .enabled, status: .failure(.version(daemon: "9.0.0", api: 2)),
        sinceRegistered: nil)
    #expect(version.title == "Needs reinstall")
    let legacy = MenuState(
        registration: .enabled, status: .failure(.legacyVersion), sinceRegistered: nil)
    #expect(legacy.title == "Needs reinstall")
}

@Test func theStatusBadgesFollowTheBrief() throws {
    let s = try status()
    #expect(s.overviewBadge == Badge("Healthy", .good))
    #expect(s.networkBadge == Badge("Behind NAT", .off))
    #expect(s.relayBadge == nil)
    #expect(s.consensusBadge == Badge("Available", .good))
    #expect(s.securityBadge == Badge("Protected", .good))
    #expect(s.networkConditions == "behind NAT, keepalive 25s")
    #expect(s.wireGuardSummary == "userspace on utun7, port 51820")
    #expect(s.portBadge("wireguard") == Badge("Mapped", .good))
    #expect(s.portBadge("control") == Badge("Not mapped", .attention))
    #expect(s.connectivityLevel == .attention)
    let off = try status { $0.portMapping = nil; $0.changesPaused = true; $0.security = "relaxed" }
    #expect(off.portBadge("wireguard") == Badge("Off", .off))
    #expect(off.connectivityLevel == .off)
    #expect(off.consensusBadge == Badge("Changes paused", .attention))
    #expect(off.securityBadge == Badge("Relaxed", .info))
    let asking = PortMap(port: "control", localPort: 51821, mapped: nil, error: nil)
    #expect(asking.badge == Badge("Requesting", .off))
}

@Test func thePeerColumnsFollowTheBrief() throws {
    let json = try #require(try examples().first { $0.kind == "peers" }?.json)
    var peer = try #require(try decoder.decode([Peer].self, from: Data(json.utf8)).first)
    #expect(peer.control == Badge("yes", .good))
    #expect(peer.controlTooltip == "Connected directly.")
    #expect(peer.presenceTooltip == "Present: reached now")
    #expect(peer.stateLevel == .good)
    #expect(peer.pathDetail == "up")
    #expect(peer.stateTooltip == "Up\nWireGuard had a recent handshake with this member, so traffic flows.")
    #expect(peer.retryInSecs == nil)
    #expect(peer.handshakeText == "16s ago")
    peer.connected = false
    #expect(peer.control == Badge("relay", .off))
    #expect(peer.controlTooltip == "Reached through other members.")
    peer.present = false
    #expect(peer.control == Badge("no", .off))
    #expect(peer.controlTooltip == "Not reached now.")
    #expect(peer.presence == .off)
    #expect(peer.presenceTooltip == "Not present: not reached now")
    peer.pathState = "no_path"
    peer.pathDetail = "no path; retry in 20s"
    peer.retryInSecs = 20
    #expect(peer.stateLevel == .broken)
    #expect(peer.pathDetail == "no path; retry in 20s")
    #expect(peer.retryInSecs == 20)
    #expect(peer.stateTooltip.hasPrefix("No path; retry in 20s\nNAT hole punching failed"))
    peer.pathState = "punching"
    #expect(peer.stateLevel == .attention)
    peer.pathState = "no_handshake"
    #expect(peer.stateLevel == .attention)
    peer.pathState = "not_configured"
    #expect(peer.stateLevel == .attention)
    // A state from a newer daemon has no meaning here, so only its detail shows.
    peer.pathState = "new_state"
    peer.pathDetail = "new state"
    #expect(peer.stateLevel == .off)
    #expect(peer.stateTooltip == "New state")
    peer.handshakeAgeSecs = 150
    #expect(peer.handshakeText == "2m ago")
    peer.thisNode = true
    #expect(peer.stateLevel == nil)
}

@Test func onlyAnAdminMayChangeTheNetwork() throws {
    let member = try status()
    #expect(member.isAdmin)
    let router = try status { $0.permissions = Permissions(admin: false, vote: true, relay: true) }
    #expect(!router.isAdmin)
    let outside = try status { $0.phase = .none; $0.permissions = nil }
    #expect(!outside.isAdmin)
}

@Test func permissionsAreNamedForPeople() throws {
    #expect(Permissions.all.names == "All")
    #expect(Permissions(admin: false, vote: true, relay: true).names == "Voter, Relay")
    #expect(Permissions(admin: true, vote: false, relay: true).names == "Admin, Relay")
    #expect(Permissions(admin: true, vote: false, relay: false).names == "Admin")
    #expect(Permissions(admin: false, vote: false, relay: false).names == "Member")

    let json = try #require(try examples().first { $0.kind == "peers" }?.json)
    let peer = try #require(try decoder.decode([Peer].self, from: Data(json.utf8)).first)
    #expect(peer.permissions.names == "Voter, Relay")
}

@Test func rolesAndPermissionsAreIcons() throws {
    let json = try #require(try examples().first { $0.kind == "peers" }?.json)
    var peer = try #require(try decoder.decode([Peer].self, from: Data(json.utf8)).first)
    peer.acceptor = true
    peer.relay = true
    #expect(peer.roleIcons.map(\.tooltip) == [
        "Acceptor: votes on changes now", "Relay: relays messages for other members now",
    ])
    peer.acceptor = false
    peer.relay = false
    #expect(peer.roleIcons == [PeerIcon("person", "Member: no other role now", dim: true)])

    #expect(Permissions.all.icons.map(\.symbol) == ["shield", "checkmark", "arrow.left.arrow.right"])
    #expect(Permissions.all.icons.allSatisfy { !$0.dim })
    #expect(Permissions(admin: false, vote: false, relay: false).icons == [
        PeerIcon("person", "Member: may use the network and leave", dim: true)
    ])
}

@Test func longIDsAreShortened() {
    #expect(shortID("74b239929045c3f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f7a567") == "74b239929045…a567")
    #expect(shortID("short") == "short")
}
