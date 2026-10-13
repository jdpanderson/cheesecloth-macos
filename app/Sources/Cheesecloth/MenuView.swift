// The menu (mockups/macos-interface.png): a header with the state, and the
// items that fit it. Items that open a page open it in the page window.

import CheeseclothKit
import SwiftUI

struct MenuView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Messages()
            Divider()
            items
        }
        .padding(12)
        .frame(width: 300)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cheesecloth").font(.title3.bold())
            HStack(spacing: 8) {
                Dot(level: model.state.level)
                Text(model.state.title).font(.headline)
            }
            if let detail = model.state.detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 17)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder private var items: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.state {
            case .connected:
                MenuItem("Status…", "chart.bar.xaxis", panel: .status)
                MenuItem("Peers…", "person.3", panel: .peers)
                if !model.proposals.isEmpty {
                    MenuItem("Approvals (\(model.proposals.count))…", "checkmark.seal", panel: .approvals)
                }
                // Invite is in the Peers window, and Leave Network in the
                // Status window.
            case .noNetwork:
                MenuItem("Create Network…", "plus.circle", panel: .create)
                MenuItem("Join Network…", "link", panel: .join)
            case .waitingForApproval:
                MenuItem("Status…", "chart.bar.xaxis", panel: .status)
                MenuItem("Cancel Join", "xmark.circle") { model.confirmLeave(cancelJoin: true) }
            case .leaving:
                MenuItem("Retry Leave", "arrow.clockwise") { Task { await model.leave(force: false) } }
                MenuItem("Open Logs…", "doc.text") { model.openLogs() }
            case .notResponding:
                MenuItem("Open Logs…", "doc.text") { model.openLogs() }
            case .allowInSettings:
                MenuItem("Open System Settings…", "gearshape") { model.openSettings() }
            case .starting, .administratorsOnly, .needsReinstall, .quitting:
                EmptyView()
            }
            if model.state != .quitting {
                Divider().padding(.vertical, 4)
                MenuItem("Quit", "power") { model.quit() }
            }
        }
        .disabled(model.busy)
    }
}

/// One menu item. It is highlighted under the pointer, as macOS menu items
/// are.
struct MenuItem: View {
    @Environment(Panels.self) private var panels
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    private let title: String
    private let symbol: String
    private let panel: Panel?
    private let action: () -> Void

    init(_ title: String, _ symbol: String, panel: Panel) {
        self.title = title
        self.symbol = symbol
        self.panel = panel
        action = {}
    }

    init(_ title: String, _ symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        panel = nil
        self.action = action
    }

    private var highlighted: Bool { enabled && hovering }

    var body: some View {
        Button {
            if let panel { panels.show(panel) } else { action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(highlighted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
