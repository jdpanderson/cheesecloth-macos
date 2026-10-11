# macOS installer

A `.pkg` installer for
[cheesecloth](https://github.com/jdpanderson/cheesecloth) on macOS 14 or
later. It installs the `cheesecloth` command in `/usr/local/bin` and its docs
in `/usr/local/share/doc/cheesecloth`. It does not set up a service.

## Install

Pick the installer for your Mac from the CI run's **Artifacts**:

- `cheesecloth-<version>-macos-arm64.pkg` for Apple Silicon;
- `cheesecloth-<version>-macos-x86_64.pkg` for Intel.

Install it from a terminal:

```sh
sudo installer -pkg cheesecloth-0.3.0-macos-arm64.pkg -target /
```

Then start the daemon with `sudo cheesecloth daemon`.

A newer installer upgrades in place. Downgrades are not supported: an older
daemon may not read the state files of a newer one.

## Uninstall

```sh
sudo rm /usr/local/bin/cheesecloth
sudo rm -r /usr/local/share/doc/cheesecloth
sudo pkgutil --forget ca.janderson.cheesecloth
```

This keeps the state directory, `/Library/Application Support/cheesecloth`,
with the node's keys and cluster state; delete it to forget the node. Leave
the cluster first with `cheesecloth leave` if the node should not come back.

## Weak points

- **Not signed or notarized.** Gatekeeper blocks the installer when it is
  opened from Finder. `sudo installer` in a terminal installs it.
- **No service.** The daemon runs only while `sudo cheesecloth daemon` runs.
  It does not start at boot.
- **No uninstaller.** macOS has none for `.pkg` installers; see
  [Uninstall](#uninstall).

## Building

CI (`.github/workflows/ci.yml`) gets the pinned binary in the `binary` job
(see [the pin file](#the-pin-file)). The `installer` job then runs
`build.sh`, which builds the installer, checks the binary's architecture, and
checks the payload of the archive without installing it. The installer holds
the binary unchanged. It is not stripped, so backtraces show function names.

To build one by hand on a Mac, with a cheesecloth checkout beside this one,
at the commit or tag of the binary:

```sh
bash build.sh ../cheesecloth/target/release/cheesecloth ../cheesecloth
```

The binary must be for the Mac's own architecture. Release binaries are
built for macOS 14. If you build one yourself, set
`MACOSX_DEPLOYMENT_TARGET=14.0`, as CI does.

### The pin file

`cheesecloth.pin` names what the installer packages. Its format is set in
cheesecloth's
[docs/REPOSITORIES.md](https://github.com/jdpanderson/cheesecloth/blob/main/docs/REPOSITORIES.md#contracts).
It is TOML, in one of two forms. A commit:

```toml
commit = "<40-character commit id>"
```

CI checks out cheesecloth at that commit, builds the binary from source, and
takes the README, LICENSE, notices and docs from the same checkout.

Or a release, with the SHA-256 of each macOS binary it attaches:

```toml
release = "0.4.0"
[sha256]
aarch64-apple-darwin = "<sha-256>"
x86_64-apple-darwin = "<sha-256>"
```

CI downloads `cheesecloth-<release>-<target>` from the release, and fails if
its SHA-256 is not the one in the pin. It takes the README, LICENSE, notices
and docs from the tag `v<release>`. Copy the SHA-256 values from the
release's `SHA256SUMS` file:

```sh
gh release download v0.4.0 -R jdpanderson/cheesecloth -p SHA256SUMS -D target/
```

Before a package release, the pin must name a release. For work that spans
both repositories, change cheesecloth first and merge it, then pin that
commit here.
