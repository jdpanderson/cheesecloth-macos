// The menu-bar app: a status item with a standard NSMenu, so its material
// and placement match the rest of the menu bar exactly. Each row is a
// custom view, for its icon and hover highlight. Each menu item opens its
// page in a standard window in the middle of the screen.

import AppKit
import CheeseclothKit
import SwiftUI

/// Starts the app with AppKit, not SwiftUI's `App`: an `App` needs a scene,
/// and SwiftUI opens that scene's window when the app is active and its last
/// window closes. The status item is this app's UI, so it has no scene.
@main
@MainActor
enum CheeseclothApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        // `delegate` is weak; this local holds the delegate while `run` runs.
        app.delegate = delegate
        app.mainMenu = mainMenu()
        app.run()
    }

    /// The menu bar is not shown (the app has no Dock icon), but its key
    /// equivalents still work: the Edit commands for the text fields, and
    /// Close for the page window. No Quit: "Quit" in the status item's menu
    /// also stops the daemon.
    private static func mainMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let bar = NSMenu()
        for menu in [NSMenu(title: "Cheesecloth"), edit, window] {
            bar.addItem(withTitle: menu.title, action: nil, keyEquivalent: "").submenu = menu
        }
        return bar
    }
}

/// The pages that the menu opens, each in the page window.
enum Panel: Hashable {
    case status
    case peers
    case approvals
    case invite
    case join
    case create

    /// The page window's title.
    var title: String {
        switch self {
        case .status: "Status"
        case .peers: "Peers"
        case .approvals: "Approvals"
        case .invite: "Invite Node"
        case .join: "Join Network"
        case .create: "Create Network"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private let panels = Panels()
    private var item: NSStatusItem!
    private var menu: NSMenu!
    private var page: PageWindow!
    /// The screen the status item was on when the menu last opened, for
    /// centering a page window.
    private var screen = NSRect.zero
    private var monitors: [Any] = []
    /// Whether the menu is open, so the model is only watched while it is.
    private var menuIsOpen = false

    /// Every row's width, so they line up under each other.
    static let menuWidth: CGFloat = 300

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon. The bundle's Info.plist also says so (LSUIElement);
        // this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)

        panels.show = { [weak self] panel in self?.show(panel) }
        panels.close = { [weak self] in self?.menu.cancelTracking() }
        page = PageWindow(content: PanelView().environment(model).environment(panels))
        page.closed = { [weak self] in self?.panels.open = nil }

        menu = NSMenu()
        menu.delegate = self

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = AppDelegate.icon()
        item.menu = menu
        watchEscape()
        model.launch()
    }

    /// The menu-bar icon: a template image, so macOS tints it for the menu
    /// bar's appearance.
    private static func icon() -> NSImage {
        guard let url = Bundle.module.url(forResource: "menubar", withExtension: "svg"),
            let image = NSImage(contentsOf: url)
        else {
            fatalError("menubar.svg is missing from the app's resources")
        }
        image.size = NSSize(width: 18, height: 16)
        image.isTemplate = true
        image.accessibilityDescription = "Cheesecloth"
        return image
    }

    /// Builds the menu's rows for the state at hand, right before the system
    /// shows it.
    func menuNeedsUpdate(_ menu: NSMenu) {
        var items = [hosted(MenuHeaderView().environment(model))]
        items.append(.separator())
        for row in MenuRows.rows(for: model) {
            items.append(hosted(row.disabled(model.busy).environment(panels)))
        }
        if model.state != .quitting {
            items.append(.separator())
            items.append(
                hosted(MenuItem("Quit", "power") { self.model.quit() }.disabled(model.busy).environment(panels)))
        }
        menu.items = items
    }

    func menuWillOpen(_ menu: NSMenu) {
        screen = item.button?.window?.screen?.frame ?? NSScreen.main?.frame ?? .zero
        // Keep the menu bar shown while the menu is open, when it is set to
        // hide. It applies while this app is active; a click on the icon lets
        // it become active.
        NSApp.activate()
        NSMenu.setMenuBarVisible(true)
        Task { await model.refresh() }
        menuIsOpen = true
        watchModel()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    /// Rebuilds the open menu's rows each time the model changes, so a
    /// status update that lands while the menu is open still shows.
    private func watchModel() {
        withObservationTracking {
            _ = (model.state, model.proposals, model.busy, model.error, model.notice)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.menuIsOpen else { return }
                self.menu.update()
                self.watchModel()
            }
        }
    }

    /// Wraps `content` as one menu item's custom view, sized to fit it.
    private func hosted<V: View>(_ content: V) -> NSMenuItem {
        let hosting = NSHostingView(rootView: content.frame(width: AppDelegate.menuWidth, alignment: .leading))
        hosting.frame.size = hosting.fittingSize
        let item = NSMenuItem()
        item.view = hosting
        return item
    }

    /// Opens `panel` in the page window, in the middle of the screen the
    /// menu was on. It replaces the page that was open.
    private func show(_ panel: Panel) {
        model.clearMessages()
        if panel == .invite { model.forgetInvite() }
        panels.open = panel
        panels.shown += 1
        page.title = panel.title
        NSApp.activate()
        page.open(on: screen)
    }

    /// Closes the page window on Escape. The menu closes itself.
    private func watchEscape() {
        if let escape = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self] event in
                guard event.keyCode == 53, let self, self.page.isVisible else { return event }  // Escape
                self.page.close()
                return nil
            })
        {
            monitors.append(escape)
        }
    }
}

/// A standard window for a page: a title bar with its close button, in the
/// middle of the screen, sized by its page.
@MainActor
final class PageWindow: NSWindow, NSWindowDelegate {
    /// Called when the window closes, by its close button, Escape or the
    /// app.
    var closed: () -> Void = {}

    private var screenFrame = NSRect.zero
    private var resizeWatch: (any NSObjectProtocol)?

    init<V: View>(content: V) {
        super.init(
            contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        // Only the close button: a page is not minimised or zoomed.
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        let host = NSHostingController(rootView: content)
        // The window takes its page's size, and follows it when it changes.
        host.sizingOptions = [.preferredContentSize]
        contentViewController = host
        delegate = self
        // A page that grows or shrinks stays in the middle of the screen.
        resizeWatch = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.centerOnScreen() }
        }
    }

    /// Shows the window in the middle of `screen`, once its page has laid
    /// out.
    func open(on screen: NSRect) {
        screenFrame = screen
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.contentView?.layoutSubtreeIfNeeded()
            self.centerOnScreen()
            self.alphaValue = 1
        }
    }

    private func centerOnScreen() {
        let size = frame.size
        setFrameOrigin(
            NSPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2))
    }

    func windowWillClose(_ notification: Notification) {
        closed()
    }
}

/// Which page is open, and how to open one.
@MainActor
@Observable
final class Panels {
    var open: Panel?
    /// Counts the showings, so that a page shown again loads again.
    var shown = 0
    @ObservationIgnored var show: (Panel) -> Void = { _ in }
    /// Closes the menu. Set by the app delegate.
    @ObservationIgnored var close: () -> Void = {}
}

/// The page of the page window.
struct PanelView: View {
    @Environment(Panels.self) private var panels

    var body: some View {
        Group {
            switch panels.open {
            case .status: StatusPage()
            case .peers: PeersPage()
            case .approvals: ApprovalsPage()
            case .invite: InvitePage()
            case .join: JoinPage()
            case .create: CreatePage()
            case nil: EmptyView()
            }
        }
        .id(panels.shown)
        // The status page is a split view, which reaches the window's
        // edges as System Settings does.
        .padding(panels.open == .status ? 0 : 16)
        .fixedSize()
    }
}

extension Level {
    var color: Color {
        switch self {
        case .good: .green
        case .attention: .orange
        case .broken: .red
        case .off: .gray
        case .info: Color(red: 0.42, green: 0.53, blue: 0.66)
        }
    }
}

struct Dot: View {
    var level: Level

    var body: some View {
        Circle().fill(level.color).frame(width: 9, height: 9)
    }
}

struct BadgeView: View {
    var badge: Badge

    var body: some View {
        HStack(spacing: 5) {
            Dot(level: badge.level)
            Text(badge.text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(badge.level.color.opacity(0.14), in: Capsule())
    }
}

/// The last action's error or result.
struct Messages: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let error = model.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let notice = model.notice {
            Text(notice)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
