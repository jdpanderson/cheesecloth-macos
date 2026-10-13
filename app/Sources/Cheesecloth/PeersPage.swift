// The peers panel (mockups/macos-peers.png).

import CheeseclothKit
import SwiftUI

struct PeersPage: View {
    @Environment(AppModel.self) private var model
    @Environment(Panels.self) private var panels

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text("\(model.peers.count) members").foregroundStyle(.secondary)
                Button("Invite", systemImage: "person.badge.plus") { panels.show(.invite) }
                    .buttonStyle(.borderedProminent)
            }
            Messages()
            if model.peers.count == 1 {
                Text("No other members yet.").foregroundStyle(.secondary)
            }
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        ForEach(
                            ["", "NAME", "IPV4", "ROLE", "CTRL", "PATH", "STATE", "ENDPOINT", "HANDSHAKE", ""],
                            id: \.self
                        ) { Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                    }
                    Divider()
                    ForEach(model.peers) { row($0) }
                }
            }
            .frame(maxHeight: 480)
            Text("* acceptor  |  CTRL relay = reached through other members")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 820)
        .task { await model.loadPeers() }
    }

    private func row(_ peer: Peer) -> some View {
        GridRow {
            Dot(level: peer.presence)
            Text(peer.thisNode ? "\(peer.name) (this)" : peer.name)
                .foregroundStyle(peer.thisNode ? Color.accentColor : .primary)
                .lineLimit(1)
            Text(peer.ipv4).monospacedDigit()
            Chip(text: peer.role + (peer.acceptor ? "*" : ""))
            if peer.thisNode { Text("") } else { Chip(text: peer.control.text, level: peer.control.level) }
            Chip(text: peer.path)
            HStack(spacing: 5) {
                if let level = peer.stateLevel { Dot(level: level) }
                Text(peer.thisNode ? "-" : peer.pathDetail).lineLimit(1)
            }
            Text(peer.wgEndpoint ?? "-").monospacedDigit()
            Text(peer.handshakeText)
            Menu {
                Button("Copy IP") { model.copy(peer.ipv4) }
                Button("Copy Name") { model.copy(peer.name) }
                if !peer.thisNode {
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
