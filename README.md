<div>

[**简体中文**](README_zh_CN.md)

</div>

# FlClash

[![Downloads](https://img.shields.io/github/downloads/makriq-org/FlClash/total?style=flat-square&logo=github)](https://github.com/makriq-org/FlClash/releases/)
[![Latest Release](https://img.shields.io/github/release/makriq-org/FlClash/all.svg?style=flat-square)](https://github.com/makriq-org/FlClash/releases/)
[![License](https://img.shields.io/github/license/makriq-org/FlClash?style=flat-square)](LICENSE)

FlClash is an independent fork of the original project maintained by `makriq`. This repository is the canonical source for the product, release process, documentation, and Android privacy-focused improvements shipped by the fork.

## Overview

FlClash keeps the familiar Clash-compatible workflow across desktop and Android, while adding a release pipeline and feature set that can evolve independently from upstream.

The current focus of the fork is:

- predictable standalone releases from this repository;
- hardened Android VPN behavior for privacy-sensitive use cases;
- profile-driven Android split tunneling;
- clearer release notes and maintenance documentation.

## Highlights

- Multi-platform app for Android, Windows, macOS, and Linux
- Clash-compatible profiles and subscription workflow
- WebDAV sync support
- Built-in self-update flow for Android releases
- Android split tunneling controlled directly from profile YAML
- Additional Android VPN hardening to reduce unnecessary local exposure

## Android Focus

This fork adds an Android-only hardening layer that closes local listeners in VPN mode, avoids exposing the app through the Android system proxy path, and keeps routing behavior consistent on the hardened TUN path.

Profile-managed split tunneling supports:

- `tun.exclude-package` and `tun.include-package`
- exact package names
- file-backed package lists
- URL-backed package lists
- glob rules such as `*.example.*`
- regex rules via `re:`
- negation via `!`

The goal is to reduce what the client exposes by default. It does not claim to make VPN usage fully undetectable through public Android APIs.

## Documentation

- [Release notes index](docs/releases/README.md)
- [Changelog](CHANGELOG.md)
- [Release process](docs/releasing.md)
- [Android VPN hardening notes](docs/android-vpn-hardening.md)
- [Android split tunneling notes](docs/android-profile-split-tunneling.md)
- [Security policy](SECURITY.md)
- [Roadmap](ROADMAP.md)

## Screenshots

Desktop:
<p align="center">
  <img alt="desktop" src="snapshots/desktop.gif">
</p>

Mobile:
<p align="center">
  <img alt="mobile" src="snapshots/mobile.gif">
</p>

## Build

1. Initialize submodules:

```bash
git submodule update --init --recursive
```

2. Install `Flutter` and `Go`.

3. For Android builds, install `Android SDK` and `Android NDK`.

4. Prepare the target platform:

```bash
dart setup.dart android
dart setup.dart windows --arch amd64
dart setup.dart linux --arch amd64
dart setup.dart macos --arch arm64
```

## Release Model

- `main` is the product branch.
- Stable releases use `v*` tags.
- Pre-releases use `v*-pre*` tags.
- GitHub release notes are generated from the top section of [`CHANGELOG.md`](CHANGELOG.md).
- Longer release-specific notes live in [`docs/releases`](docs/releases/README.md).
