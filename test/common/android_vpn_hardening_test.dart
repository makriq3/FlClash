import 'dart:io';

import 'package:fl_clash/common/android_vpn_hardening.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'android profile split tunneling expands include-package-file relative to profiles path',
    () async {
      final profilesDir = await Directory.systemTemp.createTemp(
        'flclash-include-file-',
      );
      addTearDown(() async {
        await profilesDir.delete(recursive: true);
      });
      final packagesDir = Directory('${profilesDir.path}/lists');
      await packagesDir.create(recursive: true);
      final packagesFile = File('${packagesDir.path}/include.txt');
      await packagesFile.writeAsString('''
# comment
org.telegram.messenger
- com.android.chrome
org.telegram.messenger
''');

      final normalized = await normalizeAndroidProfileAccessControlConfig(
        {
          'tun': {
            'include-package': ['com.termux'],
            'include-package-file': 'lists/include.txt',
          },
        },
        isAndroid: true,
        profilesPath: profilesDir.path,
      );

      expect(normalized['tun']['include-package'], [
        'com.termux',
        'org.telegram.messenger',
        'com.android.chrome',
      ]);
      expect(
        (normalized['tun'] as Map<String, dynamic>).containsKey(
          'include-package-file',
        ),
        isFalse,
      );

      final resolved = resolveAndroidProfileAccessControlOverride(
        normalized,
        isAndroid: true,
      );
      expect(resolved?.mode, AccessControlMode.acceptSelected);
      expect(resolved?.acceptList, [
        'com.termux',
        'org.telegram.messenger',
        'com.android.chrome',
      ]);
    },
  );

  test(
    'android profile split tunneling expands exclude-package-file from yaml list files',
    () async {
      final profilesDir = await Directory.systemTemp.createTemp(
        'flclash-exclude-file-',
      );
      addTearDown(() async {
        await profilesDir.delete(recursive: true);
      });
      final packagesFile = File('${profilesDir.path}/exclude.yaml');
      await packagesFile.writeAsString('''
- org.mozilla.firefox
- com.android.vending
''');

      final normalized = await normalizeAndroidProfileAccessControlConfig(
        {
          'tun': {
            'exclude-package-file': ['exclude.yaml'],
          },
        },
        isAndroid: true,
        profilesPath: profilesDir.path,
      );

      expect(normalized['tun']['exclude-package'], [
        'org.mozilla.firefox',
        'com.android.vending',
      ]);
      expect(
        (normalized['tun'] as Map<String, dynamic>).containsKey(
          'exclude-package-file',
        ),
        isFalse,
      );

      final resolved = resolveAndroidProfileAccessControlOverride(
        normalized,
        isAndroid: true,
      );
      expect(resolved?.mode, AccessControlMode.rejectSelected);
      expect(resolved?.rejectList, [
        'org.mozilla.firefox',
        'com.android.vending',
      ]);
    },
  );

  test(
    'android profile split tunneling downloads package lists from urls and caches them',
    () async {
      final profilesDir = await Directory.systemTemp.createTemp(
        'flclash-url-file-',
      );
      addTearDown(() async {
        await profilesDir.delete(recursive: true);
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('org.telegram.messenger\ncom.android.chrome\n');
        await request.response.close();
      });

      final normalized = await normalizeAndroidProfileAccessControlConfig(
        {
          'tun': {
            'exclude-package-url':
                'http://${server.address.address}:${server.port}/packages.txt',
          },
        },
        isAndroid: true,
        profilesPath: profilesDir.path,
        profileId: 42,
      );

      expect(normalized['tun']['exclude-package'], [
        'org.telegram.messenger',
        'com.android.chrome',
      ]);
      final cacheDir = Directory('${profilesDir.path}/providers/42/packages');
      expect(await cacheDir.exists(), isTrue);
      expect(await cacheDir.list().isEmpty, isFalse);
    },
  );

  test(
    'android profile split tunneling falls back to cached package list urls',
    () async {
      final profilesDir = await Directory.systemTemp.createTemp(
        'flclash-url-cache-',
      );
      addTearDown(() async {
        await profilesDir.delete(recursive: true);
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final url =
          'http://${server.address.address}:${server.port}/packages.txt';
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('org.mozilla.firefox\n');
        await request.response.close();
      });

      await normalizeAndroidProfileAccessControlConfig(
        {
          'tun': {'include-package-url': url},
        },
        isAndroid: true,
        profilesPath: profilesDir.path,
        profileId: 7,
      );
      await server.close(force: true);

      final normalized = await normalizeAndroidProfileAccessControlConfig(
        {
          'tun': {'include-package-url': url},
        },
        isAndroid: true,
        profilesPath: profilesDir.path,
        profileId: 7,
      );

      expect(normalized['tun']['include-package'], ['org.mozilla.firefox']);
    },
  );

  test(
    'android profile split tunneling accepts url descriptors with explicit cache paths',
    () async {
      final profilesDir = await Directory.systemTemp.createTemp(
        'flclash-url-descriptor-',
      );
      addTearDown(() async {
        await profilesDir.delete(recursive: true);
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('- com.termux\n');
        await request.response.close();
      });

      final normalized = await normalizeAndroidProfileAccessControlConfig(
        {
          'tun': {
            'include-package-file': [
              {
                'url':
                    'http://${server.address.address}:${server.port}/allow.yaml',
                'path': 'lists/allow.yaml',
              },
            ],
          },
        },
        isAndroid: true,
        profilesPath: profilesDir.path,
        profileId: 99,
      );

      expect(normalized['tun']['include-package'], ['com.termux']);
      expect(File('${profilesDir.path}/lists/allow.yaml').existsSync(), isTrue);
    },
  );

  test(
    'android profile split tunneling rejects local package list paths outside profiles path',
    () async {
      final profilesDir = await Directory.systemTemp.createTemp(
        'flclash-outside-local-',
      );
      addTearDown(() async {
        await profilesDir.delete(recursive: true);
      });

      await expectLater(
        () => normalizeAndroidProfileAccessControlConfig(
          {
            'tun': {
              'include-package-file': '../outside.txt',
            },
          },
          isAndroid: true,
          profilesPath: profilesDir.path,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'android profile split tunneling rejects remote cache paths outside profiles path',
    () async {
      final profilesDir = await Directory.systemTemp.createTemp(
        'flclash-outside-remote-',
      );
      addTearDown(() async {
        await profilesDir.delete(recursive: true);
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('com.termux\n');
        await request.response.close();
      });

      await expectLater(
        () => normalizeAndroidProfileAccessControlConfig(
          {
            'tun': {
              'include-package-file': [
                {
                  'url':
                      'http://${server.address.address}:${server.port}/allow.txt',
                  'path': '../outside-cache.txt',
                },
              ],
            },
          },
          isAndroid: true,
          profilesPath: profilesDir.path,
          profileId: 99,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'android profile split tunneling rejects missing package list files',
    () async {
      await expectLater(
        () => normalizeAndroidProfileAccessControlConfig(
          {
            'tun': {'exclude-package-file': 'missing.txt'},
          },
          isAndroid: true,
          profilesPath: '/tmp/flclash-missing',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'android profile split tunneling maps exclude-package to blacklist mode',
    () {
      final resolved = resolveAndroidProfileAccessControlOverride({
        'tun': {
          'exclude-package': ['org.telegram.messenger', 'com.android.chrome'],
        },
      }, isAndroid: true);

      expect(resolved, isNotNull);
      expect(resolved?.enable, isTrue);
      expect(resolved?.mode, AccessControlMode.rejectSelected);
      expect(resolved?.rejectList, [
        'org.telegram.messenger',
        'com.android.chrome',
      ]);
    },
  );

  test(
    'android profile split tunneling maps include-package to whitelist mode',
    () {
      final resolved = resolveAndroidProfileAccessControlOverride({
        'tun': {
          'include-package': ['com.termux'],
        },
      }, isAndroid: true);

      expect(resolved, isNotNull);
      expect(resolved?.enable, isTrue);
      expect(resolved?.mode, AccessControlMode.acceptSelected);
      expect(resolved?.acceptList, ['com.termux']);
    },
  );

  test('android profile split tunneling rejects conflicting package modes', () {
    expect(
      () => resolveAndroidProfileAccessControlOverride({
        'tun': {
          'include-package': ['com.termux'],
          'exclude-package': ['org.telegram.messenger'],
        },
      }, isAndroid: true),
      throwsFormatException,
    );
  });

  test(
    'android profile split tunneling requests installed package access only for dynamic selectors',
    () {
      expect(
        shouldRequestInstalledPackageAccessForAndroidProfile(
          {
            'tun': {
              'exclude-package': ['com.termux'],
            },
          },
          isAndroid: true,
        ),
        isFalse,
      );
      expect(
        shouldRequestInstalledPackageAccessForAndroidProfile(
          {
            'tun': {
              'exclude-package': ['*.yandex.*'],
            },
          },
          isAndroid: true,
        ),
        isTrue,
      );
      expect(
        shouldRequestInstalledPackageAccessForAndroidProfile(
          {
            'tun': {
              'exclude-package-file': ['lists/apps.txt'],
            },
          },
          isAndroid: true,
        ),
        isTrue,
      );
    },
  );

  test(
    'android profile split tunneling expands masks regex and exceptions against installed packages',
    () async {
      const installedPackageNames = [
        'ru.yandex.music',
        'ru.yandex.browser',
        'org.mozilla.firefox',
        'com.termux',
      ];

      final normalized = await normalizeAndroidProfileAccessControlConfig(
        {
          'tun': {
            'exclude-package': [
              '*.yandex.*',
              '!ru.yandex.browser',
              r're:^org\.mozilla\..+$',
            ],
          },
        },
        isAndroid: true,
        installedPackageNames: installedPackageNames,
      );

      expect(normalized['tun']['exclude-package'], [
        'ru.yandex.music',
        'org.mozilla.firefox',
      ]);

      final resolved = resolveAndroidProfileAccessControlOverride(
        normalized,
        isAndroid: true,
        installedPackageNames: installedPackageNames,
      );
      expect(resolved?.mode, AccessControlMode.rejectSelected);
      expect(resolved?.rejectList, [
        'ru.yandex.music',
        'org.mozilla.firefox',
      ]);
    },
  );

  test(
    'android profile split tunneling keeps selector order across file lists',
    () async {
      final profilesDir = await Directory.systemTemp.createTemp(
        'flclash-pattern-file-',
      );
      addTearDown(() async {
        await profilesDir.delete(recursive: true);
      });
      final packagesFile = File('${profilesDir.path}/include.txt');
      await packagesFile.writeAsString('''
com.termux
*.yandex.*
!ru.yandex.browser
''');

      final normalized = await normalizeAndroidProfileAccessControlConfig(
        {
          'tun': {
            'include-package-file': 'include.txt',
          },
        },
        isAndroid: true,
        profilesPath: profilesDir.path,
        installedPackageNames: const [
          'ru.yandex.music',
          'org.mozilla.firefox',
          'com.termux',
          'ru.yandex.browser',
        ],
      );

      expect(normalized['tun']['include-package'], [
        'com.termux',
        'ru.yandex.music',
      ]);
    },
  );

  test(
    'android profile split tunneling ignores dynamic selectors without installed package metadata',
    () {
      final resolved = resolveAndroidProfileAccessControlOverride(
        {
          'tun': {
            'exclude-package': ['*.yandex.*'],
          },
        },
        isAndroid: true,
      );

      expect(resolved, isNull);
    },
  );

  test(
    'android profile split tunneling keeps exact selectors when installed package metadata is unavailable',
    () {
      final resolved = resolveAndroidProfileAccessControlOverride(
        {
          'tun': {
            'exclude-package': ['com.termux', '*.yandex.*', '!com.termux'],
          },
        },
        isAndroid: true,
      );

      expect(resolved, isNull);
    },
  );

  test(
    'android profile split tunneling keeps exact selectors without installed package metadata',
    () {
      final resolved = resolveAndroidProfileAccessControlOverride(
        {
          'tun': {
            'include-package': ['com.termux', '*.yandex.*'],
          },
        },
        isAndroid: true,
      );

      expect(resolved?.mode, AccessControlMode.acceptSelected);
      expect(resolved?.acceptList, ['com.termux']);
    },
  );

  test('resolved tun route-address is propagated into vpn options', () {
    const options = VpnOptions(
      enable: true,
      port: 7890,
      ipv6: false,
      dnsHijacking: false,
      accessControlProps: AccessControlProps(),
      allowBypass: true,
      systemProxy: true,
      bypassDomain: [],
      stack: 'mixed',
    );
    const tun = Tun(
      stack: TunStack.system,
      routeAddress: ['1.1.1.0/24', '2001:db8::/32'],
    );

    final resolved = applyResolvedTunToVpnOptions(
      options,
      tun: tun,
      routeMode: RouteMode.config,
      isDesktop: false,
    );

    expect(resolved.stack, TunStack.system.name);
    expect(resolved.routeAddress, ['1.1.1.0/24', '2001:db8::/32']);
  });

  test('android runtime config resolves tun and keeps listeners closed', () {
    const config = ClashConfig(
      mixedPort: 7890,
      allowLan: true,
      externalController: ExternalControllerStatus.open,
      tun: Tun(stack: TunStack.system, routeAddress: ['1.1.1.0/24']),
    );

    final runtimeConfig = resolveAndroidRuntimeClashConfig(
      config,
      routeMode: RouteMode.config,
      isAndroid: true,
      vpnEnabled: true,
    );

    expect(runtimeConfig.tun.stack, TunStack.system);
    expect(runtimeConfig.tun.routeAddress, ['1.1.1.0/24']);
    expect(runtimeConfig.mixedPort, 0);
    expect(runtimeConfig.allowLan, false);
    expect(runtimeConfig.externalController, ExternalControllerStatus.close);
  });

  test('android runtime config respects bypassPrivate route mode', () {
    const config = ClashConfig(
      mixedPort: 7890,
      tun: Tun(stack: TunStack.gvisor, routeAddress: ['203.0.113.0/24']),
    );

    final runtimeConfig = resolveAndroidRuntimeClashConfig(
      config,
      routeMode: RouteMode.bypassPrivate,
      isAndroid: true,
      vpnEnabled: true,
    );

    expect(runtimeConfig.tun.stack, TunStack.gvisor);
    expect(runtimeConfig.tun.autoRoute, isFalse);
    expect(runtimeConfig.tun.routeAddress, defaultBypassPrivateRouteAddress);
    expect(runtimeConfig.mixedPort, 0);
  });

  test('runtime config stays unchanged when android hardening is inactive', () {
    const config = ClashConfig(
      mixedPort: 7890,
      allowLan: true,
      externalController: ExternalControllerStatus.open,
      tun: Tun(stack: TunStack.system, routeAddress: ['198.51.100.0/24']),
    );

    final runtimeConfig = resolveAndroidRuntimeClashConfig(
      config,
      routeMode: RouteMode.config,
      isAndroid: true,
      vpnEnabled: false,
    );

    expect(runtimeConfig.mixedPort, 7890);
    expect(runtimeConfig.allowLan, isTrue);
    expect(runtimeConfig.externalController, ExternalControllerStatus.open);
    expect(runtimeConfig.tun.routeAddress, ['198.51.100.0/24']);
  });

  test('android clash config hardening closes local listeners', () {
    const config = ClashConfig(
      port: 8080,
      socksPort: 1080,
      mixedPort: 7890,
      redirPort: 7892,
      tproxyPort: 7893,
      allowLan: true,
      externalController: ExternalControllerStatus.open,
    );

    final hardened = hardenAndroidClashConfig(
      config,
      isAndroid: true,
      vpnEnabled: true,
    );

    expect(hardened.port, 0);
    expect(hardened.socksPort, 0);
    expect(hardened.mixedPort, 0);
    expect(hardened.redirPort, 0);
    expect(hardened.tproxyPort, 0);
    expect(hardened.allowLan, false);
    expect(hardened.externalController, ExternalControllerStatus.close);
  });

  test('android vpn options hardening disables bypass and system proxy', () {
    const options = VpnOptions(
      enable: true,
      port: 7890,
      ipv6: true,
      dnsHijacking: false,
      accessControlProps: AccessControlProps(),
      allowBypass: true,
      systemProxy: true,
      bypassDomain: ['example.com'],
      stack: 'system',
    );

    final hardened = hardenAndroidVpnOptions(options, isAndroid: true);

    expect(hardened.port, 0);
    expect(hardened.allowBypass, false);
    expect(hardened.systemProxy, false);
    expect(hardened.bypassDomain, isEmpty);
  });

  test(
    'android compatibility rules preserve bypass domains without localhost proxy',
    () {
      final rules = buildAndroidVpnCompatibilityRules(
        isAndroid: true,
        vpnEnabled: true,
        bypassDomain: const ['2ip.ru', '*.ru', '127.*'],
      );

      expect(rules, contains('DOMAIN,2ip.ru,DIRECT'));
      expect(rules, contains('DOMAIN-SUFFIX,ru,DIRECT'));
      expect(rules, contains('IP-CIDR,127.0.0.0/8,DIRECT,no-resolve'));
    },
  );

  test(
    'android profile compatibility injects rules and sniffer for hardened vpn mode',
    () {
      final patched = applyAndroidVpnProfileCompatibility(
        {
          'rules': ['MATCH,PROXY'],
        },
        isAndroid: true,
        vpnEnabled: true,
        bypassDomain: const ['2ip.ru'],
      );

      expect(
        patched['rules'],
        containsAll(['DOMAIN,2ip.ru,DIRECT', 'MATCH,PROXY']),
      );
      expect(patched['sniffer'], isA<Map<String, dynamic>>());
      expect(patched['sniffer']['enable'], true);
      expect(
        (patched['sniffer']['sniffing'] as List).cast<String>(),
        containsAll(['http', 'tls', 'quic']),
      );
    },
  );

  test(
    'android profile compatibility still enables sniffer without bypass domains',
    () {
      final patched = applyAndroidVpnProfileCompatibility(
        {
          'rules': ['DOMAIN-SUFFIX,ru,DIRECT', 'MATCH,PROXY'],
        },
        isAndroid: true,
        vpnEnabled: true,
        bypassDomain: const [],
      );

      expect(patched['rules'], isNotEmpty);
      expect(patched['sniffer'], isA<Map<String, dynamic>>());
      expect(patched['sniffer']['enable'], true);
    },
  );

  test('android profile compatibility preserves explicit sniffer settings', () {
    final patched = applyAndroidVpnProfileCompatibility(
      {
        'sniffer': {
          'override-destination': false,
          'sniff': {
            'HTTP': {
              'ports': ['80'],
              'override-destination': false,
            },
          },
        },
      },
      isAndroid: true,
      vpnEnabled: true,
      bypassDomain: const [],
    );

    final sniffer = patched['sniffer'] as Map<String, dynamic>;
    final sniff = sniffer['sniff'] as Map<String, dynamic>;
    final http = sniff['HTTP'] as Map<String, dynamic>;

    expect(sniffer['override-destination'], isFalse);
    expect(http['override-destination'], isFalse);
    expect(
      (http['ports'] as List).cast<String>(),
      containsAll(['80', '8080-8880']),
    );
    expect(sniff.keys, containsAll(['HTTP', 'TLS', 'QUIC']));
  });

  test(
    'android profile compatibility stays inert when hardening is inactive',
    () {
      final rawConfig = <String, dynamic>{
        'rules': ['MATCH,PROXY'],
      };

      final patched = applyAndroidVpnProfileCompatibility(
        rawConfig,
        isAndroid: true,
        vpnEnabled: false,
        bypassDomain: const ['2ip.ru'],
      );

      expect(patched, same(rawConfig));
    },
  );

  test('android app requests avoid localhost proxy in vpn mode', () {
    expect(
      shouldUseLocalProxyForRequests(
        isAndroid: true,
        vpnEnabled: true,
        isStart: true,
        port: 7890,
      ),
      isFalse,
    );
  });

  test('desktop keeps localhost proxy path when service is running', () {
    expect(
      shouldUseLocalProxyForRequests(
        isAndroid: false,
        vpnEnabled: true,
        isStart: true,
        port: 7890,
      ),
      isTrue,
    );
  });
}
