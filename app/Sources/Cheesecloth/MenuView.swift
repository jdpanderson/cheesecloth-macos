// The menu (mockups/macos-interface.png): a header with the state, and the
// rows that fit it. Each becomes one NSMenuItem (see CheeseclothApp.swift),
// so the system menu owns the material and placement. Rows that open a page
// open it in the page window.

import CheeseclothKit
import SwiftUI

/// The menu's header: the app name, the state, and any error or notice.
/// Not a row: it does nothing when clicked.
struct MenuHeaderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            Messages()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// The menu's rows, for the state at hand. The app delegate turns each into
/// one NSMenuItem.
@MainActor
enum MenuRows {
    static func rows(for model: AppModel) -> [AnyView] {
        var rows: [AnyView] = []
        switch model.state {
        case .connected:
            rows.append(AnyView(MenuItem("Status…", "chart.bar.xaxis", panel: .status)))
            rows.append(AnyView(MenuItem("Peers…", "person.3", panel: .peers)))
            if !model.proposals.isEmpty {
                rows.append(
                    AnyView(
                        MenuItem(
                            "Approvals (\(model.proposals.count))…", "checkmark.seal", panel: .approvals)))
            }
        // Invite is in the Peers window, and Leave Network in the Status
        // window.
        case .noNetwork:
            rows.append(AnyView(MenuItem("Create Network…", "plus.circle", panel: .create)))
            rows.append(AnyView(MenuItem("Join Network…", "link", panel: .join)))
        case .waitingForApproval:
            rows.append(AnyView(MenuItem("Status…", "chart.bar.xaxis", panel: .status)))
            rows.append(AnyView(MenuItem("Cancel Join", "xmark.circle") { model.confirmLeave(cancelJoin: true) }))
        case .leaving:
            rows.append(
                AnyView(MenuItem("Retry Leave", "arrow.clockwise") { Task { await model.leave(force: false) } }))
            rows.append(AnyView(MenuItem("Open Logs…", "doc.text") { model.openLogs() }))
        case .notResponding:
            rows.append(AnyView(MenuItem("Open Logs…", "doc.text") { model.openLogs() }))
        case .allowInSettings:
            rows.append(AnyView(MenuItem("Open System Settings…", "gearshape") { model.openSettings() }))
        case .starting, .administratorsOnly, .needsReinstall, .quitting:
            break
        }
        return rows
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
            panels.close()
            if let panel { panels.show(panel) } else { action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 14)
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
