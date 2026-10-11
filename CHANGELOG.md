# Changelog

All notable changes to the macOS installer are listed here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). A release
names the cheesecloth version it packages plus a package revision, such as
`0.4.0-2`.

## [Unreleased]

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
