// The menu-bar app: a status item whose menu is a rounded window under it.
// Each menu item opens its page in a standard window in the middle of the
// screen.
//
// Borderless windows placed by the app, not SwiftUI's MenuBarExtra or an
// NSPopover: a MenuBarExtra window moves and resizes without its shadow,
// and a popover draws an arrow that menu-bar menus do not have. The app
// places its windows itself, so they stay put when the menu bar hides.

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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let panels = Panels()
    private var item: NSStatusItem!
    private var menu: RoundedWindow!
    private var page: PageWindow!
    /// The status item, on its screen, when the menu opened.
    private var icon = NSRect.zero
    private var monitors: [Any] = []

    /// The gap between the menu bar and the menu.
    private static let gap: CGFloat = 5
    /// The space kept free at the screen's edges.
    private static let margin: CGFloat = 8

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon. The bundle's Info.plist also says so (LSUIElement);
        // this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)

        panels.show = { [weak self] panel in self?.show(panel) }
        menu = RoundedWindow(content: MenuView().environment(model).environment(panels))
        menu.place = { [weak self] size in self?.placeMenu(size) ?? .zero }
        page = PageWindow(content: PanelView().environment(model).environment(panels))
        page.closed = { [weak self] in self?.panels.open = nil }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = AppDelegate.icon()
            button.target = self
            button.action = #selector(toggle)
        }
        watchEvents()
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

    @objc private func toggle() {
        if menu.isVisible {
            closeMenu()
            return
        }
        guard let button = item.button, let window = button.window else { return }
        Task { await model.refresh() }
        // Where the icon is now. With the menu bar set to hide, its window
        // moves off the screen once the pointer leaves the menu bar, so the
        // menu is placed from this, not from the icon's window later.
        icon = RoundedWindow.onScreen(window.convertToScreen(button.convert(button.bounds, to: nil)))
        // Keep the menu bar shown while the menu is open, when it is set to
        // hide. It applies while this app is active; a click on the icon lets
        // it become active.
        NSApp.activate()
        NSMenu.setMenuBarVisible(true)
        menu.open()
        // The icon stays highlighted while its menu is open. This action runs
        // inside the button's click, and the button turns its highlight off
        // when the click ends, after this returns. So highlight it once the
        // click is over: the next turn of the main queue.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.menu.isVisible else { return }
            button.highlight(true)
        }
    }

    /// The menu's top-left corner: under the menu bar, its left edge at the
    /// icon's, and on the screen.
    private func placeMenu(_ size: NSSize) -> NSPoint {
        let screen = RoundedWindow.screen(of: icon)
        let x = min(icon.minX, screen.maxX - AppDelegate.margin - size.width)
        return NSPoint(x: max(x, screen.minX + AppDelegate.margin), y: icon.minY - AppDelegate.gap)
    }

    /// Closes the menu, and opens `panel` in the page window, in the middle
    /// of the screen the menu was on. It replaces the page that was open.
    private func show(_ panel: Panel) {
        closeMenu()
        model.clearMessages()
        if panel == .invite { model.forgetInvite() }
        panels.open = panel
        panels.shown += 1
        page.title = panel.title
        NSApp.activate()
        page.open(on: RoundedWindow.screen(of: icon))
    }

    /// Closes the page window if it is open, else the menu. False if neither
    /// was open.
    private func closeTop() -> Bool {
        if page.isVisible {
            page.close()
        } else if menu.isVisible {
            closeMenu()
        } else {
            return false
        }
        return true
    }

    private func closeMenu() {
        menu.close()
        item.button?.highlight(false)
    }

    /// Closes the menu on a click outside the app, as a menu closes, and the
    /// page window or the menu on Escape.
    private func watchEvents() {
        if let outside = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in MainActor.assumeIsolated { self?.closeMenu() } })
        {
            monitors.append(outside)
        }
        if let escape = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self] event in
                guard event.keyCode == 53, let self else { return event }  // Escape
                let closed = MainActor.assumeIsolated { self.closeTop() }
                return closed ? nil : event
            })
        {
            monitors.append(escape)
        }
    }
}

/// A borderless, rounded window with the menu material, sized by its
/// SwiftUI content and placed by `place`.
@MainActor
final class RoundedWindow: NSPanel {
    /// The window's top-left corner on the screen, for a content size.
    var place: (NSSize) -> NSPoint = { _ in .zero }

    private var resizeWatch: (any NSObjectProtocol)?

    init<V: View>(content: V) {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let host = NSHostingController(rootView: content.background(MenuMaterial()))
        // The window takes its content's size, and follows it when it changes.
        host.sizingOptions = [.preferredContentSize]
        contentViewController = host
        // Each time the content resizes the window, put it back in its place.
        resizeWatch = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    // Key focus, so that Escape reaches the app and closes the menu.
    override var canBecomeKey: Bool { true }

    /// Shows the window, fading in once its content has laid out, so that it
    /// appears at its size and place.
    func open() {
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.contentView?.layoutSubtreeIfNeeded()
            self.reposition()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                self.animator().alphaValue = 1
            }
        }
    }

    /// Moves the window to its place for its size, and redraws the shadow
    /// for its shape.
    private func reposition() {
        let size = frame.size
        let topLeft = place(size)
        setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - size.height))
        invalidateShadow()
    }

    /// `rect` (a status item), moved down onto its screen if the menu bar is
    /// hidden at the moment.
    static func onScreen(_ rect: NSRect) -> NSRect {
        var rect = rect
        let top = screen(of: rect).maxY
        if rect.maxY > top { rect.origin.y = top - rect.height }
        return rect
    }

    /// The frame of the screen under `rect`'s middle.
    static func screen(of rect: NSRect) -> NSRect {
        let screen = NSScreen.screens.first {
            $0.frame.minX <= rect.midX && rect.midX < $0.frame.maxX && $0.frame.minY <= rect.minY
        }
        return (screen ?? NSScreen.main)?.frame ?? .zero
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

/// The menu's background: the system menu material, behind the window, in a
/// rounded rectangle. A mask, not a clipped layer, so that the window's
/// shadow takes the rounded shape.
struct MenuMaterial: NSViewRepresentable {
    static let radius: CGFloat = 10

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.state = .active
        view.blendingMode = .behindWindow
        view.maskImage = MenuMaterial.roundedMask()
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    /// A rounded rectangle that stretches without stretching its corners.
    private static func roundedMask() -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
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
