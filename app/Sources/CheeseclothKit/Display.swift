// What the app shows for the daemon's answers: the menu header's state, the
// badges of the status panel, and the values of the peers table. The design
// brief (mockups/macos-brief.md) lists them.

import Foundation

/// The four colours of dots and badges.
public enum Level: Sendable, Equatable {
    /// Green.
    case good
    /// Orange: needs a look.
    case attention
    /// Red.
    case broken
    /// Grey: off, or no data.
    case off
    /// Grey-blue: a fact that may look worrying but is a choice, such as
    /// relaxed security.
    case info
}

/// A short label with a colour.
public struct Badge: Sendable, Equatable {
    public var text: String
    public var level: Level

    public init(_ text: String, _ level: Level) {
        self.text = text
        self.level = level
    }
}

/// How launchd holds the daemon (`SMAppService.Status`), or `unmanaged`
/// when the app runs outside its bundle and someone else runs the daemon.
public enum Registration: Sendable, Equatable {
    case notRegistered
    case requiresApproval
    case enabled
    case unmanaged
}

/// The menu header's state.
public enum MenuState: Sendable, Equatable {
    case allowInSettings
    case starting
    case notResponding(String)
    case administratorsOnly(String)
    case needsReinstall(String)
    case noNetwork(Status)
    case waitingForApproval(Status)
    case leaving(Status)
    case connected(Status)
    case quitting

    /// A daemon that does not answer this long after it was started is
    /// "not responding", not "starting".
    public static let startTime: TimeInterval = 15

    /// The state, from launchd's hold on the daemon, the answer to
    /// `status`, and the time since the app registered the daemon.
    public init(
        registration: Registration, status: Result<Status, APIError>,
        sinceRegistered: TimeInterval?
    ) {
        if registration == .requiresApproval || registration == .notRegistered {
            self = .allowInSettings
            return
        }
        switch status {
        case let .success(s):
            switch s.phase {
            case .none: self = .noNetwork(s)
            case .pending: self = .waitingForApproval(s)
            case .stopping: self = .leaving(s)
            case .member: self = .connected(s)
            }
        case let .failure(.refused(text)): self = .administratorsOnly(text)
        case let .failure(error) where error.isVersion:
            self = .needsReinstall(error.description)
        case let .failure(.unreachable(why)):
            if let since = sinceRegistered, since < MenuState.startTime {
                self = .starting
            } else {
                self = .notResponding(why)
            }
        case let .failure(error): self = .notResponding(error.description)
        }
    }

    public var title: String {
        switch self {
        case .allowInSettings: "Allow in System Settings"
        case .starting: "Starting…"
        case .notResponding: "Not responding"
        case .administratorsOnly: "Administrators only"
        case .needsReinstall: "Needs reinstall"
        case .noNetwork: "Not in a network"
        case .waitingForApproval: "Waiting for approval"
        case .leaving: "Leaving"
        case let .connected(s): s.warnings.isEmpty ? "Connected" : "Connected, with warnings"
        case .quitting: "Quitting…"
        }
    }

    public var level: Level {
        switch self {
        case .starting, .noNetwork, .quitting: .off
        case .allowInSettings, .waitingForApproval, .leaving: .attention
        case .notResponding, .administratorsOnly, .needsReinstall: .broken
        case let .connected(s): s.warnings.isEmpty ? .good : .attention
        }
    }

    /// The line under the title.
    public var detail: String? {
        switch self {
        case let .connected(s):
            let members = "\(s.members) member\(s.members == 1 ? "" : "s")"
            let warnings = s.warnings.count
            return warnings == 0
                ? "\(s.name) • \(members)"
                : "\(s.name) • \(warnings) warning\(warnings == 1 ? "" : "s")"
        case let .noNetwork(s): return s.name
        case let .waitingForApproval(s): return s.name
        case let .leaving(s): return s.warnings.first
        case let .notResponding(why): return why
        case let .administratorsOnly(text): return text
        case let .needsReinstall(text): return text
        case .allowInSettings, .starting, .quitting: return nil
        }
    }
}

extension APIError {
    var isVersion: Bool {
        if case .version = self { true } else { false }
    }
}

extension Status {
    /// Overview: Healthy, N warnings, or Leaving.
    public var overviewBadge: Badge {
        if phase == .stopping { return Badge("Leaving", .attention) }
        let n = warnings.count
        return n == 0 ? Badge("Healthy", .good) : Badge("\(n) warning\(n == 1 ? "" : "s")", .attention)
    }

    /// Network: Public or Behind NAT.
    public var networkBadge: Badge {
        `public` ? Badge("Public", .good) : Badge("Behind NAT", .off)
    }

    /// Network: Relay, when this node relays for others.
    public var relayBadge: Badge? {
        relay ? Badge("Relay", .off) : nil
    }

    /// Consensus: Available, or Changes paused.
    public var consensusBadge: Badge {
        changesPaused ? Badge("Changes paused", .attention) : Badge("Available", .good)
    }

    /// Security: Protected or Relaxed; none when not a member. Relaxed is
    /// not a problem: small networks choose it.
    public var securityBadge: Badge? {
        switch security {
        case "protected": Badge("Protected", .good)
        case "relaxed": Badge("Relaxed", .info)
        default: nil
        }
    }

    /// "behind NAT, keepalive 25s", "public, keepalive off".
    public var networkConditions: String {
        let place = `public` ? "public" : "behind NAT"
        let keepalive = keepalive == 0 ? "keepalive off" : "keepalive \(keepalive)s"
        return "\(place), \(keepalive)"
    }

    /// "userspace on utun7, port 51820".
    public var wireGuardSummary: String {
        let backend = wgBackend.map { "\($0) on \(wgInterface)" } ?? "no interface"
        return "\(backend), port \(wgPort)"
    }

    /// The port mapping badge of `port` ("wireguard" or "control").
    public func portBadge(_ port: String) -> Badge {
        guard let maps = portMapping else { return Badge("Off", .off) }
        guard let map = maps.first(where: { $0.port == port }) else { return Badge("Off", .off) }
        return map.badge
    }

    /// The level of both port mappings together: the one that most needs a
    /// look.
    public var connectivityLevel: Level {
        let levels = ["wireguard", "control"].map { portBadge($0).level }
        for level in [Level.broken, .attention, .good] where levels.contains(level) {
            return level
        }
        return .off
    }
}

extension PortMap {
    /// Mapped, Not mapped, or Requesting.
    public var badge: Badge {
        if mapped != nil { return Badge("Mapped", .good) }
        if error != nil { return Badge("Not mapped", .attention) }
        return Badge("Requesting", .off)
    }
}

extension Peer {
    /// The dot: reached or not.
    public var presence: Level { present ? .good : .off }

    /// "member" or "relay".
    public var role: String { relay ? "relay" : "member" }

    /// The control connection: yes, relay (reached through other members),
    /// or no.
    public var control: Badge {
        if connected { return Badge("yes", .good) }
        if present { return Badge("relay", .off) }
        return Badge("no", .off)
    }

    /// The colour of `pathState`. The daemon's text is for people; only
    /// "up" has a fixed meaning, so the others are grouped by their words.
    public var stateLevel: Level? {
        if thisNode { return nil }
        switch pathState {
        case "up": return .good
        case "stale", "no handshake yet", "waiting to punch", "offer sent", "punching":
            return .attention
        case let s where s.hasPrefix("no path"): return .broken
        default: return .off
        }
    }

    /// "16s ago", "2m ago", "3h ago", or "-".
    public var handshakeText: String {
        guard let age = handshakeAgeSecs else { return "-" }
        return Peer.ago(age)
    }

    static func ago(_ secs: Int) -> String {
        switch secs {
        case ..<90: "\(secs)s ago"
        case ..<(90 * 60): "\(secs / 60)m ago"
        case ..<(36 * 3600): "\(secs / 3600)h ago"
        default: "\(secs / 86400)d ago"
        }
    }
}

/// "74b239929045…a567": the start and end of a long ID.
public func shortID(_ id: String) -> String {
    guard id.count > 16 else { return id }
    return "\(id.prefix(12))…\(id.suffix(4))"
}
