# Plan: the menu-bar app

Phase 3 of cheesecloth's
[packaging plan](https://github.com/jdpanderson/cheesecloth/blob/main/docs/plans/packaging.md),
for macOS. It needs the local API access and versioning from cheesecloth's
`docs/plans/local-api.md` first.

## Goal

`Cheesecloth.app`, for macOS 14 or later:
- a menu-bar icon that does nothing until it is clicked;
- a menu, a status panel and a peers panel, as in the mockups
  (`macos-interface.png`, `macos-status.png`, `macos-peers.png`);
- it carries the `cheesecloth` binary and runs it as a launchd daemon
  through `SMAppService`, so the daemon starts at boot.

The app replaces the `.pkg`. There is no installed base, so there is no
migration from it.

## Step 0: can an unsigned app register a daemon?

`SMAppService.daemon(plistName:)` registers a LaunchDaemon from the app
bundle. Apple's examples sign with a team, and the docs don't say whether an
ad-hoc signature works. Today nothing here is signed.

A test app, ad-hoc signed (`codesign -s -`), in `/Applications`, on macOS 14
and on the current macOS:
1. register a daemon that writes a file as root;
2. approve it in System Settings > General > Login Items;
3. reboot, and check that it runs;
4. unregister it, and check that launchd stops it, and whether that asks
   for a password (see [Quit](#quit)).

The app is decided either way; this test only says whether it costs money.
- If it works: go on as below, and keep "not signed" as a weak point.
- If it does not: join the Apple Developer Program, sign with a Developer ID
  and notarize (see [Signing](#signing)).

Result: it works. The ad hoc signed app, opened from `/Applications` on
macOS 26, registered the daemon after approval in Login Items, and Quit
stopped it. macOS 14 is not tested yet. The first releases are signed ad
hoc.

## Bundle layout

```
Cheesecloth.app/Contents/
  Info.plist                 LSUIElement = true (no Dock icon)
  MacOS/Cheesecloth          the Swift app
  Helpers/cheesecloth        the pinned binary, unchanged
  Library/LaunchDaemons/ca.janderson.cheesecloth.plist
  Resources/                 AppIcon.icns, README, LICENSE, notices, docs
  Resources/Cheesecloth_Cheesecloth.bundle
                             the Swift package's resources (the menu-bar icon)
```

`swift build` puts the resource bundle beside the executable. The app finds
it in `Contents/Resources` (`Bundle.module`), so `build.sh` copies it there.

The binary is in `Helpers/`, not `MacOS/`: APFS is not case-sensitive by
default, so `MacOS/Cheesecloth` and `MacOS/cheesecloth` would be one file.

The LaunchDaemon plist:
- `BundleProgram`: `Contents/Helpers/cheesecloth`, arguments `daemon`;
- `KeepAlive` true, `RunAtLoad` true;
- `StandardOutPath` and `StandardErrorPath`: `/Library/Logs/cheesecloth.log`.

Daemon options (relay mode, advertise addresses and so on) are out of scope.
The defaults are used. A later step can add a settings file the plist reads.

## The app

Swift 6 and SwiftUI, built as a Swift package (`swift build`, no Xcode
project), so CI and a terminal build the same way. AppKit starts the app and
owns its windows: an `NSStatusItem`, a borderless rounded window for its
menu, and a standard window for each page. SwiftUI draws what is inside
them. No SwiftUI `App` or scene: SwiftUI opens a scene's window when the app's
last window closes, and this app has no window to show then.

Parts:
- `APIClient`: connects to `/Library/Application Support/cheesecloth/control.sock`,
  sends one JSON line, reads one line. `Codable` types written from
  `LOCAL-API.md`. Calls `hello` first and refuses an unknown `api` number.
- `DaemonService`: wraps `SMAppService`: status (not registered, needs
  approval, enabled), register, unregister, open Login Items settings.
- `Model`: asks for `status` when the menu opens, and `peers` when the peers
  window opens. The status window asks again every 5 seconds while it is
  open. Nothing runs while no window is open.

The icon is a monochrome template image, so macOS tints it. It does not
change with the node's state. It is `mockups/menubar_template.svg`, copied to
`app/Sources/Cheesecloth/Resources/`; copy it again when the design changes.

The menu (`macos-interface.png`):
- header: "Cheesecloth", the state ("Connected" and so on), node name and
  member count;
- each item opens its page in a standard window in the middle of the
  screen, with the close button in its title bar; the menu closes;
- "Status…" and "Peers…" open their windows;
- no "Invite Node…": the Peers window's "Invite" button opens a window with
  a button that creates an invite, then shows the token with a copy button;
- "Quit", which also stops the daemon (see [Quit](#quit)).

The status window (`macos-status.png`) is laid out as System Settings is: a
sidebar of sections (Overview, Network, Consensus, Security, Connectivity),
each with a dot for its health, and the chosen section beside it as a
grouped form. The window keeps one size for every section. A node that is
not a member has only the overview. The overview starts with any warnings.
The Network section ends with "Leave Network…", which asks first. The window
refreshes itself every 5 seconds, so it has no Refresh button. The mockup's
"Open Logs…" and settings buttons are not in the first version.

The peers window (`macos-peers.png`): a table of name, IPv4, role (with
acceptors marked), control connection, path, state, endpoint and handshake
age, and an "Invite" button. Each row's "…" menu has "Copy IP", "Copy Name"
and "Remove…" (asks first; not on this node's row).

The mockups live in `mockups/` beside the repositories, not in a
repository. They change as the design does.

### Quit

The daemon runs while the app runs. This is a choice for macOS users: they
expect Quit to turn a thing off.
- App start: register the LaunchDaemon. macOS asks for approval once; after
  that, registering starts the daemon at once.
- "Quit": unregister it. launchd stops the daemon with SIGTERM, and the daemon
  shuts down cleanly, as it does for `cheesecloth stop`. Then the app exits.
- Log out, restart or shut down: the app ends without its Quit item, so it
  does not unregister. The daemon starts again at boot, before anyone logs
  in.
- If unregistering fails, the app stays open and says so, because the
  daemon still runs.
- The app starts at login (`SMAppService.mainApp`), with no setting for it
  in the first version. The user can turn it off in System Settings > Login
  Items.

The app does not use the API's `stop`.

The app shows the daemon's `{"err": ...}` text as is. It does not parse it.

If the logged-in user is not in `admin`, the API refuses the connection. The
app says so.

## Command line

The binary is inside the app, at
`/Applications/Cheesecloth.app/Contents/Helpers/cheesecloth`. The README says
how to link it into `/usr/local/bin`. An "Install command-line tool…" item
belongs in the settings, which come after the first version.

## Build and CI

`build.sh <source> <binary>...`:
1. joins the binaries with `lipo` (CI passes the two pinned binaries, after
   checking a release binary against the pin's SHA-256);
2. `swift build -c release` with an `--arch` for each architecture of the
   binary;
3. assembles the bundle; the plists are in `app/Bundle/`;
4. `codesign -s -` (ad hoc) with the hardened runtime, or later a Developer
   ID signature (see [Signing](#signing));
5. a disk image (`hdiutil create`) with the app and a link to
   `/Applications`, so the user drags the app there; then it checks the app
   in the disk image: `codesign --verify`, the architectures, and
   `Helpers/cheesecloth --version`.

One universal app, not one per architecture. CI also runs the Swift unit
tests, which check the API types against the examples in `LOCAL-API.md` at
the pinned commit or tag. A release attaches the disk image and its SHA-256.

A CI test with a real daemon would need root and approval in System
Settings, so it is a manual release step.

## Signing

Not needed: step 0 passed. It is still worth doing later: a signed and
notarized app opens from Finder without a Gatekeeper block, and the
"not signed" weak point goes away.

- Apple Developer Program membership, and a "Developer ID Application"
  certificate.
- Sign the app and `Helpers/cheesecloth` with the hardened runtime
  (`codesign --options runtime`). The binary stays as released, apart from
  the signature that `codesign` adds. CI checks its SHA-256 before signing,
  and `--version` after.
- Sign the disk image, notarize it with `notarytool`, then staple it.
- The certificate and a notary API key are secrets of this repository only,
  used by the release job. That matches the split in cheesecloth's
  `docs/REPOSITORIES.md`: package signing and its secrets live in the OS
  repository.

## Steps

1. Step 0, the signing test. Done: ad hoc works.
2. cheesecloth: the local API plan. The pin names its branch's commit until
   it is merged; then pin the merged commit, and later its release.
3. The Swift package: `APIClient`, `Model`, the menu, against a daemon run by
   hand with `sudo cheesecloth daemon`. Done.
4. `DaemonService`, the plist and the bundle. Done.
5. `build.sh`, CI, README (install, uninstall, weak points), CHANGELOG. Done.
6. Remove the `.pkg` build. Done.

## Open questions

- Icons and the screens the mockups don't show yet: a list of what the
  designer needs is with the mockups. Until they are drawn, SF Symbols and
  plain SwiftUI views stand in.
