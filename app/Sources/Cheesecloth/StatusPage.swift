// The status window (mockups/macos-status.png), laid out as System Settings
// is: a sidebar of sections, each with a dot for its health, and the chosen
// section beside it.

import CheeseclothKit
import SwiftUI

struct StatusPage: View {
    @Environment(AppModel.self) private var model
    @State private var selection: StatusSection = .overview

    var body: some View {
        NavigationSplitView {
            List(sections, selection: $selection) { section in
                HStack {
                    Label(section.title, systemImage: section.symbol)
                    Spacer()
                    if let level = status.flatMap(section.level) { Dot(level: level) }
                }
            }
            .navigationSplitViewColumnWidth(StatusPage.sidebarWidth)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Form {
                if model.error != nil || model.notice != nil {
                    Section { Messages() }
                }
                if let status { detail(status) }
            }
            .formStyle(.grouped)
        }
        .frame(width: StatusPage.size.width, height: StatusPage.size.height)
        // A section that goes away, such as Network when the node leaves,
        // gives way to the overview.
        .onChange(of: sections) { if !sections.contains(selection) { selection = .overview } }
        // Fresh every few seconds while the window is open. The task ends
        // when the window closes.
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: StatusPage.interval)
            }
        }
    }

    static let interval: Duration = .seconds(5)
    /// One size for every section, so the window does not jump when the
    /// selection changes.
    static let size = CGSize(width: 640, height: 420)
    static let sidebarWidth: CGFloat = 180

    private var status: Status? {
        switch model.state {
        case let .connected(s), let .noNetwork(s), let .waitingForApproval(s), let .leaving(s): s
        default: nil
        }
    }

    /// Only a member has more than an overview.
    private var sections: [StatusSection] {
        status?.phase == .member ? StatusSection.allCases : [.overview]
    }

    @ViewBuilder private func detail(_ s: Status) -> some View {
        switch selection {
        case .overview:
            if !s.warnings.isEmpty {
                Section {
                    ForEach(s.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Section {
                if let badge = StatusSection.overview.badge(s) { badgeRow(badge) }
                row("Node", s.name)
                row("Node ID", shortID(s.nodeId))
                if let cluster = s.clusterId { row("Network ID", shortID(cluster)) }
                if s.phase == .member { row("Members", "\(s.members)") }
                if s.phase == .pending { row("Join", "waiting for approval") }
            }
        case .network:
            Section {
                badgeRow(s.networkBadge, s.relayBadge)
                if let ipv4 = s.ipv4 { row("Overlay IPv4", ipv4) }
                if let ipv6 = s.ipv6 { row("Overlay IPv6", ipv6) }
                row("Network conditions", s.networkConditions)
            }
            // Only a member has this section, so only a member can leave.
            Section {
                HStack {
                    Spacer()
                    // Asks first (`confirmLeave`).
                    Button("Leave Network…", role: .destructive) {
                        model.confirmLeave(cancelJoin: false)
                    }
                    .disabled(model.busy)
                }
            }
        case .consensus:
            Section {
                badgeRow(s.consensusBadge, help: Help.consensus)
                if let version = s.version { row("State version", "\(version)", help: Help.version) }
                row("Acceptors", "\(s.acceptors.count)", help: Help.acceptors)
                if let config = s.config { row("Configuration", "\(config)", help: Help.config) }
            }
        case .security:
            Section {
                if let badge = s.securityBadge { badgeRow(badge, help: Help.security) }
                row("Quorum", "\(s.quorum)", help: Help.quorum)
                row("Reachable", "\(s.reachableVoters)", help: Help.reachable)
                row("Strict mode", s.strictSecurity ? "on" : "off", help: Help.strict)
                row("Buffer", "\(s.bufferNodes)", help: Help.buffer)
            }
        case .connectivity:
            Section {
                port("WireGuard", s.wireGuardSummary, s.portBadge("wireguard"), s.portMap("wireguard"))
                port("Control", s.controlAddr ?? "-", s.portBadge("control"), s.portMap("control"))
            } footer: {
                Text("The badge is the router's port mapping.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ label: String, _ value: String, help: String? = nil) -> some View {
        LabeledContent {
            Text(value).textSelection(.enabled)
        } label: {
            title(label, help: help)
        }
    }

    private func badgeRow(_ badge: Badge, _ extra: Badge? = nil, help: String? = nil) -> some View {
        LabeledContent {
            HStack {
                if let extra { BadgeView(badge: extra) }
                BadgeView(badge: badge)
            }
        } label: {
            title("Status", help: help)
        }
    }

    /// A row's title, with an (i) that explains it.
    @ViewBuilder private func title(_ label: String, help: String?) -> some View {
        if let help {
            HStack(spacing: 4) {
                Text(label)
                InfoButton(text: help)
            }
        } else {
            Text(label)
        }
    }

    private func port(_ label: String, _ value: String, _ badge: Badge, _ map: PortMap?) -> some View {
        LabeledContent(label) {
            HStack {
                Text(value).textSelection(.enabled)
                BadgeView(badge: badge).help(map.map(portHelp) ?? "Port mapping is off")
            }
        }
    }

    private func portHelp(_ map: PortMap) -> String {
        if let grant = map.mapped { return "\(grant.external) by \(grant.method)" }
        return map.error ?? "Asking the router"
    }
}

/// An (i) that shows `text` as a tooltip under the pointer, and in a
/// popover when clicked.
private struct InfoButton: View {
    var text: String
    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(text)
        .accessibilityLabel(text)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(12)
        }
    }
}

/// What the consensus and security rows mean, for their (i) tooltips. From
/// cheesecloth's docs/CONSENSUS-SAFETY.md.
private enum Help {
    static let consensus = """
        Available: enough acceptors can be reached to agree on changes.
        Changes paused: too few can be reached, so joins, removals and setting \
        changes wait. Traffic between members keeps flowing.
        """
    static let version =
        "The version of the network's agreed state (members and settings) that this Mac holds. It goes up with each change."
    static let acceptors =
        "The members that vote on changes and keep the agreed state. There are at most 7."
    static let config =
        "The number of the current group of acceptors. It goes up each time the group changes."
    static let security = """
        Protected: changes stay safe even if one acceptor is compromised and lies. \
        It needs at least 4 acceptors.
        Relaxed: changes are safe only while every acceptor is honest. This is \
        normal for small networks.
        """
    static let quorum = "The number of acceptor votes needed to agree on a change."
    static let reachable =
        "The acceptors this Mac can reach now. When fewer than the quorum can be reached, changes pause."
    static let strict =
        "When on, a protected network does not fall back to relaxed when acceptors go away. It pauses changes instead."
    static let buffer =
        "How many acceptors may be unreachable while changes still go through. A larger buffer needs more acceptors before protection starts."
}

/// A section of the status window's sidebar.
enum StatusSection: CaseIterable, Identifiable {
    case overview, network, consensus, security, connectivity

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .network: "Network"
        case .consensus: "Consensus"
        case .security: "Security"
        case .connectivity: "Connectivity"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "desktopcomputer"
        case .network: "globe"
        case .consensus: "square.3.layers.3d"
        case .security: "shield"
        case .connectivity: "arrow.left.arrow.right"
        }
    }

    /// The section's badge, at the top of the section. A node that is not a
    /// member has none.
    func badge(_ s: Status) -> Badge? {
        switch self {
        case .overview: s.phase == .member || s.phase == .stopping ? s.overviewBadge : nil
        case .network: s.networkBadge
        case .consensus: s.consensusBadge
        case .security: s.securityBadge
        case .connectivity: nil
        }
    }

    /// The colour of the section's dot in the sidebar, or nil for none.
    func level(_ s: Status) -> Level? {
        self == .connectivity ? s.connectivityLevel : badge(s)?.level
    }
}

extension Status {
    func portMap(_ port: String) -> PortMap? {
        portMapping?.first { $0.port == port }
    }
}
