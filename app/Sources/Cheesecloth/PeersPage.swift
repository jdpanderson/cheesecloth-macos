// The peers panel (mockups/macos-peers.png).

import CheeseclothKit
import SwiftUI

struct PeersPage: View {
    @Environment(AppModel.self) private var model
    @Environment(Panels.self) private var panels

    /// Only an admin may invite or remove, so other members get neither.
    private var isAdmin: Bool {
        model.peers.first { $0.thisNode }?.permissions.admin == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(model.peers.count) members").foregroundStyle(.secondary)
                Spacer()
                if isAdmin {
                    Button("Invite a new member", systemImage: "plus") { panels.show(.invite) }
                        .labelStyle(.iconOnly)
                        .help("Invite a new member")
                }
            }
            Messages()
            if model.peers.count == 1 {
                Text("No other members yet.").foregroundStyle(.secondary)
            }
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        ForEach(
                            ["", "NAME", "IPV4", "ROLE", "PERMISSIONS", "CONTROL", "PATH", "STATE", "ENDPOINT", "HANDSHAKE", ""],
                            id: \.self
                        ) { Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                    }
                    Divider()
                    ForEach(model.peers) { row($0) }
                }
            }
            .frame(maxHeight: 480)
        }
        .frame(width: 920)
        .task { await model.loadPeers() }
    }

    private func row(_ peer: Peer) -> some View {
        GridRow {
            Dot(level: peer.presence).help(peer.presenceTooltip)
            Text(peer.thisNode ? "\(peer.name) (this)" : peer.name)
                .foregroundStyle(peer.thisNode ? Color.accentColor : .primary)
                .lineLimit(1)
            Text(peer.ipv4).monospacedDigit()
            Icons(icons: peer.roleIcons)
            Icons(icons: peer.permissions.icons)
            if peer.thisNode {
                Text("")
            } else {
                Chip(text: peer.control.text, level: peer.control.level).help(peer.controlTooltip)
            }
            Chip(text: peer.path)
            if let level = peer.stateLevel {
                Dot(level: level)
                    .help(peer.stateTooltip)
                    .accessibilityLabel(peer.stateTooltip)
            } else {
                Text("-")
            }
            Text(peer.wgEndpoint ?? "-").monospacedDigit()
            Text(peer.handshakeText)
            Menu {
                Button("Copy IP") { model.copy(peer.ipv4) }
                Button("Copy Name") { model.copy(peer.name) }
                if isAdmin && !peer.thisNode {
                    Divider()
                    Button("Remove…") { model.confirmRemove(peer) }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

/// A row of icons. Each has a tooltip that names it and says what it means.
struct Icons: View {
    var icons: [PeerIcon]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(icons, id: \.symbol) { icon in
                Image(systemName: icon.symbol)
                    .foregroundStyle(icon.dim ? Color.secondary : .primary)
                    .help(icon.tooltip)
                    .accessibilityLabel(icon.tooltip)
            }
        }
    }
}

/// A small rounded label.
struct Chip: View {
    var text: String
    var level: Level? = nil

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background((level?.color ?? .secondary).opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
    }
}
