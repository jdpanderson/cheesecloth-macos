# macOS app

`Cheesecloth.app`, the menu-bar app for
[cheesecloth](https://github.com/jdpanderson/cheesecloth) on macOS 14 or
later. It carries the `cheesecloth` binary and runs it as a launchd daemon
while the app runs. One universal app runs on Apple Silicon and Intel.

## Install

Download `Cheesecloth-<version>-macos.dmg` from the
[releases](https://github.com/jdpanderson/cheesecloth-macos/releases). The
version is the cheesecloth release plus a package revision, such as `0.5.0-1`,
or `0.5.0-beta.1-1` for a pre-release.
Check that `shasum -a 256 <file>` prints the SHA-256 that the release's
`SHA256SUMS` lists for it.

1. Open the disk image, and drag `Cheesecloth.app` onto the Applications
   folder beside it. Then eject the disk image.
2. Open Cheesecloth from `/Applications`. The app is not notarized, so macOS
   blocks it the first time. Go to System Settings > Privacy & Security, and
   click "Open Anyway" for Cheesecloth.
3. macOS asks to let the app run a background item. Allow it in System
   Settings > General > Login Items & Extensions. The app starts the daemon
   as soon as it is allowed.

The menu-bar icon then shows the node's state. From the menu, create a
network or join one with a token from an existing member.

A CI run's **Artifacts** also hold the app, named with the version of the
binary only.

A newer app upgrades in place: quit the old one, replace it in
`/Applications`, and open the new one. Downgrades are not supported: an older
daemon may not read the state files of a newer one.

## Use

- The app starts at login. It starts the daemon when it starts.
- **Quit** in the menu stops the daemon, then quits the app.
- After a logout or a restart without Quit, the daemon starts at boot, before
  anyone logs in, and the app starts again at login.
- Users in the `admin` group can use the app. The daemon refuses other users.
- The daemon's log is `/Library/Logs/cheesecloth.log`.

The daemon has its default options. There are no settings in the app yet.

### Command line

The binary is inside the app. To run it as `cheesecloth`:

```sh
sudo ln -s /Applications/Cheesecloth.app/Contents/Helpers/cheesecloth /usr/local/bin/cheesecloth
```

Users in `admin` can run every command without `sudo`, except `stop`. Do not
start a second daemon with `cheesecloth daemon` while the app runs one.

## Uninstall

1. Choose Quit in the menu, so the daemon stops and launchd forgets it.
2. Delete `/Applications/Cheesecloth.app`, and the link in `/usr/local/bin` if
   you made one.
3. If Cheesecloth is still listed in System Settings > General > Login Items
   & Extensions, remove it there.

This keeps the state directory, `/Library/Application Support/cheesecloth`,
with the node's keys and network state; delete it to forget the node. Leave
the network first (Status > Network > Leave Network…) if the node should not
come back. The log is `/Library/Logs/cheesecloth.log`.

## Weak points

- **Signed ad hoc, not notarized.** macOS blocks the app the first time it is
  opened; see [Install](#install). A Developer ID signature and
  notarization would remove this step.
- **Tested on one macOS version.** Running the daemon from an ad hoc signed
  app has been tested on macOS 26 only.
- **No settings.** The daemon runs with its default options.

## Building

CI (`.github/workflows/ci.yml`) gets the pinned binary for arm64 and x86_64
in the `binary` job (see [the pin file](#the-pin-file)). The `test` job runs
the app's unit tests. The `app` job then runs `build.sh`, which:
1. joins the two binaries into one universal binary with `lipo`;
2. builds the Swift app for both architectures;
3. assembles `Cheesecloth.app`, with the binary in `Contents/Helpers`, the
   LaunchDaemon plist, the icon, and cheesecloth's README, LICENSE, notices
   and docs;
4. signs the binary and the app ad hoc, with the hardened runtime;
5. puts it on a disk image, `dist/Cheesecloth-<version>.dmg`, with a link to
   `/Applications`, and checks the app on the disk image: its signature, its
   architectures and the binary's version.

The binary is not stripped, so backtraces show function names. It is the
binary that was built or released, apart from the signature.

To build one by hand on a Mac with Xcode, with a cheesecloth checkout beside
this one, at the commit or tag of the binary:

```sh
bash build.sh ../cheesecloth ../cheesecloth/target/release/cheesecloth
```

With one binary, the app is for that architecture only. Pass an arm64 and an
x86_64 binary for a universal app. Release binaries are built for macOS 14. If
you build one yourself, set `MACOSX_DEPLOYMENT_TARGET=14.0`, as CI does.

The app's tests read the local API examples from `docs/LOCAL-API.md` in the
cheesecloth checkout beside this one, or from the file that
`CHEESECLOTH_API_DOC` names:

```sh
swift test --package-path app
```

The menu-bar icon is `mockups/menubar_template.svg` and the app icon
`mockups/app-icon.png`, from the mockups beside the repositories. Copy them to
`app/Sources/Cheesecloth/Resources/` and `app/Bundle/AppIcon.png` when the
design changes. The plan is in
[docs/plans/menu-bar-app.md](docs/plans/menu-bar-app.md).

### The pin file

`cheesecloth.pin` names what the app holds. Its format is set in
cheesecloth's
[docs/REPOSITORIES.md](https://github.com/jdpanderson/cheesecloth/blob/main/docs/REPOSITORIES.md#contracts).
It is TOML, in one of two forms. A commit:

```toml
commit = "<40-character commit id>"
```

CI checks out cheesecloth at that commit, builds the binary from source, and
takes the README, LICENSE, notices, docs and the local API examples from the
same checkout.

Or a release, with the SHA-256 of each macOS binary it attaches:

```toml
release = "0.4.0"
[sha256]
aarch64-apple-darwin = "<sha-256>"
x86_64-apple-darwin = "<sha-256>"
```

CI downloads `cheesecloth-<release>-<target>` from the release, and fails if
its SHA-256 is not the one in the pin. It takes the README, LICENSE, notices,
docs and the local API examples from the tag `v<release>`. Copy the SHA-256
values from the release's `SHA256SUMS` file:

```sh
gh release download v0.4.0 -R jdpanderson/cheesecloth -p SHA256SUMS -D target/
```

Before a package release, the pin must name a release. For work that spans
both repositories, change cheesecloth first and merge it, then pin that
commit here.

### Releasing

A package release names the cheesecloth release it packages plus a package
revision, such as `0.5.0-1` (the revision starts at 1 for each cheesecloth
release). It is published on this repository's releases.

1. Pin the cheesecloth release in `cheesecloth.pin`, and merge it to `main`.
2. On a Mac, install the app from the last CI run of `main` as in
   [Install](#install). Check that the menu reaches "No network" or the
   node's state, and that Quit stops the daemon (`pgrep -x cheesecloth`
   prints nothing).
3. Add a heading for the package version to CHANGELOG.md, and merge it.
4. Tag `main` and push the tag:
   `git tag v0.5.0-1 && git push origin v0.5.0-1`.

For the tag, CI checks that it is `v<pinned release>-<revision>`, runs all
the checks, and the `release` job attaches
`Cheesecloth-<package version>-macos.dmg` and a `SHA256SUMS` file. A pinned
pre-release, such as `0.5.0-beta.1`, makes a pre-release here too. Its app
shows the plain version (`0.5.0`) in Finder, since macOS allows only numbers
there; the disk image's name has the full version. The app is
signed ad hoc and not notarized; see [Weak points](#weak-points).
