// The menu (mockups/macos-interface.png): a header with the state, and the
// rows that fit it. Rows that open a page open it in the page window.
//
// The header is a custom view, for its multi-line layout; it is not a row,
// so it is never highlighted or clicked. The rows are plain NSMenuItems:
// once an item has a custom view, AppKit no longer highlights or tracks it
// at all, and the app would have to do that by hand. Plain items keep the
// system's own highlight, which also tracks the pointer leaving a row or
// the menu correctly, for free.

import AppKit
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

/// A plain menu item with a Swift closure instead of a target and a
/// selector, and an SF Symbol for its icon.
final class RowItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, _ symbol: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(chosen), keyEquivalent: "")
        target = self
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        self.image = image
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("RowItem does not support NSCoding")
    }

    @objc private func chosen() {
        handler()
    }
}

/// The menu's rows, for the state at hand.
@MainActor
enum MenuRows {
    static func rows(for model: AppModel, panels: Panels) -> [NSMenuItem] {
        func row(_ title: String, _ symbol: String, panel: Panel) -> NSMenuItem {
            RowItem(title, symbol) {
                panels.close()
                panels.show(panel)
            }
        }
        func row(_ title: String, _ symbol: String, action: @escaping () -> Void) -> NSMenuItem {
            RowItem(title, symbol) {
                panels.close()
                action()
            }
        }

        var rows: [NSMenuItem] = []
        switch model.state {
        case .connected:
            rows.append(row("Status…", "chart.bar.xaxis", panel: .status))
            rows.append(row("Peers…", "person.3", panel: .peers))
            if !model.proposals.isEmpty {
                rows.append(row("Approvals (\(model.proposals.count))…", "checkmark.seal", panel: .approvals))
            }
        // Invite is in the Peers window, and Leave Network in the Status
        // window.
        case .noNetwork:
            rows.append(row("Create Network…", "plus.circle", panel: .create))
            rows.append(row("Join Network…", "link", panel: .join))
        case .waitingForApproval:
            rows.append(row("Status…", "chart.bar.xaxis", panel: .status))
            rows.append(row("Cancel Join", "xmark.circle") { model.confirmLeave(cancelJoin: true) })
        case .leaving:
            rows.append(row("Retry Leave", "arrow.clockwise") { Task { await model.leave(force: false) } })
            rows.append(row("Open Logs…", "doc.text") { model.openLogs() })
        case .notResponding:
            rows.append(row("Open Logs…", "doc.text") { model.openLogs() })
        case .allowInSettings:
            rows.append(row("Open System Settings…", "gearshape") { model.openSettings() })
        case .starting, .administratorsOnly, .needsReinstall, .quitting:
            break
        }
        return rows
    }
}
