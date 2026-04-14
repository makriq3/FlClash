import 'package:fl_clash/common/android_vpn_hardening.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
