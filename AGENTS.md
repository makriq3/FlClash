# AGENTS.md

## Client (FlClash)

### Working Context

- Repository fork created under `makriq-org/FlClash`.
- Local repo path: `/home/max/Projects/Prod/FlClash`.
- Current upstream HEAD at inspection time: commit `672eacc` (`Update changelog`).
- Git remotes:
  - `origin` -> `https://github.com/makriq-org/FlClash.git`
  - `upstream` -> `https://github.com/chen08209/FlClash.git`

### App Architecture

- FlClash is a Flutter app with Android-specific `VpnService` code and a Go core based on `mihomo` + `sing-tun`.
- Main Android VPN entrypoint:
  - `android/service/src/main/java/com/follow/clash/service/VpnService.kt`
- TUN startup path:
  - Android `VpnService` builds the tunnel and passes the FD into Go via `Core.startTun(...)`.
  - Go TUN implementation lives in:
    - `core/tun/tun.go`
    - `core/lib.go`
- Network observation / DNS refresh lives in:
  - `android/service/src/main/java/com/follow/clash/service/modules/NetworkObserveModule.kt`

### Relevant Current Defaults

- `mixed-port` default is `7890`:
  - `lib/models/clash_config.dart`
- `socks-port` default is `0`, but the active Android `VpnOptions.port` is derived from `mixed-port`:
  - `lib/providers/state.dart`
- `VpnProps.systemProxy` default is `true`:
  - `lib/models/config.dart`
- `VpnProps.allowBypass` default is `true`:
  - `lib/models/config.dart`
- `VpnProps.dnsHijacking` default is `false`:
  - `lib/models/config.dart`
- `external-controller` default is closed (`''`), and explicit open state is `127.0.0.1:9090`:
  - `lib/enum/enum.dart`
  - `lib/models/clash_config.dart`

### Confirmed Detection / Leak Surface In Current Code

- Android `VpnService` is always used when VPN mode is enabled:
  - `android/service/.../VpnService.kt`
- `VpnService` currently exposes stable, fingerprintable values:
  - session name: `FlClash`
  - IPv4 tunnel address: `172.19.0.1/30`
  - IPv4 DNS advertised to system: `172.19.0.2`
  - IPv6 tunnel address: `fdfe:dcba:9876::1/126`
  - IPv6 DNS advertised to system: `fdfe:dcba:9876::2`
- On Android 10+ (`API 29+`) FlClash can publish a system HTTP proxy pointing to `127.0.0.1:<mixed-port>` when `systemProxy=true`:
  - `android/service/.../VpnService.kt`
- The Go core recreates inbound listeners for HTTP / SOCKS / mixed / redir / tproxy according to config:
  - `core/common.go`
- Because `mixed-port` defaults to `7890`, current Android flow effectively keeps a localhost mixed proxy available unless user changes config.
- `mixed-port` in mihomo supports both HTTP and SOCKS5 on one port. This means a localhost leak is still possible even with `socks-port=0`.
- FlClash itself globally routes many app HTTP requests through the local mixed proxy via `HttpOverrides`:
  - `lib/main.dart`
  - `lib/common/http.dart`
  - `lib/common/request.dart`
- Consequence:
  - enabling proxy auth on localhost is not a drop-in fix by itself;
  - the app must either learn to authenticate to its own local proxy, or Android TUN mode must stop depending on that local mixed proxy path.

### External Evidence Collected

- Upstream FlClash issue `#1934` opened on `2026-04-08`:
  - title: `[SECURITY] Critical vulnerability: SOCKS5 localhost proxy bypass allows discovery of outbound IP`
  - repo: `chen08209/FlClash`
- The issue discussion points to a practical mitigation direction:
  - secure-by-default auth for local proxy, or
  - disabling local SOCKS/mixed inbound when TUN mode is active.
- Official mihomo docs confirm:
  - `mixed-port` supports both HTTP and SOCKS.
  - global `authentication:` can protect `http`, `socks`, and `mixed` proxies.
  - `skip-auth-prefixes` can exclude ranges like `127.0.0.1/8`, so it must be handled carefully for localhost hardening.

### Research On Detection Tools

- `NoVPNDetect` is an Xposed module. It does not fix the VPN client itself; it hooks Android APIs seen by other apps.
- In inspected code, `NoVPNDetect` hooks and falsifies:
  - `NetworkCapabilities.hasTransport(TRANSPORT_VPN)`
  - `NetworkCapabilities.hasCapability(NET_CAPABILITY_NOT_VPN)`
  - `NetworkCapabilities.getCapabilities()`
  - `NetworkInterface.getName()`
  - `NetworkInterface.getByName()`
  - `NetworkInterface.isUp()`
  - `NetworkInterface.isVirtual()`
- Practical meaning:
  - Some app-visible VPN signs cannot be removed by FlClash alone.
  - Those signs require root/Xposed/LSPosed-style API hiding on the device.

- `YourVPNDead` is a detector app focused on practical app-visible leak paths.
- Inspected checks include:
  - `NetworkCapabilities.TRANSPORT_VPN`
  - `NetworkCapabilities.NET_CAPABILITY_NOT_VPN`
  - `System.getProperty("http.proxyHost" / "socksProxyHost")`
  - `NetworkInterface` enumeration for `tun*`, `wg*`, `ppp*`, etc.
  - `/proc/net/route`
  - `ConnectivityManager.getLinkProperties(...).dnsServers`
  - localhost port scans on `127.0.0.1` and `::1`
  - `/proc/net/tcp*` and `/proc/net/udp*`
  - SOCKS5 handshake probing
  - Clash API probing on `9090` / `19090`
  - exit IP extraction through unauthenticated localhost proxy

### What FlClash Can Realistically Fix By Itself

- Close or harden localhost inbound proxy exposure in Android VPN mode.
- Make safer defaults so users are not vulnerable out of the box.
- Potentially reduce obvious fingerprinting from static session / address / DNS values where platform constraints allow it.
- Add a dedicated hardened / stealth mode so subscription updates do not silently undo safety-critical local settings.
- Improve verification workflow so one build can validate several hypotheses at once.

### What FlClash Cannot Fully Fix By Itself

- Android reporting VPN transport via `NetworkCapabilities`.
- Absence of `NET_CAPABILITY_NOT_VPN` on the active VPN network.

### Update Dialog Simplification (2026-04-13)

- Текущий обработчик обновлений жил в `lib/controller.dart` на основе `globalState.showMessage(...)` с двумя действиями.
- Отказ от релиза при автообновлении раньше отключал `autoCheckUpdate` глобально, что создавало неочевидное поведение.
- Новая продуктовая логика обновления для Android:
  - `Позже` закрывает окно без побочных эффектов.
  - `Пропустить релиз` сохраняет пропуск только для текущего `tagName` релиза в `SharedPreferences`.
  - `Скачать и установить` очищает пропуск и запускает существующий Android self-update pipeline.
- Для хранения пропущенного релиза используется отдельный ключ `skippedReleaseTag` в `lib/common/preferences.dart`.
- Ручная проверка обновлений должна игнорировать сохранённый пропуск и всё равно показывать релиз пользователю.
- Visibility of TUN-style interfaces and some route / MTU / DNS signs to apps using public Android APIs.
- These require device-side root hooking / API hiding tools such as Xposed/LSPosed modules.

### Initial Priority Assessment

1. Highest priority:
   - localhost mixed/http/socks exposure and any auth-less inbound reachable by other apps.
2. High priority:
   - system proxy visibility (`127.0.0.1:<port>`) when not strictly required.
3. Medium priority:
   - stable static identifiers (`FlClash`, tunnel addresses, tunnel DNS) that can aid heuristics.
4. Out of scope for client-only fix:
   - direct Android VPN API detection without root hooks.

### Build / CI Notes

- Existing GitHub Actions workflow in this repo builds Android artifacts, but currently triggers on tag push (`v*`) rather than branch push / manual testing flow.
- For fast iteration in fork `makriq-org/FlClash`, a dedicated Android test/build workflow will likely be needed so heavy builds happen in GitHub Actions without local machine load.
- Because the risk here is mostly runtime behavior, validation should combine:
  - code-level assertions for generated config / safe defaults,
  - CI-built APK artifacts,
  - one batched manual device run against detector apps instead of repeated per-edit installs.

### Validation Direction

- Avoid repeated manual APK installs by batching fixes and validating them against a fixed checklist:
  - no localhost leak through mixed / socks / http
  - no unexpected external controller exposure
  - expected behavior in TUN mode
  - explicit comparison against detector apps (`YourVPNDead`, `NoVPNDetect` where applicable)
- Important constraint:
  - a "clean" result in detector apps is only partially achievable by client changes alone;
  - full "no detect" for Android usually requires FlClash hardening plus root/Xposed masking.

### Implemented Hardening In This Fork

- Added Android-only runtime hardening for VPN mode:
  - force-close localhost listeners in generated Clash config:
    - `port=0`
    - `socks-port=0`
    - `mixed-port=0`
    - `redir-port=0`
    - `tproxy-port=0`
  - force `external-controller=''`
  - force `allow-lan=false`
- Added Android-only VPN option hardening:
  - force `systemProxy=false`
  - force `allowBypass=false`
  - clear `bypassDomain`
  - force local proxy port in `VpnOptions` to `0`
- Added Android request-path hardening:
  - app-owned HTTP traffic no longer routes through localhost mixed proxy while Android VPN mode is active.
  - this prevents the app from depending on the same localhost listener surface we are trying to close.
- Added Android-side fingerprint reduction in `VpnService`:
  - randomized per-start IPv4/IPv6 tunnel addressing instead of static `172.19.0.1/30` and `fdfe:dcba:9876::/126`
  - generic session name `VPN` instead of `FlClash`
- Added regression coverage:
  - `test/common/android_vpn_hardening_test.dart`
- Added branch/manual Android GitHub Actions workflow for the fork:
  - `.github/workflows/android-branch-build.yml`

### Android Routing Regression Investigation (2026-04-12)

- Upstream security issue confirmed:
  - `chen08209/FlClash` issue `#1934`
  - title: `[SECURITY] Critical vulnerability: SOCKS5 localhost proxy bypass allows discovery of outbound IP`
  - opened on `2026-04-07`
- The Android hardening release in this fork is commit:
  - `b8abc74` (`Prepare hardened fork release v0.8.93`)
- Security hardening did change:
  - generated Clash patch config for Android VPN mode
  - app-local HTTP proxy usage
  - Android `VpnService` tunnel identity values
- Security hardening did **not** change:
  - Android `protect()` bridge wiring into Go core
  - Go TUN startup hook that applies socket protection for direct outbound connections
  - rule list generation in `makeRealProfileTask(...)`

### Confirmed Route Handling Split

- There are two separate routing layers in the Android flow:
  - generated Clash core config (`tun.route-address`, rules, DNS, etc.)
  - Android `VpnService.Builder.addRoute(...)` decisions from `VpnOptions.routeAddress`
- The generated Clash config still preserves the resolved TUN route list:
  - `lib/controller.dart` computes `patchConfig.tun.getRealTun(routeMode)`
  - `lib/common/task.dart` writes it into raw config as `rawConfig['tun']['route-address']`
- `Tun.getRealTun(RouteMode routeMode)` resolves:
  - `RouteMode.config` -> user config `tun.route-address`
  - `RouteMode.bypassPrivate` -> `defaultBypassPrivateRouteAddress`

### Subscription Deep Link + Auto Update Research (2026-04-13)

- Android app already declares a custom-scheme deep link on `MainActivity`:
  - file: `android/app/src/main/AndroidManifest.xml`
  - activity is `android:exported="true"` and `android:launchMode="singleTop"`
  - deep-link intent filter:
    - action: `android.intent.action.VIEW`
    - categories: `DEFAULT`, `BROWSABLE`
    - schemes: `clash`, `clashmeta`, `flclash`
    - host: `install-config`
- Current in-app deep-link parser:
  - file: `lib/common/link.dart`
  - listens via `app_links`
  - accepts only links where `uri.host == 'install-config'`
  - expects query parameter `url`
  - current effective link shape is:
    - `flclash://install-config?url=<percent-encoded-config-url>`
    - same parser also accepts `clash://...` and `clashmeta://...`
- Current app behavior after link reception:
  - file: `lib/controller.dart`
  - `initLink()` subscribes to `linkManager.initAppLinksListen(...)`
  - after a link arrives, the app shows a confirmation dialog first
  - only after user confirms, it calls `addProfileFormURL(url)`
- Current profile creation path for URL subscriptions:
  - file: `lib/controller.dart`
  - `addProfileFormURL(String url)`:
    - pops to root page
    - navigates to Profiles
    - creates a new profile with `Profile.normal(url: url).update()`
    - saves it with `putProfile(profile)`
- Important UX/product gaps for the requested "tap link and subscription is added immediately" flow:
  - the confirmation dialog is the main extra user step and must be removed or bypassed for trusted install links
  - current flow appears to create a fresh profile on every accepted link tap; there is no existing deduplication by subscription URL
  - current link integration only subscribes to `uriLinkStream`; there is no explicit `getInitialLink()` handling in app code
  - `app_links` documentation says the plugin should be instantiated early to catch the first cold-start link; current app initializes link listening only after Flutter app attach / first frame in `lib/application.dart`
- `app_links` reference checked:
  - package docs expose `uriLinkStream`, `getInitialLink()`, and `getLatestLink()`
  - docs explicitly recommend instantiating `AppLinks` early to catch the very first cold-state link
- Current default auto-update interval for new URL profiles:
  - file: `lib/common/constant.dart`
  - `defaultUpdateDuration = Duration(days: 1)`
  - file: `lib/models/profile.dart`
  - `Profile.normal(...)` uses `defaultUpdateDuration`
- Persistence details for auto-update:
  - file: `lib/database/profiles.dart`
  - each profile stores concrete `autoUpdateDurationMillis` in DB
  - changing `defaultUpdateDuration` will affect newly created profiles, not already saved ones
- Current edit UI for subscriptions:
  - file: `lib/views/profiles/edit.dart`
  - interval is shown/edited in minutes via `profile.autoUpdateDuration.inMinutes`
  - no extra migration logic exists for old values
- Existing CI path suitable for remote validation through GitHub Actions on `makriq-org/FlClash`:
  - file: `.github/workflows/android-branch-build.yml`
  - triggers on `workflow_dispatch` and pushes to `main`, `codex/**`, `feature/**`, `fix/**`
  - runs `flutter test test/common`
  - builds Android artifacts via `dart setup.dart android`
  - uploads artifacts from `dist/`
  - if the final list is empty on mobile, `auto-route=true`; otherwise `auto-route=false`

### Confirmed Android Service Gap

- `VpnOptions` includes `routeAddress` on both Flutter and Android sides:
  - Flutter: `lib/models/core.dart`
  - Android parcelable: `android/service/.../VpnOptions.kt`
- Android `VpnService` explicitly relies on `options.routeAddress`:
  - if non-empty, it adds only those routes
  - if empty, it falls back to `addRoute(0.0.0.0, 0)` and `addRoute(::, 0)`
- Current `SharedState` construction does **not** populate `VpnOptions.routeAddress`:

### Update Mechanism Research (2026-04-12)

- Current app update UX is only a release check plus external redirect:
  - release check hits `https://api.github.com/repos/$repository/releases/latest`
  - source: `lib/common/request.dart`
  - user flow shows a dialog with release notes, then opens `https://github.com/$repository/releases/latest`
  - source: `lib/controller.dart`
  - manual entry point exists in About screen:
    - `lib/views/about.dart`
- Current release source inside code is still **upstream**, not the fork:
  - `const repository = 'chen08209/FlClash'`
  - source: `lib/common/constant.dart`
- Consequence:
  - this fork already has its own release channel, but the app still looks at upstream releases.
  - current fork users will not get correct fork updates until the release source is switched or abstracted.

- Verified live release state at research time:
  - fork `makriq-org/FlClash` latest release:
    - tag: `v0.8.93`
    - published: `2026-04-12`
    - release page: `https://github.com/makriq-org/FlClash/releases/tag/v0.8.93`
  - upstream `chen08209/FlClash` latest release:
    - tag: `v0.8.92`
    - published: `2026-02-02`
    - release page: `https://github.com/chen08209/FlClash/releases/tag/v0.8.92`
- Practical implication:
  - the fork is already newer than upstream.
  - keeping the hardcoded upstream repository breaks any future user-facing update story for this fork.

- Android release artifacts are already suitable for ABI-aware self-update:
  - Android packaging is split per ABI via `split-per-abi`.
  - source: `setup.dart`
  - current release assets include:
    - `FlClash-<version>-android-arm64-v8a.apk`
    - `FlClash-<version>-android-armeabi-v7a.apk`
    - `FlClash-<version>-android-x86_64.apk`
    - matching `.sha256` files
  - fork release page currently exposes `Assets 24`, so Android APKs and checksum files are already part of the existing release pipeline.

- CI / release pipeline facts relevant to updates:
  - stable multi-platform releases are created only from tag push `v*`:
    - `.github/workflows/build.yaml`
  - the workflow already computes and uploads `.sha256` files for release assets.
  - branch/manual Android verification exists separately:
    - `.github/workflows/android-branch-build.yml`
  - this matches the desired workflow of:
    - heavy build in GitHub Actions,
    - single batched APK verification on device.

- Android app install support is **not implemented yet**:
  - Flutter side already declares:
    - `app.openFile(path)`
    - `app.requestNotificationsPermission()`
    - source: `lib/plugins/app.dart`
  - Android `AppPlugin` method channel currently handles:
    - `moveTaskToBack`
    - `updateExcludeFromRecents`
    - `initShortcuts`
    - `getPackages`
    - `getChinaPackageNames`
    - `getPackageIcon`
    - `tip`
  - It does **not** handle:
    - `openFile`
    - `requestNotificationsPermission` as a direct Flutter method call
  - source: `android/app/src/main/kotlin/com/follow/clash/plugins/AppPlugin.kt`
- Consequence:
  - even a basic "download APK and open installer" flow is currently missing in Android native code.

- Android manifest is not yet prepared for robust in-app APK install flow:
  - current manifest has no `REQUEST_INSTALL_PACKAGES` permission.
  - current manifest has no `FileProvider`.
  - no provider XML path config was found.
  - source: `android/app/src/main/AndroidManifest.xml`
- Consequence:
  - safe installer launch through `content://` URI is not wired yet.
  - unknown-app-source permission flow is not wired yet.

- Official Android platform constraints for non-Play self-update:
  - Android allows releasing APKs from a website / direct link, including own server or GitHub-style distribution.
  - users must opt in to installs from unknown sources.
  - on Android 8.0+ this permission is granted per-source app.
  - sources that install unknown apps should check `canRequestPackageInstalls()`.
  - Android docs reference:
    - `Publish your app`
    - `PackageManager.canRequestPackageInstalls()`
- This means:
  - a good GitHub-release updater is feasible,
  - but first install and sometimes re-enabled permission will still require a system permission screen.

- Official Android platform constraints for accepted app updates:
  - update must keep the same `applicationId`.
  - update must keep the same signing certificate, or valid proof-of-rotation.
  - update must have same-or-higher `versionCode`.
  - Android docs reference:
    - `How app updates work`
- Repository-specific implication:
  - release signing key stability is mandatory for seamless updates in this fork.
  - if release signing secrets are absent, current Gradle config falls back to debug signing and adds `.dev` applicationId suffix even for release build:
    - source: `android/app/build.gradle.kts`
  - such builds are fine for test artifacts, but they are **not** valid upgrade targets for production users.

- Google Play in-app updates are not the right primary mechanism for the current distribution model:
  - Play can update only apps published on Google Play, with matching app id / signing, and present in the user's library.
  - current FlClash fork distribution is GitHub Releases, not Play.
  - so the realistic mechanism here is a fork-owned self-updater based on GitHub Releases, not Play Core.

- Existing app capabilities that help implement a good updater:
  - `device_info_plus` is already included, so ABI / SDK-aware asset selection can be implemented without adding a new heavy dependency.
  - `dio` is already included and suitable for download with progress.
  - app paths already expose:
    - downloads directory
    - temporary directory
    - cache directory
  - sources:
    - `lib/common/system.dart`
    - `lib/common/path.dart`

- Recommended product direction based on current facts:
  - Android update UX should become:
    - app checks fork release channel,
    - app selects correct APK for current ABI,
    - app downloads inside the app with progress,
    - app verifies checksum,
    - app opens system installer,
    - app guides user only when Android requires unknown-source permission.
  - This removes:
    - manual GitHub browsing,
    - platform selection by the user,
    - checksum ambiguity,
    - most chances to install the wrong asset.
  - Remaining unavoidable user action:
  - final confirmation in Android package installer,
  - and one-time / occasional unknown-source permission grant on Android 8+.

### Implemented Android Self-Update Direction (2026-04-12)

- The client is now being reoriented to the fork release channel:
  - `repository` should point to `makriq-org/FlClash`, not upstream.
  - this affects:
    - update checks
    - About -> Project link
    - release page fallback links

- The intended Android update flow in this fork is:
  - check latest fork release through GitHub API
  - detect current device ABI on Android
  - select the matching split APK asset automatically
  - download APK in-app
  - verify SHA-256 before install
  - launch Android package installer directly from the app
  - fall back to the release page only on failure

- Artifact selection rules:
  - use release assets already produced by `split-per-abi`
  - prefer ABI in the device-reported order from `supportedAbis`
  - current expected asset names include:
    - `arm64-v8a`
    - `armeabi-v7a`
    - `x86_64`
  - if no compatible APK is found, surface a user-facing error instead of asking the user to choose manually

- Integrity verification rules:
  - prefer GitHub release asset `digest` when available
  - otherwise fetch the matching `.apk.sha256` sidecar asset
  - verify the downloaded APK before invoking the installer
  - keep the downloaded APK in app cache so the user does not need to redownload on every retry

- Android native integration needed for this mechanism:
  - `REQUEST_INSTALL_PACKAGES` in manifest
  - `FileProvider` in manifest
  - XML provider paths for cache/files download handoff
  - Flutter method-channel handler for `openFile(path)` on Android
  - APK-specific launch path should use the Android package installer rather than plain browser redirect

- CI / release assumptions for the updater to remain valid:
  - stable Android releases must always be signed with the fork release key
  - unsigned / debug-signed artifacts are acceptable only for branch testing, not for production updates
  - branch GitHub Actions builds should use signing secrets when available so device validation artifacts stay representative of real upgrade builds

- Validation target for this feature:
  - no manual ABI/platform selection by the user
  - no need to browse GitHub releases manually during normal upgrade
  - one in-app flow should cover:
    - discovery
    - download
    - checksum verification
    - installer handoff
  - remaining user action is only the unavoidable Android system install confirmation / unknown-source approval

- First CI failure during self-update implementation:
  - branch workflow run `24305718946` failed in `Run Android Regression Tests`
  - failure cause was not updater logic itself, but compile mismatches in the new dialog:
    - missing import for `TrafficShowExt` from `lib/models/common.dart`
    - missing import for `CommonDialog` from `lib/widgets/dialog.dart`
    - used nonexistent localization key `close` instead of existing `cancel`
  - fix was applied directly in `lib/widgets/update_dialog.dart` before rerunning Actions
  - `lib/providers/state.dart` builds `VpnOptions(...)` without `routeAddress`

### Standalone Product Rebrand And Release Independence (2026-04-12)

- The fork is now being converted from "privacy fork with upstream-era identifiers" into a standalone release line owned by `makriq`.
- Product identifier changes applied:
  - Android app / module namespace moved from `com.follow.clash` to `com.makriq.flclash`
  - macOS bundle identifiers moved to `com.makriq.flclash`
  - Linux desktop application id moved to `com.makriq.flclash`
  - Dart-side `packageName` constant now matches the new namespace
- Android source migration was not just `applicationId`:
  - Kotlin package declarations had to move under new filesystem paths in:
    - `android/app`
    - `android/common`
    - `android/core`
    - `android/service`
  - AIDL package paths also had to be moved to `com/makriq/flclash/...`
- Release independence findings:
  - old Android release flow still depended on Firebase / `google-services.json`
  - after package rename, that would have blocked stable tagged releases unless a new Firebase app was provisioned
  - to keep releases self-owned and immediately operable, Firebase / Crashlytics integration was removed from Android Gradle and CI setup
  - stable Android release now depends only on keystore + signing credentials, not on `SERVICE_JSON`
- User-facing upstream traces removed from product surface:
  - About screen no longer links to upstream Telegram / upstream core page
  - packaging metadata now publishes under `makriq`
  - release helper URLs point to `makriq-org/FlClash`
  - public README files now describe the repo as an independent release line rather than an upstream-facing fork
- Dependency independence improvement:
  - `flutter_js` and `yaml_writer` were moved from upstream-owned GitHub git refs to neutral `pub.dev` packages
- Verification:
  - branch run `24313374852` (`Rebrand app identifiers for standalone release`) passed
  - result:
    - `Run Android Regression Tests` passed
    - `Build Android Artifacts` passed
    - `Upload Android Artifact` passed
  - this validates:
    - new namespace/package migration,
    - removal of Firebase release coupling,
    - updated dependency sources,
    - continued branch Android build viability in GitHub Actions
  - Practical consequence:
  - Android service receives an empty route list even when final Clash config contains a non-empty `tun.route-address`
  - system VPN routing and core TUN config can therefore diverge

### Historical Note

- This `routeAddress` omission predates the hardening commit:
  - `b8abc74` kept building `VpnOptions` without `routeAddress`
  - so the bug may be older than the security fix and only became visible after hardening changed the traffic path / test conditions

### Current Working Hypothesis

- Strong hypothesis:
  - Android-side routing regression is caused by `VpnOptions.routeAddress` not being synchronized with the resolved `tun.route-address`
  - because of that, `VpnService` installs full-capture routes even when config expects a narrower route set
- Still not fully proven:
  - whether the user-visible `RU via VPN` symptom comes entirely from this route divergence
  - or whether there is a second issue in direct-outbound handling for Clash `DIRECT` rules
- Important distinction:
  - the generated Clash config itself still appears to preserve rules and `tun.route-address`
  - the strongest confirmed mismatch is between generated core config and Android `VpnService` route installation

### Refined Regression Hypothesis After User Reproduction Note

- User-reported behavior:
  - with the same practical config, `2ip.ru` went direct before the fork
  - after the fork / hardening release, `2ip.ru` goes through VPN
- This makes a pure "old hidden bug" explanation less likely as the primary cause.
- Stronger fork-specific regression candidate:
  - before the fork, Android path preserved `systemProxy=true` and non-empty `bypassDomain`
  - after the fork, Android defaults and runtime hardening now force:
    - `systemProxy=false`
    - `allowBypass=false`
    - `bypassDomain=[]`
    - `port=0`
- Evidence:
  - upstream/default Android settings previously inherited normal defaults
  - fork now overrides Android defaults in `lib/providers/config.dart`
  - fork also force-overrides active `VpnOptions` in `lib/common/android_vpn_hardening.dart`
  - Android `VpnService` uses `bypassDomain` only when `systemProxy=true` through `ProxyInfo.buildDirectProxy(...)`
- Practical meaning:
  - if the observed "RU direct" behavior depended on Android system proxy bypass domains rather than Clash rule evaluation inside TUN, the fork would break it immediately even with the same visible profile config
- Current best explanation ranking:
  1. most likely:
     - fork hardening removed Android `systemProxy` + localhost mixed-proxy path that previously let browser/app traffic reach Clash as proxy traffic instead of only raw TUN traffic
     - if user routing relied on Android proxy bypass domains or on domain-based Clash rules that worked better on the proxy path, this would immediately regress after hardening
  2. still possible / secondary:
     - missing `VpnOptions.routeAddress` causes route divergence between Android `VpnService` and generated Clash config
  3. less likely but not excluded:
     - an additional regression in direct-outbound handling for Clash `DIRECT` rules inside Android TUN

### Reproduced Mechanism

- The core routing failure is now reproduced at rule-matching level against local `mihomo` packages in a temporary Go module:
  - a `DOMAIN-SUFFIX,ru,DIRECT` rule matches `Metadata{Host: "2ip.ru"}`
  - the same rule does **not** match IP-only metadata (`Metadata{DstIP: ...}`)
- This confirms the practical regression mechanism:
  - before hardening, Android browser/app traffic could arrive through the localhost proxy path with domain metadata preserved
  - after hardening, traffic is forced onto raw TUN and can become IP-only unless domain recovery is explicitly enabled
  - in that state, domain-based rules such as `DOMAIN*`, `GEOSITE`, and many rule-set based direct routes can silently stop matching
- Conclusion:
  - `routeAddress` was a real bug and still needed fixing
  - but the user-visible `2ip.ru -> VPN` regression is better explained by loss of domain-aware matching after hardening removed the proxy path

### Implemented Follow-Up Fixes (Pending CI Verification)

- Kept Android-safe TUN route synchronization:
  - `SharedState.vpnOptions.routeAddress` is derived from the same resolved TUN config logic as profile generation
  - this still closes the confirmed route mismatch between Flutter-side config generation and Android `VpnService`
- Refined the Android routing fix after failed manual validation:
  - removed fork-specific Android default overrides from `VpnSetting`, `NetworkSetting`, and `PatchClashConfig`
  - hardening remains runtime-only in active Android VPN mode instead of rewriting the app's baseline defaults
- Strengthened Android VPN profile compatibility so it no longer depends on `requestedSystemProxy=true`:
  - whenever hardened Android VPN mode is active, profile generation now:
    - translates compatible `bypassDomain` entries into top-priority `DIRECT` Clash rules
    - always enables / augments `sniffer` for `http`, `tls`, and `quic`
- Rationale:
  - the previous compatibility attempt could stay inert if forked Android defaults had already forced `systemProxy=false`
  - always-on domain recovery is safer for the hardened TUN-only path and directly targets the reproduced loss of host metadata

### Follow-Up Security Regression Found After Device Validation

- After restoring normal Android defaults, a localhost exposure regression reappeared.
- Root cause:
  - profile generation was still hardened correctly during setup
  - but runtime live updates use `updateParamsProvider -> coreController.updateConfig(...)`
  - that path was still sending unhardened `patchClashConfig` values such as `mixedPort: 7890`
  - as a result, Android VPN mode could start from a hardened profile and then reopen local listeners during the next runtime config sync
- Fix direction:
  - unify Android runtime hardening for both setup/profile generation and live `updateConfig` updates through one shared helper
  - keep UI defaults normal, but apply hardening consistently whenever Android VPN mode is actually active

### Verification Status

- Local Flutter/Dart test execution is not available in the current workstation environment:
  - `flutter`, `dart`, `fvm`, and `melos` are absent from `PATH`
- Existing branch workflow suitable for remote verification:
  - `.github/workflows/android-branch-build.yml`
  - it already runs `flutter test test/common/android_vpn_hardening_test.dart`
  - and builds Android artifacts in GitHub Actions on branch push / manual dispatch
- Anti-regression coverage was extended for the highest-risk follow-up scenarios:
  - Android runtime hardening with `RouteMode.bypassPrivate`
  - ensuring runtime config remains untouched when Android hardening is inactive
  - preserving explicit existing `sniffer` settings while still enforcing domain recovery in hardened Android VPN mode

### Release Packaging Notes

- This fix set is being prepared as release `v0.8.94`.
- Release narrative:
  - keep the localhost leak closed,
  - restore correct Android direct routing on the hardened TUN path,
  - ensure live runtime config updates cannot silently reopen listeners after startup.
- Public-facing docs updated for this release:
  - `CHANGELOG.md`
  - `docs/android-vpn-hardening.md`
  - `README.md`
- Release workflow fan-out observed after merge/tag push:
  - `android-branch-build` ran for the last two branch commits on `codex/android-routing-regression-fix`,
  - another `android-branch-build` ran on `main` after merge,
  - `build` ran for tag `v0.8.94`.
- The branch-only in-progress runs that were not needed after merge were explicitly cancelled:
  - Actions run `24304867441` (`Prepare v0.8.94 release notes`)
  - Actions run `24304783943` (`Expand Android hardening regression coverage`)
- The intended runs to keep after release are:
  - `android-branch-build` on `main`
  - `build` for release tag `v0.8.94`

### Production Cleanup Follow-Up And Runtime Namespace Risk (2026-04-12)

- After the standalone rebrand landed, one more Android runtime risk was identified before the next release:
  - `android/core/src/main/cpp/core.cpp` still exported JNI symbols under `Java_com_follow_clash_core_Core_*`
  - Java/Kotlin packages had already moved to `com.makriq.flclash.core`
  - build validation could still pass because the native library compiles, but Android runtime native method binding would fail once the renamed `Core` class invoked those methods
- Fixes applied for the production release line:
  - updated all native JNI export names in `android/core/src/main/cpp/core.cpp` to `Java_com_makriq_flclash_core_Core_*`
  - updated `JNI_OnLoad` class lookups from `com/follow/clash/core/*` to `com/makriq/flclash/core/*`
  - removed the last old Windows vendor metadata from `windows/runner/Runner.rc` (`CompanyName`, `InternalName`, `ProductName`, copyright)
  - removed now-unused Firebase entries from `android/gradle/libs.versions.toml` after the product line was decoupled from Google Services
  - normalized leftover user-facing localization strings so product text no longer references Firebase Crashlytics directly
- Verification notes:
  - repo-wide search outside `AGENTS.md` no longer returns `com.follow`, `chen08209/FlClash`, `follow/clash`, or `Firebase Crashlytics`
  - local Flutter/Dart execution is still unavailable in the workstation environment, so release verification continues through GitHub Actions
- Release signing follow-up:
  - first post-cleanup `android-branch-build` run on `main` failed during `Build Android Artifacts` even though tests were green
  - root cause was repository secret mismatch for the Android release keystore:
    - Gradle reported `keystore password was incorrect`
    - the fork uses a PKCS12 keystore, and `KEY_PASSWORD` needed to match `STORE_PASSWORD` for this signing setup
  - repository secrets were re-uploaded from the local keystore backup with aligned values:
    - `KEYSTORE`
    - `KEY_ALIAS`
    - `STORE_PASSWORD`
    - `KEY_PASSWORD`
- Final verification before release:
  - `android-branch-build` run `24313864713`, attempt `2`, completed successfully on commit `a565f2d`
  - the successful run covered:
    - Android signing setup
    - Android regression tests
    - full Android artifact build
    - artifact upload
- Release intent updated:
  - supersede failed `v0.8.95` with `v0.8.96` after production cleanup and runtime namespace correction

### Branch Cleanup And Release Channel Simplification (2026-04-13)

- Repository state after `v0.8.96` verification:
  - `main` is the default branch on `makriq-org/FlClash`
  - `latestRelease` on GitHub is `v0.8.96`
  - fork still had extra remote branches:
    - `codex/android-self-update`
    - `codex/prod-rebrand-release`
    - `dev`
    - `release/v0.8.91`
    - `release/v0.8.92`
- Branch ancestry check:
  - both `codex/*` branches had no commits missing from `main`
  - `dev` and `release/*` were confirmed as upstream-derived history and are not part of the maintained fork release line
- Cleanup direction:
  - keep `origin/main` as the single maintained branch for the fork
  - delete stale fork branches on `origin`
  - remove local `upstream` remote after upstream traces are no longer needed operationally
- Cleanup completed:
  - deleted remote branches:
    - `codex/android-self-update`
    - `codex/prod-rebrand-release`
    - `dev`
    - `release/v0.8.91`
    - `release/v0.8.92`
  - deleted matching local `codex/*` branches
  - removed local Git remote `upstream`
  - resulting branch layout is now:
    - `origin/main`
- Release follow-up:
  - bump app version to `0.8.97+2026041301`
  - cut the next release from cleaned `main` after branch cleanup

### Repository Russification And Release Reset (2026-04-13)

- Release control update:
  - user explicitly stopped the first `v0.8.97` release attempt because the delta was too small for a production tag
  - canceled GitHub Actions run:
    - `24329018459`
  - deleted tag:
    - `v0.8.97`
  - confirmed no GitHub Release object remained for `v0.8.97` after the cancel / tag removal sequence
- Russification scope chosen for this pass:
  - translate the first-party public repository surface to Russian before recutting the release
  - include:
    - `README.md`
    - `ROADMAP.md`
    - `SECURITY.md`
    - `CHANGELOG.md`
    - `docs/android-vpn-hardening.md`
    - GitHub issue templates
    - GitHub release template
    - GitHub Actions workflow display names and step labels
    - repository description on GitHub
    - package description in `pubspec.yaml`
  - keep vendor / third-party content out of scope:
    - `core/Clash.Meta`
  - keep `README_zh_CN.md`, but convert it into a Russian compatibility pointer to the main Russian docs so old links do not break
- GitHub metadata update:
  - repository description is now:
    - `Независимый форк FlClash с упором на защиту Android VPN и автономные релизы.`
- Release strategy after russification:
  - push the documentation / metadata pass to `main`
  - use the branch Android Actions workflow on `main` as the pre-release verification gate
  - only after a green branch build, recreate tag `v0.8.97` from the verified `main`

### Release Notes Formatting Follow-Up (2026-04-13)

- User feedback on `v0.8.97`:
  - the release page looked like a short README / policy text instead of concise release notes
  - the `v0.8.97` changelog wording also read like instructions rather than completed changes
- Root cause:
  - release workflow prepended `.github/release_template.md` before the actual changelog excerpt
  - the template itself was written as a generic repository description
- Fix direction:
  - make the template a short footer with only practical release links
  - generate release body in this order:
    - title
    - changelog excerpt for the tag
    - short footer
  - rewrite `v0.8.97` changelog entry in release-note style
  - update the already published `v0.8.97` body in place so users do not keep seeing the bad format

### Android Connectivity Regression After Update-System Rollout (2026-04-13)

- User-reported symptom to investigate:
  - after the recent update-system work, Android no longer connects to any server
  - even the dashboard current IP / direct IP widget does not resolve and stays in loading state
- Most relevant regression window in fork history:
  - last clearly pre-update tag: `v0.8.96` (`5cc0654`, 2026-04-12)
  - update-system introduction: `5cd063d` (`Add Android self-update flow`, 2026-04-12)
  - adjacent Android namespace / runtime churn:
    - `7996e3b` (`Rebrand app identifiers for standalone release`, 2026-04-12)
    - `a565f2d` (`Finalize production rebrand cleanup`, 2026-04-12)
  - latest UI-only refinement on top:
    - `ec0f8d1` (`Refine Android update dialog`, 2026-04-13)
- Confirmed startup / update facts from current code:
  - `AppController._init()` calls `autoCheckUpdate()` very early and **without `await`**
  - this happens before:
    - `_connectCore()`
    - `_initCore()`
    - `_initStatus()`
  - file: `lib/controller.dart`
  - current auto-update path does:
    - GitHub `releases/latest` request against `makriq-org/FlClash`
    - release dialog rendering
    - on Android, APK download / checksum verification / installer launch
  - files:
    - `lib/common/request.dart`
    - `lib/common/update.dart`
    - `lib/widgets/update_dialog.dart`
- Important negative finding:
  - the self-update commits do **not** directly change:
    - Android TUN startup
    - profile generation / `applyProfile(...)`
    - proxy group fetch via `coreController.getProxiesGroups(...)`
    - provider fetch via `coreController.getExternalProviders()`
    - IP-check source list or parsing logic
  - meaning:
    - the update-system path is a valid regression suspect because it now runs during startup
    - but the raw connection failure is not yet explained by a direct network-config diff inside those commits alone
- Broader Android risk surface in the same release band:
  - `7996e3b` renamed Android package / namespace / AIDL / manifest / service paths from `com.follow.clash` to `com.makriq.flclash`
  - this touched:
    - app module Kotlin entrypoints
    - Android common module helpers and component routing
    - service module AIDL and `VpnService`
    - plugin wiring
  - this change set is much larger and operationally riskier than the update dialog itself
  - if the bug appeared "after update-system work", the real regression could still live in the adjacent rebrand/runtime churn rather than in release-check UI code
- Symptom-to-code mapping already confirmed:
  - empty / never-ready proxy state is populated through:
    - `AppController.applyProfile()`
    - `_setupConfig()`
    - `updateGroups()`
    - `updateProviders()`
  - files:
    - `lib/controller.dart`
    - `lib/core/controller.dart`
  - current IP widget is driven by:
    - `NetworkDetection.startCheck()`
    - `NetworkDetection._checkIp()`
  - file:
    - `lib/providers/app.dart`
- Confirmed dashboard IP-state bug that can amplify the symptom:
  - `NetworkDetection._checkIp()` sets `state = isLoading:true, ipInfo:null` before the request
  - if all IP sources fail, `request.checkIp()` may return `Result.success(null)`
  - current code then does:
    - `if (ipInfo == null) { return; }`
  - consequence:
    - widget can remain in endless loading state instead of switching to an explicit timeout / failure state
  - this does **not** prove the root cause of connectivity loss, but it does explain why the UI can show "just loading" with little diagnostic value
- Error-visibility limitation in current startup path:
  - `applyProfile(...)` is wrapped in `loadingRun(...) -> safeRun(...)`
  - setup failures are surfaced mainly as transient notifier text, while groups/providers can stay empty afterward
  - consequence:
    - a core/setup failure during startup can look like "no servers / no IP / loading" unless logs or notifier text are captured
- Local environment limitation during this investigation round:
  - `flutter` is not installed in the current workstation environment
  - `dart` is not installed in the current workstation environment
  - because of that, local `flutter test` / `dart analyze` could not be executed here
  - heavy validation should continue via GitHub Actions in `makriq-org/FlClash`
- Current best hypothesis ranking before device/log evidence:
  - highest-risk area by churn:
    - Android rebrand/runtime namespace changes around `7996e3b` and `a565f2d`
  - plausible startup interaction:
    - early unawaited self-update check / dialog during app initialization
  - confirmed secondary UI bug:
    - network detection spinner can hide failure by never switching to timeout when all IP sources fail
- Practical next evidence needed for root-cause isolation:
  - compare behavior between:
    - `v0.8.96`
    - `v0.8.97`
    - `v0.8.98`
  - capture notifier/log output during a failing Android launch
  - inspect whether core/setup/profile application fails before proxy groups are requested
