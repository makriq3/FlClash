# Changelog

This changelog covers the independent `makriq` fork starting from `v0.8.93`. Each entry is written for end users and mirrors the short release notes shown on GitHub Releases.

## v0.9.02-pre1

- Fixed Android split tunneling so profile rules from files and URLs are applied reliably again.
- Stopped external package lists from leaking unrelated app matches when the installed-app list is unavailable.
- Preserved route settings defined in the profile instead of overwriting them during runtime patching.

## v0.9.01

- Brought profile-driven Android split tunneling to a stable release.
- Added support for app lists from files, URLs, masks, regex rules, and exclusions.
- Improved updater reliability and tightened Android file and routing behavior around split tunneling.

## v0.9.01-pre9

- Stabilized the final Android split tunneling flow before the `v0.9.01` release.

## v0.9.01-pre8

- Removed extra friction around app access while keeping profile-based rules resilient.

## v0.9.01-pre7

- Aligned the installed-app permission flow with the Android system behavior.

## v0.9.01-pre6

- Kept exact split tunneling rules working even when installed-app access is unavailable.

## v0.9.01-pre5

- Added mask, regex, and exclusion support for Android split tunneling rules.

## v0.9.01-pre4

- Fixed profile switching for Android split tunneling.

## v0.9.01-pre3

- Added remote package lists and made the active profile the source of truth for Android app rules.

## v0.9.01-pre2

- Added file-backed package lists for Android split tunneling.

## v0.9.01-pre1

- Added profile-driven Android split tunneling.

## v0.9.00

- Finalized the standalone release flow and improved update-channel behavior.

## v0.9.00-pre1

- Introduced the pre-release update channel and the fork-owned release pipeline.

## v0.8.98

- Refined the Android update dialog and skip-update behavior.

## v0.8.97

- Cleaned up repository-facing documentation and branch layout for the standalone fork.

## v0.8.96

- Finished the remaining standalone branding cleanup.

## v0.8.95

- Added Android self-update support and moved the product to standalone identifiers.

## v0.8.94

- Restored correct Android routing on the hardened TUN path.

## v0.8.93

- Introduced Android VPN hardening and the initial fork-owned release pipeline.
