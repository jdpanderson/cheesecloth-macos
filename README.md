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

CI (`.github/workflows/ci.yml`) builds `cheesecloth` at the pinned commit in
the `binary` job. The `installer` job then runs `build.sh`, which builds the
installer, checks the binary's architecture, and checks the payload of the
archive without installing it.

To build one by hand on a Mac, with a cheesecloth checkout beside this one,
at the commit that built the binary:

```sh
bash build.sh ../cheesecloth/target/release/cheesecloth ../cheesecloth
```

The binary must be for the Mac's own architecture. Set
`MACOSX_DEPLOYMENT_TARGET=14.0` when you build it, as CI does, so that it
runs on macOS 14.

### The pin file

`cheesecloth.json` names the cheesecloth commit that the installer packages:

```json
{ "commit": "<full commit SHA-1>" }
```

CI checks out cheesecloth at that commit, builds the binary from source, and
takes the README, LICENSE, notices and docs from the same checkout.

When cheesecloth releases attach a binary for each target, the pin will name
a release and the SHA-256 of each binary in place of the commit, and CI will
download and check them:

```json
{ "release": "v0.4.0", "sha256": { "arm64": "<sha256>", "x86_64": "<sha256>" } }
```

CI does not read this form yet. Before a package release, the pin must name a
release. For work that spans both repositories, change cheesecloth first and
merge it, then pin that commit here.
