import 'dart:collection';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

bool shouldApplyAndroidVpnHardening({
  required bool isAndroid,
  required bool vpnEnabled,
}) {
  return isAndroid && vpnEnabled;
}

AccessControlProps? resolveAndroidProfileAccessControlOverride(
  Map<String, dynamic> rawConfig, {
  required bool isAndroid,
}) {
  if (!isAndroid) {
    return null;
  }

  final tun = _asStringKeyedMap(rawConfig['tun']);
  final includePackages = _asPackageList(
    tun['include-package'],
    fieldName: 'tun.include-package',
  );
  final excludePackages = _asPackageList(
    tun['exclude-package'],
    fieldName: 'tun.exclude-package',
  );

  if (includePackages.isNotEmpty && excludePackages.isNotEmpty) {
    throw const FormatException(
      'Android profile split tunneling is ambiguous: use either '
      '`tun.include-package` or `tun.exclude-package`, not both.',
    );
  }

  if (includePackages.isNotEmpty) {
    return AccessControlProps(
      enable: true,
      mode: AccessControlMode.acceptSelected,
      acceptList: includePackages,
    );
  }

  if (excludePackages.isNotEmpty) {
    return AccessControlProps(
      enable: true,
      mode: AccessControlMode.rejectSelected,
      rejectList: excludePackages,
    );
  }

  return null;
}

VpnOptions applyResolvedTunToVpnOptions(
  VpnOptions options, {
  required Tun tun,
  required RouteMode routeMode,
  required bool isDesktop,
}) {
  final resolvedTun = _resolveTunForPlatform(
    tun,
    routeMode: routeMode,
    isDesktop: isDesktop,
  );
  return options.copyWith(
    stack: resolvedTun.stack.name,
    routeAddress: resolvedTun.routeAddress,
  );
}

ClashConfig resolveAndroidRuntimeClashConfig(
  ClashConfig config, {
  required RouteMode routeMode,
  required bool isAndroid,
  required bool vpnEnabled,
}) {
  final resolvedConfig = config.copyWith(
    tun: _resolveTunForPlatform(
      config.tun,
      routeMode: routeMode,
      isDesktop: !isAndroid,
    ),
  );
  return hardenAndroidClashConfig(
    resolvedConfig,
    isAndroid: isAndroid,
    vpnEnabled: vpnEnabled,
  );
}

Tun _resolveTunForPlatform(
  Tun tun, {
  required RouteMode routeMode,
  required bool isDesktop,
}) {
  final routeAddress = routeMode == RouteMode.bypassPrivate
      ? defaultBypassPrivateRouteAddress
      : tun.routeAddress;
  return switch (isDesktop) {
    true => tun.copyWith(autoRoute: true, routeAddress: const []),
    false => tun.copyWith(
      autoRoute: routeAddress.isEmpty,
      routeAddress: routeAddress,
    ),
  };
}

ClashConfig hardenAndroidClashConfig(
  ClashConfig config, {
  required bool isAndroid,
  required bool vpnEnabled,
}) {
  if (!shouldApplyAndroidVpnHardening(
    isAndroid: isAndroid,
    vpnEnabled: vpnEnabled,
  )) {
    return config;
  }
  return config.copyWith(
    port: 0,
    socksPort: 0,
    mixedPort: 0,
    redirPort: 0,
    tproxyPort: 0,
    allowLan: false,
    externalController: ExternalControllerStatus.close,
  );
}

VpnOptions hardenAndroidVpnOptions(
  VpnOptions options, {
  required bool isAndroid,
}) {
  if (!shouldApplyAndroidVpnHardening(
    isAndroid: isAndroid,
    vpnEnabled: options.enable,
  )) {
    return options;
  }
  return options.copyWith(
    allowBypass: false,
    systemProxy: false,
    bypassDomain: const [],
    port: 0,
  );
}

List<String> buildAndroidVpnCompatibilityRules({
  required bool isAndroid,
  required bool vpnEnabled,
  required List<String> bypassDomain,
}) {
  if (!shouldApplyAndroidVpnHardening(
    isAndroid: isAndroid,
    vpnEnabled: vpnEnabled,
  )) {
    return const [];
  }
  final rules = <String>{};
  for (final pattern in bypassDomain) {
    final rule = _convertBypassPatternToDirectRule(pattern);
    if (rule != null) {
      rules.add(rule);
    }
  }
  return rules.toList();
}

Map<String, dynamic> applyAndroidVpnProfileCompatibility(
  Map<String, dynamic> rawConfig, {
  required bool isAndroid,
  required bool vpnEnabled,
  required List<String> bypassDomain,
}) {
  if (!shouldApplyAndroidVpnHardening(
    isAndroid: isAndroid,
    vpnEnabled: vpnEnabled,
  )) {
    return rawConfig;
  }

  final patched = Map<String, dynamic>.from(rawConfig);
  final compatibilityRules = buildAndroidVpnCompatibilityRules(
    isAndroid: isAndroid,
    vpnEnabled: vpnEnabled,
    bypassDomain: bypassDomain,
  );
  if (compatibilityRules.isNotEmpty) {
    final existingRules =
        (patched['rules'] as List?)?.map((item) => item.toString()).toList() ??
        const <String>[];
    patched['rules'] = <String>{
      ...compatibilityRules,
      ...existingRules,
    }.toList();
  }

  final sniffer = _asStringKeyedMap(patched['sniffer']);
  sniffer['enable'] = true;
  sniffer['force-dns-mapping'] ??= true;
  sniffer['parse-pure-ip'] ??= true;
  sniffer['override-destination'] ??= true;

  final sniffing = LinkedHashSet<String>.from(
    _asStringList(sniffer['sniffing']),
  )..addAll(['http', 'tls', 'quic']);
  sniffer['sniffing'] = sniffing.toList();

  final sniff = _asStringKeyedMap(sniffer['sniff']);
  sniff['HTTP'] = _mergeSniffPorts(
    sniff['HTTP'],
    ports: const ['80', '8080-8880'],
    overrideDestination: true,
  );
  sniff['TLS'] = _mergeSniffPorts(sniff['TLS'], ports: const ['443', '8443']);
  sniff['QUIC'] = _mergeSniffPorts(sniff['QUIC'], ports: const ['443', '8443']);
  sniffer['sniff'] = sniff;
  patched['sniffer'] = sniffer;

  return patched;
}

bool shouldUseLocalProxyForRequests({
  required bool isAndroid,
  required bool vpnEnabled,
  required bool isStart,
  required int port,
}) {
  if (!isStart || port <= 0) {
    return false;
  }
  return !shouldApplyAndroidVpnHardening(
    isAndroid: isAndroid,
    vpnEnabled: vpnEnabled,
  );
}

Map<String, dynamic> _mergeSniffPorts(
  dynamic rawValue, {
  required List<String> ports,
  bool? overrideDestination,
}) {
  final value = _asStringKeyedMap(rawValue);
  final mergedPorts = LinkedHashSet<String>.from(_asStringList(value['ports']))
    ..addAll(ports);
  value['ports'] = mergedPorts.toList();
  if (overrideDestination != null) {
    value['override-destination'] ??= overrideDestination;
  }
  return value;
}

Map<String, dynamic> _asStringKeyedMap(dynamic value) {
  if (value is! Map) {
    return <String, dynamic>{};
  }
  return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
}

List<String> _asStringList(dynamic value) {
  if (value is! List) {
    return const [];
  }
  return value.map((item) => item.toString()).toList();
}

List<String> _asPackageList(dynamic value, {required String fieldName}) {
  if (value == null) {
    return const [];
  }
  if (value is String) {
    final normalized = value.trim();
    return normalized.isEmpty ? const [] : [normalized];
  }
  if (value is! List) {
    throw FormatException(
      'Profile field `$fieldName` must be a YAML list of Android package names.',
    );
  }
  final packages = <String>{};
  for (final item in value) {
    final normalized = item.toString().trim();
    if (normalized.isEmpty) {
      continue;
    }
    packages.add(normalized);
  }
  return packages.toList();
}

String? _convertBypassPatternToDirectRule(String rawPattern) {
  final pattern = rawPattern.trim();
  if (pattern.isEmpty) {
    return null;
  }

  final ipRule = _convertIpv4PatternToRule(pattern);
  if (ipRule != null) {
    return ipRule;
  }

  if (pattern.startsWith('+.')) {
    final suffix = pattern.substring(2);
    return suffix.isEmpty ? null : 'DOMAIN-SUFFIX,$suffix,DIRECT';
  }

  if (pattern.startsWith('*')) {
    if (pattern.indexOf('*', 1) != -1) {
      return null;
    }
    final suffix = pattern.substring(1).replaceFirst(RegExp(r'^\.+'), '');
    return suffix.isEmpty ? null : 'DOMAIN-SUFFIX,$suffix,DIRECT';
  }

  if (pattern.contains('*')) {
    return null;
  }

  return 'DOMAIN,$pattern,DIRECT';
}

String? _convertIpv4PatternToRule(String pattern) {
  final exactMatch = RegExp(
    r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
  ).firstMatch(pattern);
  if (exactMatch != null) {
    final octets = exactMatch.groups([1, 2, 3, 4]);
    if (_isValidOctets(octets)) {
      return 'IP-CIDR,${octets.join('.')}/32,DIRECT,no-resolve';
    }
  }

  final slash24Match = RegExp(
    r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.\*$',
  ).firstMatch(pattern);
  if (slash24Match != null) {
    final octets = slash24Match.groups([1, 2, 3]);
    if (_isValidOctets(octets)) {
      return 'IP-CIDR,${octets.join('.')}.0/24,DIRECT,no-resolve';
    }
  }

  final slash16Match = RegExp(
    r'^(\d{1,3})\.(\d{1,3})\.\*$',
  ).firstMatch(pattern);
  if (slash16Match != null) {
    final octets = slash16Match.groups([1, 2]);
    if (_isValidOctets(octets)) {
      return 'IP-CIDR,${octets.join('.')}.0.0/16,DIRECT,no-resolve';
    }
  }

  final slash8Match = RegExp(r'^(\d{1,3})\.\*$').firstMatch(pattern);
  if (slash8Match != null) {
    final octets = slash8Match.groups([1]);
    if (_isValidOctets(octets)) {
      return 'IP-CIDR,${octets.first}.0.0.0/8,DIRECT,no-resolve';
    }
  }

  return null;
}

bool _isValidOctets(List<String?> octets) {
  return octets.every((octet) {
    final value = int.tryParse(octet ?? '');
    return value != null && value >= 0 && value <= 255;
  });
}
