// The local API's messages, as cheesecloth's docs/LOCAL-API.md describes
// them. JSON keys are snake case; `decoder` and `encoder` convert them.

import Foundation

/// The API version this app speaks. See "Versions" in LOCAL-API.md.
public let apiVersion = 1

/// A request to the daemon.
public enum Request: Sendable, Equatable {
    case hello
    case status
    case peers
    case initialize(ipv4Range: String?, strictSecurity: Bool)
    /// The new member gets only the permissions that are true.
    case invite(permissions: Permissions)
    case join(token: String)
    case remove(node: String)
    case leave(force: Bool)
    case pending
    case approve(proposal: String)
    case reject(proposal: String)
    case configGet

    /// The request as one JSON object.
    var json: [String: Any] {
        switch self {
        case .hello: ["cmd": "hello"]
        case .status: ["cmd": "status"]
        case .peers: ["cmd": "peers"]
        case let .initialize(range, strict):
            ["cmd": "init", "strict_security": strict, "ipv4_range": range ?? NSNull()]
        case let .invite(p):
            ["cmd": "invite", "permissions": ["admin": p.admin, "vote": p.vote, "relay": p.relay]]
        case let .join(token): ["cmd": "join", "token": token]
        case let .remove(node): ["cmd": "remove", "node": node]
        case let .leave(force): ["cmd": "leave", "force": force]
        case .pending: ["cmd": "pending"]
        case let .approve(proposal): ["cmd": "approve", "proposal": proposal]
        case let .reject(proposal): ["cmd": "reject", "proposal": proposal]
        case .configGet: ["cmd": "config_get"]
        }
    }

    /// The request as one line, without its newline.
    public func line() throws -> Data {
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }
}

/// What a member may do, set by its invite. It never changes.
public struct Permissions: Codable, Sendable, Equatable {
    /// Invite, remove, change settings, approve and reject.
    public var admin: Bool
    /// Be an acceptor, and take joins to the cluster.
    public var vote: Bool
    /// Relay control messages for other members.
    public var relay: Bool

    public init(admin: Bool, vote: Bool, relay: Bool) {
        self.admin = admin
        self.vote = vote
        self.relay = relay
    }

    public static let all = Permissions(admin: true, vote: true, relay: true)
}

/// The answer to `hello`.
public struct Hello: Codable, Sendable, Equatable {
    public var api: Int
    public var daemon: String
}

/// The answer to `status`.
public struct Status: Codable, Sendable, Equatable {
    public var security: String
    public var quorum: Int
    public var reachableVoters: Int
    public var changesPaused: Bool
    public var strictSecurity: Bool
    public var bufferNodes: Int
    public var nodeId: String
    public var name: String
    public var phase: Phase
    public var clusterId: String?
    public var pendingProposal: String?
    public var ipv4: String?
    public var ipv6: String?
    /// What this node may do; nil unless a member.
    public var permissions: Permissions?
    public var relay: Bool
    public var `public`: Bool
    public var keepalive: Int
    public var acceptors: [String]
    public var config: Int?
    public var version: Int?
    public var members: Int
    public var controlAddr: String?
    public var wgBackend: String?
    public var wgInterface: String
    public var wgPort: Int
    public var portMapping: [PortMap]?
    public var warnings: [String]

    public enum Phase: String, Codable, Sendable {
        case none, pending, member, stopping
    }
}

/// The router port mapping of one local port.
public struct PortMap: Codable, Sendable, Equatable {
    /// "wireguard" or "control".
    public var port: String
    public var localPort: Int
    public var mapped: Grant?
    public var error: String?

    public struct Grant: Codable, Sendable, Equatable {
        public var external: String
        /// "UPnP", "PCP" or "NAT-PMP".
        public var method: String
    }
}

/// One member, from `peers`.
public struct Peer: Codable, Sendable, Equatable, Identifiable {
    public var nodeId: String
    public var name: String
    public var ipv4: String
    public var ipv6: String?
    public var permissions: Permissions
    public var relay: Bool
    public var acceptor: Bool
    public var thisNode: Bool
    public var connected: Bool
    public var present: Bool
    public var wgKey: String
    public var path: String
    public var pathState: String
    public var pathDetail: String
    public var retryInSecs: Int?
    public var wgEndpoint: String?
    public var handshakeAgeSecs: Int?

    public var id: String { nodeId }
}

/// The answer to `init`.
public struct Created: Codable, Sendable, Equatable {
    public var clusterId: String
    public var ipv4Range: String
}

/// The answer to `invite`.
public struct Invite: Codable, Sendable, Equatable {
    public var token: String
    public var expiresAtMs: Int64

    public var expiresAt: Date { Date(timeIntervalSince1970: Double(expiresAtMs) / 1000) }
}

/// The answer to `join`: joined, or waiting for approvals.
public struct Joined: Codable, Sendable, Equatable {
    public var joined: Bool
    public var clusterId: String?
    public var ipv4: String?
    public var proposal: String?
    public var nodeId: String?
}

/// The answer to `leave`.
public enum Left: Codable, Sendable, Equatable {
    case left(remainingMembers: Int, problems: [String])
    case joinCancelled(clusterId: String, proposal: String)

    private enum Keys: String, CodingKey {
        case outcome, remainingMembers, problems, clusterId, proposal
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .outcome) {
        case "left":
            self = try .left(
                remainingMembers: c.decode(Int.self, forKey: .remainingMembers),
                problems: c.decode([String].self, forKey: .problems))
        case "join_cancelled":
            self = try .joinCancelled(
                clusterId: c.decode(String.self, forKey: .clusterId),
                proposal: c.decode(String.self, forKey: .proposal))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .outcome, in: c, debugDescription: "unknown outcome \(other)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .left(remaining, problems):
            try c.encode("left", forKey: .outcome)
            try c.encode(remaining, forKey: .remainingMembers)
            try c.encode(problems, forKey: .problems)
        case let .joinCancelled(cluster, proposal):
            try c.encode("join_cancelled", forKey: .outcome)
            try c.encode(cluster, forKey: .clusterId)
            try c.encode(proposal, forKey: .proposal)
        }
    }
}

/// The answer to `remove`, `approve`, `reject` and `config_set`.
public enum Change: Codable, Sendable, Equatable {
    case pending(proposal: String)
    case approved(proposal: String, remaining: Int)
    case rejected(proposal: String)
    case joined(node: String, ipv4: String)
    case removed(node: String)
    case settingChanged

    private enum Keys: String, CodingKey {
        case outcome, proposal, remaining, node, ipv4
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .outcome) {
        case "pending": self = try .pending(proposal: c.decode(String.self, forKey: .proposal))
        case "approved":
            self = try .approved(
                proposal: c.decode(String.self, forKey: .proposal),
                remaining: c.decode(Int.self, forKey: .remaining))
        case "rejected": self = try .rejected(proposal: c.decode(String.self, forKey: .proposal))
        case "joined":
            self = try .joined(
                node: c.decode(String.self, forKey: .node),
                ipv4: c.decode(String.self, forKey: .ipv4))
        case "removed": self = try .removed(node: c.decode(String.self, forKey: .node))
        case "setting_changed": self = .settingChanged
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .outcome, in: c, debugDescription: "unknown outcome \(other)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .pending(proposal):
            try c.encode("pending", forKey: .outcome)
            try c.encode(proposal, forKey: .proposal)
        case let .approved(proposal, remaining):
            try c.encode("approved", forKey: .outcome)
            try c.encode(proposal, forKey: .proposal)
            try c.encode(remaining, forKey: .remaining)
        case let .rejected(proposal):
            try c.encode("rejected", forKey: .outcome)
            try c.encode(proposal, forKey: .proposal)
        case let .joined(node, ipv4):
            try c.encode("joined", forKey: .outcome)
            try c.encode(node, forKey: .node)
            try c.encode(ipv4, forKey: .ipv4)
        case let .removed(node):
            try c.encode("removed", forKey: .outcome)
            try c.encode(node, forKey: .node)
        case .settingChanged:
            try c.encode("setting_changed", forKey: .outcome)
        }
    }
}

/// One proposal waiting for approvals, from `pending`.
public struct Proposal: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// "join", "remove" or "setting".
    public var kind: String
    public var node: String?
    public var name: String?
    /// For a join, the new member's permissions; nil for other kinds.
    public var permissions: Permissions?
    public var setting: Setting?
    public var proposer: String
    public var approvals: [String]
    public var needed: Int
    public var expiresInSecs: Int

    public struct Setting: Codable, Sendable, Equatable {
        public var key: String
        public var value: String
    }
}

/// The answer to `config_get`.
public struct Config: Codable, Sendable, Equatable {
    public var approvalsRequired: Int
    public var acceptors: Int
    public var strictSecurity: Bool
    public var bufferNodes: Int
    public var catchUpDays: Int
    public var ipv4Range: String
    public var ipv6Prefix: String
}

/// Reads the daemon's JSON: snake case keys.
public let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}()

/// Writes JSON as the daemon does, for tests that compare.
public let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.keyEncodingStrategy = .convertToSnakeCase
    return e
}()
