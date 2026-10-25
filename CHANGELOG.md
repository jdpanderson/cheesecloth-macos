# Changelog

All notable changes to the macOS app and installer are listed here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). A
release names the cheesecloth version it packages plus a package revision,
such as `0.4.0-2`.

## [Unreleased]

## [0.5.0-2] - 2026-10-24

### Changed

- The menu's dropdown is a standard menu, so its background matches the
  rest of the menu bar. It no longer looks more opaque than the other
  menus.

## [0.5.0-1] - 2026-10-24

### Changed

- The app carries cheesecloth 0.5.0.

## [0.5.0-beta.7-1] - 2026-10-24

### Changed

- The Peers window matches the GNOME and Windows apps. Roles and
  permissions show as icons, and the path state as a coloured dot. Each has
  a tooltip that names it and says what it means, so the legend at the
  bottom is gone.
- The Invite button of the Peers window is a + at the right.

## [0.5.0-beta.6-1] - 2026-10-23

### Changed

- The app carries cheesecloth 0.5.0-beta.6.

## [0.5.0-beta.5-1] - 2026-10-22

### Changed

- The app carries cheesecloth 0.5.0-beta.5. It has a Windows fix, and
  nothing that changes the app on macOS.

## [0.5.0-beta.4-1] - 2026-10-22

### Changed

- The app carries cheesecloth 0.5.0-beta.4. It has a Windows fix, and
  nothing that changes the app on macOS.

## [0.5.0-beta.3-1] - 2026-10-21

### Changed

- The app carries cheesecloth 0.5.0-beta.3. It has a Windows fix and code
  cleanups, and nothing that changes the app on macOS.

## [0.5.0-beta.2-1] - 2026-10-21

### Changed

- The app carries cheesecloth 0.5.0-beta.2. It has dependency updates and
  a Windows fix, and nothing that changes the app on macOS.

## [0.5.0-beta.1-1] - 2026-10-15

### Added

- Member permissions. The Invite window has a checkbox for each permission,
  Admin, Voter and Relay, all on by default. The Status window and join
  approvals show the permissions, and the Peers window has a Permissions
  column: "All", a list such as "Voter, Relay", or "Member".

### Changed

- The app carries cheesecloth 0.5.0-beta.1, which adds member permissions.
  Its local API and agreed state differ from 0.5.0-beta.0: rebuild existing
  networks.
- On a member without the admin permission, the app has no Invite button,
  no Remove item for peers and no Approvals item in the menu.

## [0.5.0-beta.0-1] - 2026-10-13

The first test release of the menu-bar app, with cheesecloth 0.5.0-beta.0.

### Added

- `Cheesecloth.app`, a menu-bar app for macOS 14 or later, in place of the
  `.pkg`. Its menu shows the node's state and opens the Status and Peers
  windows, and creates or joins a network. Peers can invite, approve and
  remove nodes. Users in `admin` can use it without a password.
- The app carries the `cheesecloth` binary and runs it as a launchd daemon
  (`SMAppService`) while the app runs. Quit stops the daemon. The app starts
  at login.
- One universal app for Apple Silicon and Intel, signed ad hoc and not
  notarized, on a disk image: `Cheesecloth-<version>-macos.dmg`.

### Changed

- `build.sh` accepts a cheesecloth pre-release version, such as
  `0.5.0-beta.1`. The disk image's name has the full version; the app's
  version in `Info.plist` is the plain `0.5.0`, as macOS allows only numbers.
- `build.sh` builds the app from a cheesecloth checkout and one or two
  binaries, and puts it on a disk image with a link to `/Applications`.
- The pin names a cheesecloth commit with the local API that the app needs
  (`hello` and access for the `admin` group).

### Removed

- The `.pkg` installers. To remove an installed one:
  `sudo rm /usr/local/bin/cheesecloth`,
  `sudo rm -r /usr/local/share/doc/cheesecloth` and
  `sudo pkgutil --forget ca.janderson.cheesecloth`.

## [0.4.0-1] - 2026-10-11

### Changed

- The installer packages cheesecloth 0.4.0. Not signed or notarized.

## [0.4.0pre0-1] - 2026-10-11

A test pre-release of the installer, for cheesecloth 0.4.0pre0. Not signed or
notarized.

### Changed

- The macOS installer moved here from the cheesecloth repository. `build.sh`
  now takes a built binary and a cheesecloth checkout, and no longer needs
  Cargo or Python.
- The installer no longer strips the binary. Backtraces show function names,
  and the installed binary is the same as the one that was built or
  released.

### Added

- `cheesecloth.pin`, the cheesecloth commit or release that the installer
  packages. For a commit, CI builds the binary from source. For a release,
  it downloads the release binaries and checks them against the SHA-256
  values in the pin. The pin names the test release 0.4.0pre0.
- Package releases. A tag `v<release>-<revision>` publishes the installers
  and a `SHA256SUMS` file on this repository's releases.
