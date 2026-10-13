// The pages for changes to the network: invite, join, create and
// approvals. Leaving and removing ask with an alert instead (`AppModel`).

import CheeseclothKit
import SwiftUI

struct InvitePage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "An invite lets one new node join this network. It works once, and expires after 30 minutes."
            )
            .fixedSize(horizontal: false, vertical: true)
            if let invite = model.invite {
                Text("On the new node, join with this token:")
                Text(invite.token)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                HStack {
                    Button("Copy", systemImage: "doc.on.doc") { model.copy(invite.token) }
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(expiry(invite.expiresAt, now: context.date))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            Messages()
            HStack {
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button(model.invite == nil ? "Create Invite" : "Create Another") {
                    Task { await model.createInvite() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.busy)
            }
        }
        .frame(width: 380)
    }

    private func expiry(_ at: Date, now: Date) -> String {
        let left = Int(at.timeIntervalSince(now))
        if left <= 0 { return "Expired" }
        return String(format: "Expires in %d:%02d", left / 60, left % 60)
    }
}

struct JoinPage: View {
    @Environment(AppModel.self) private var model
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste the token from Peers > Invite on a member.")
            TextField("Token", text: $token, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .lineLimit(3...6)
            HStack {
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Join") { Task { await model.join(token: token.trimmingCharacters(in: .whitespacesAndNewlines)) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(token.isEmpty || model.busy)
            }
            Messages()
        }
        .frame(width: 360)
    }
}

struct CreatePage: View {
    @Environment(AppModel.self) private var model
    @State private var range = ""
    @State private var strict = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Mac becomes the network's first member.")
            TextField("IPv4 range (default: a random /24 in 100.64.0.0/10)", text: $range)
            Toggle("Strict security", isOn: $strict)
                .help("Keep Byzantine protection once there are enough members, and pause changes instead of giving it up.")
            HStack {
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Create") { Task { await model.create(ipv4Range: range, strictSecurity: strict) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)
            }
            Messages()
        }
        .frame(width: 360)
    }
}

struct ApprovalsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Messages()
            if model.proposals.isEmpty {
                Text("Nothing waits for approval.").foregroundStyle(.secondary)
            }
            ForEach(model.proposals) { proposal in
                VStack(alignment: .leading, spacing: 6) {
                    Text(title(proposal)).font(.headline)
                    if let node = proposal.node {
                        Text(node)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        if proposal.kind == "join" {
                            Text("Check this ID against the one the joining node shows.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(
                        "Asked by \(shortID(proposal.proposer)) • \(proposal.approvals.count) of \(proposal.needed) approvals • expires in \(proposal.expiresInSecs / 60) min"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Reject") { Task { await model.vote(proposal, approve: false) } }
                        Button("Approve") { Task { await model.vote(proposal, approve: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                    .disabled(model.busy)
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(width: 420)
        .task { await model.refresh() }
    }

    private func title(_ p: Proposal) -> String {
        switch p.kind {
        case "join": "Join of \(p.name ?? "a node")"
        case "remove": "Removal of \(p.name ?? "a member")"
        case "setting":
            if let s = p.setting { "Setting \(s.key) = \(s.value)" } else { "A setting change" }
        default: "A change"
        }
    }
}
