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
    #expect(peer.stateLevel == .good)
    #expect(peer.handshakeText == "16s ago")
    peer.connected = false
    #expect(peer.control == Badge("relay", .off))
    peer.present = false
    #expect(peer.control == Badge("no", .off))
    #expect(peer.presence == .off)
    peer.pathState = "no path; retry in 20s"
    #expect(peer.stateLevel == .broken)
    peer.pathState = "punching"
    #expect(peer.stateLevel == .attention)
    peer.handshakeAgeSecs = 150
    #expect(peer.handshakeText == "2m ago")
    peer.thisNode = true
    #expect(peer.stateLevel == nil)
}

@Test func longIDsAreShortened() {
    #expect(shortID("74b239929045c3f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f7a567") == "74b239929045…a567")
    #expect(shortID("short") == "short")
}
