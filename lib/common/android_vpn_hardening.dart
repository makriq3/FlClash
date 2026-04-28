import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/common/string.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

bool shouldApplyAndroidVpnHardening({
  required bool isAndroid,
  required bool vpnEnabled,
}) {
  return isAndroid && vpnEnabled;
}

bool shouldRequestInstalledPackageAccessForAndroidProfile(
  Map<String, dynamic> rawConfig, {
  required bool isAndroid,
}) {
  if (!isAndroid) {
    return false;
  }

  final tun = _asStringKeyedMap(rawConfig['tun']);
  final inlineSelectors = [
    ..._asPackageSelectorList(
      tun['include-package'],
      fieldName: 'tun.include-package',
    ),
    ..._asPackageSelectorList(
      tun['exclude-package'],
      fieldName: 'tun.exclude-package',
    ),
  ];
  if (inlineSelectors.any(_selectorNeedsInstalledPackageAccess)) {
    return true;
  }

  return tun['include-package-file'] != null ||
      tun['exclude-package-file'] != null ||
      tun['include-package-url'] != null ||
      tun['exclude-package-url'] != null;
}

Future<Map<String, dynamic>> normalizeAndroidProfileAccessControlConfig(
  Map<String, dynamic> rawConfig, {
  required bool isAndroid,
  String? profilesPath,
  int? profileId,
  List<String> installedPackageNames = const [],
}) async {
  if (!isAndroid) {
    return rawConfig;
  }

  final tun = _asStringKeyedMap(rawConfig['tun']);
  final inlineIncludeSelectors = _asPackageSelectorList(
    tun['include-package'],
    fieldName: 'tun.include-package',
  );
  final inlineExcludeSelectors = _asPackageSelectorList(
    tun['exclude-package'],
    fieldName: 'tun.exclude-package',
  );
  final includePackageSources = _asPackageListSources(
    tun['include-package-file'],
    fieldName: 'tun.include-package-file',
  );
  final excludePackageSources = _asPackageListSources(
    tun['exclude-package-file'],
    fieldName: 'tun.exclude-package-file',
  );
  final includePackageUrls = _asPackageListSources(
    tun['include-package-url'],
    fieldName: 'tun.include-package-url',
    preferUrl: true,
  );
  final excludePackageUrls = _asPackageListSources(
    tun['exclude-package-url'],
    fieldName: 'tun.exclude-package-url',
    preferUrl: true,
  );
  final mergedIncludeSources = [
    ...includePackageSources,
    ...includePackageUrls,
  ];
  final mergedExcludeSources = [
    ...excludePackageSources,
    ...excludePackageUrls,
  ];

  if (inlineIncludeSelectors.isEmpty &&
      inlineExcludeSelectors.isEmpty &&
      mergedIncludeSources.isEmpty &&
      mergedExcludeSources.isEmpty) {
    return rawConfig;
  }

  final resolvedProfilesPath = profilesPath?.trim();
  if ((mergedIncludeSources.isNotEmpty || mergedExcludeSources.isNotEmpty) &&
      (resolvedProfilesPath == null || resolvedProfilesPath.isEmpty)) {
    throw const FormatException(
      'Android profile split tunneling file lists require a valid profiles path.',
    );
  }

  final normalizedTun = Map<String, dynamic>.from(tun);
  final includeSelectors = <String>[
    ...inlineIncludeSelectors,
    ...await _readPackageLists(
      mergedIncludeSources,
      profilesPath: resolvedProfilesPath ?? '',
      profileId: profileId,
      fieldName: 'tun.include-package-file',
    ),
  ];
  final excludeSelectors = <String>[
    ...inlineExcludeSelectors,
    ...await _readPackageLists(
      mergedExcludeSources,
      profilesPath: resolvedProfilesPath ?? '',
      profileId: profileId,
      fieldName: 'tun.exclude-package-file',
    ),
  ];
  if (includeSelectors.isNotEmpty && excludeSelectors.isNotEmpty) {
    throw const FormatException(
      'Android profile split tunneling is ambiguous: use either '
      '`tun.include-package` or `tun.exclude-package`, not both.',
    );
  }
  final includePackages = _resolvePackageSelectors(
    includeSelectors,
    fieldName: 'tun.include-package',
    installedPackageNames: installedPackageNames,
  );
  final excludePackages = _resolvePackageSelectors(
    excludeSelectors,
    fieldName: 'tun.exclude-package',
    installedPackageNames: installedPackageNames,
  );

  if (includePackages.isNotEmpty) {
    normalizedTun['include-package'] = includePackages;
  } else {
    normalizedTun.remove('include-package');
  }
  if (excludePackages.isNotEmpty) {
    normalizedTun['exclude-package'] = excludePackages;
  } else {
    normalizedTun.remove('exclude-package');
  }
  normalizedTun.remove('include-package-file');
  normalizedTun.remove('exclude-package-file');
  normalizedTun.remove('include-package-url');
  normalizedTun.remove('exclude-package-url');

  final patched = Map<String, dynamic>.from(rawConfig);
  patched['tun'] = normalizedTun;
  return patched;
}

AccessControlProps? resolveAndroidProfileAccessControlOverride(
  Map<String, dynamic> rawConfig, {
  required bool isAndroid,
  List<String> installedPackageNames = const [],
}) {
  if (!isAndroid) {
    return null;
  }

  final tun = _asStringKeyedMap(rawConfig['tun']);
  final includeSelectors = _asPackageSelectorList(
    tun['include-package'],
    fieldName: 'tun.include-package',
  );
  final excludeSelectors = _asPackageSelectorList(
    tun['exclude-package'],
    fieldName: 'tun.exclude-package',
  );

  if (includeSelectors.isNotEmpty && excludeSelectors.isNotEmpty) {
    throw const FormatException(
      'Android profile split tunneling is ambiguous: use either '
      '`tun.include-package` or `tun.exclude-package`, not both.',
    );
  }

  final includePackages = _resolvePackageSelectors(
    includeSelectors,
    fieldName: 'tun.include-package',
    installedPackageNames: installedPackageNames,
  );
  final excludePackages = _resolvePackageSelectors(
    excludeSelectors,
    fieldName: 'tun.exclude-package',
    installedPackageNames: installedPackageNames,
  );

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

List<String> _asPackageSelectorList(dynamic value, {required String fieldName}) {
  if (value == null) {
    return const [];
  }
  if (value is String) {
    final normalized = value.trim();
    return normalized.isEmpty ? const [] : [normalized];
  }
  if (value is! List) {
    throw FormatException(
      'Profile field `$fieldName` must be a YAML list of Android package '
      'selectors.',
    );
  }
  final selectors = <String>[];
  for (final item in value) {
    final normalized = item.toString().trim();
    if (normalized.isEmpty) {
      continue;
    }
    selectors.add(normalized);
  }
  return selectors;
}

List<_PackageListSource> _asPackageListSources(
  dynamic value, {
  required String fieldName,
  bool preferUrl = false,
}) {
  if (value == null) {
    return const [];
  }
  if (value is String) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return const [];
    }
    if (preferUrl && !_isHttpUrl(normalized)) {
      throw FormatException(
        'Profile field `$fieldName` must contain a valid HTTP(S) URL: '
        '$normalized',
      );
    }
    return [
      _PackageListSource(
        url: _isHttpUrl(normalized) || preferUrl ? normalized : null,
        path: _isHttpUrl(normalized) || preferUrl ? null : normalized,
      ),
    ];
  }
  if (value is Map || value is YamlMap) {
    final source = _asPackageListSourceDescriptor(
      value,
      fieldName: fieldName,
      preferUrl: preferUrl,
    );
    return source == null ? const [] : [source];
  }
  if (value is! List) {
    throw FormatException(
      'Profile field `$fieldName` must be a path, a URL, a source map, or '
      'a YAML list of those values.',
    );
  }
  final sources = <_PackageListSource>{};
  for (final item in value) {
    if (item is String) {
      final normalized = item.trim();
      if (normalized.isEmpty) {
        continue;
      }
      if (preferUrl && !_isHttpUrl(normalized)) {
        throw FormatException(
          'Profile field `$fieldName` must contain valid HTTP(S) URLs: '
          '$normalized',
        );
      }
      sources.add(
        _PackageListSource(
          url: _isHttpUrl(normalized) || preferUrl ? normalized : null,
          path: _isHttpUrl(normalized) || preferUrl ? null : normalized,
        ),
      );
      continue;
    }
    final source = _asPackageListSourceDescriptor(
      item,
      fieldName: fieldName,
      preferUrl: preferUrl,
    );
    if (source != null) {
      sources.add(source);
    }
  }
  return sources.toList();
}

_PackageListSource? _asPackageListSourceDescriptor(
  dynamic value, {
  required String fieldName,
  required bool preferUrl,
}) {
  if (value is! Map && value is! YamlMap) {
    throw FormatException(
      'Profile field `$fieldName` accepts only strings or source maps.',
    );
  }
  final normalized = _asStringKeyedMap(value);
  final rawPath = normalized['path']?.toString().trim();
  final rawUrl = normalized['url']?.toString().trim();
  final pathValue = rawPath == null || rawPath.isEmpty ? null : rawPath;
  final urlValue = rawUrl == null || rawUrl.isEmpty ? null : rawUrl;
  if (pathValue == null && urlValue == null) {
    return null;
  }
  if (urlValue != null && !_isHttpUrl(urlValue)) {
    throw FormatException(
      'Profile field `$fieldName` contains an invalid URL source: $urlValue',
    );
  }
  if (preferUrl && urlValue == null) {
    if (pathValue == null || !_isHttpUrl(pathValue)) {
      throw FormatException(
        'Profile field `$fieldName` must contain valid HTTP(S) URLs.',
      );
    }
  }
  if (preferUrl &&
      urlValue == null &&
      pathValue != null &&
      _isHttpUrl(pathValue)) {
    return _PackageListSource(url: pathValue);
  }
  return _PackageListSource(path: pathValue, url: urlValue);
}

Future<List<String>> _readPackageLists(
  List<_PackageListSource> sources, {
  required String profilesPath,
  int? profileId,
  required String fieldName,
}) async {
  final packages = <String>[];
  for (final source in sources) {
    final sourceFieldName = source.url != null
        ? fieldName.replaceAll('-file', '-url')
        : fieldName;
    final content = source.url != null
        ? await _readPackageListFromRemoteSource(
            source,
            profilesPath: profilesPath,
            profileId: profileId,
            fieldName: sourceFieldName,
          )
        : await _readPackageListFromLocalSource(
            source,
            profilesPath: profilesPath,
            fieldName: sourceFieldName,
          );
    packages.addAll([
      ..._parsePackageListFileContent(
        content,
        fieldName: sourceFieldName,
        path: source.url ?? source.path ?? sourceFieldName,
      ),
    ]);
  }
  return packages;
}

Future<String> _readPackageListFromLocalSource(
  _PackageListSource source, {
  required String profilesPath,
  required String fieldName,
}) async {
  final rawPath = source.path;
  if (rawPath == null || rawPath.isEmpty) {
    throw FormatException(
      'Package list file for `$fieldName` is missing a valid local path.',
    );
  }
  final resolvedPath = _resolvePackageListPath(rawPath, profilesPath);
  final file = File(resolvedPath);
  if (!await file.exists()) {
    throw FormatException(
      'Package list file for `$fieldName` was not found: $resolvedPath',
    );
  }
  return file.readAsString();
}

Future<String> _readPackageListFromRemoteSource(
  _PackageListSource source, {
  required String profilesPath,
  required int? profileId,
  required String fieldName,
}) async {
  final rawUrl = source.url;
  if (rawUrl == null || rawUrl.isEmpty) {
    throw FormatException(
      'Package list URL for `$fieldName` is missing a valid remote source.',
    );
  }
  final cachePath = _resolvePackageListCachePath(
    source,
    profilesPath: profilesPath,
    profileId: profileId,
    fieldName: fieldName,
  );
  final cacheFile = File(cachePath);
  await cacheFile.parent.create(recursive: true);
  try {
    final response = await request.dio.get<String>(
      rawUrl,
      options: Options(
        responseType: ResponseType.plain,
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    final content = response.data ?? '';
    await cacheFile.writeAsString(content);
    return content;
  } catch (_) {
    if (await cacheFile.exists()) {
      return cacheFile.readAsString();
    }
    throw FormatException(
      'Package list URL for `$fieldName` could not be fetched and no cache '
      'is available: $rawUrl',
    );
  }
}

String _resolvePackageListPath(String rawPath, String profilesPath) {
  return path.normalize(
    path.isAbsolute(rawPath) ? rawPath : path.join(profilesPath, rawPath),
  );
}

String _resolvePackageListCachePath(
  _PackageListSource source, {
  required String profilesPath,
  required int? profileId,
  required String fieldName,
}) {
  final rawUrl = source.url;
  if (rawUrl == null || rawUrl.isEmpty) {
    throw FormatException(
      'Package list URL for `$fieldName` is missing a cacheable source.',
    );
  }
  final rawPath = source.path?.trim();
  if (rawPath != null && rawPath.isNotEmpty) {
    return _resolvePackageListPath(rawPath, profilesPath);
  }
  if (profileId == null) {
    throw FormatException(
      'Package list URL for `$fieldName` requires a profile id to cache data.',
    );
  }
  return path.join(
    profilesPath,
    'providers',
    profileId.toString(),
    'packages',
    rawUrl.toMd5(),
  );
}

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.hasAuthority;
}

List<String> _parsePackageListFileContent(
  String content, {
  required String fieldName,
  required String path,
}) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    return const [];
  }

  try {
    final yamlContent = loadYaml(trimmed);
    if (yamlContent is List || yamlContent is YamlList) {
      return _asPackageSelectorList(
        yamlContent,
        fieldName: '$fieldName ($path)',
      );
    }
  } catch (_) {}

  final selectors = <String>[];
  for (var line in const LineSplitter().convert(content)) {
    var normalized = line.trim();
    if (normalized.isEmpty || normalized.startsWith('#')) {
      continue;
    }
    if (normalized.startsWith('-')) {
      normalized = normalized.substring(1).trim();
    }
    final inlineCommentIndex = normalized.indexOf(' #');
    if (inlineCommentIndex != -1) {
      normalized = normalized.substring(0, inlineCommentIndex).trim();
    }
    if (normalized.isEmpty || normalized.startsWith('#')) {
      continue;
    }
    selectors.add(normalized);
  }
  return selectors;
}

List<String> _resolvePackageSelectors(
  List<String> selectors, {
  required String fieldName,
  required List<String> installedPackageNames,
}) {
  if (selectors.isEmpty) {
    return const [];
  }

  final compiledSelectors = selectors
      .map(
        (selector) => _CompiledPackageSelector.parse(
          selector,
          fieldName: fieldName,
        ),
      )
      .toList();
  final normalizedInstalledPackages = LinkedHashSet<String>.from(
    installedPackageNames
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty),
  ).toList();

  if (normalizedInstalledPackages.isEmpty) {
    final resolvedPackages = <String>{};
    for (final selector in compiledSelectors) {
      if (selector.requiresInstalledPackageScan) {
        commonPrint.log(
          'Android package selector `${selector.raw}` in `$fieldName` was '
          'ignored because no installed applications list is available.',
          logLevel: LogLevel.warning,
        );
        continue;
      }
      if (selector.include) {
        resolvedPackages.add(selector.pattern);
      } else {
        resolvedPackages.remove(selector.pattern);
      }
    }
    return resolvedPackages.toList();
  }

  final matchCounters = List<int>.filled(compiledSelectors.length, 0);
  final resolvedPackages = <String>{};
  for (var index = 0; index < compiledSelectors.length; index++) {
    final selector = compiledSelectors[index];
    final matches = normalizedInstalledPackages
        .where(selector.matches)
        .toList();
    matchCounters[index] = matches.length;
    if (matches.isEmpty) {
      continue;
    }
    if (selector.include) {
      resolvedPackages.addAll(matches);
    } else {
      resolvedPackages.removeAll(matches);
    }
  }

  for (var index = 0; index < compiledSelectors.length; index++) {
    if (matchCounters[index] != 0) {
      continue;
    }
    commonPrint.log(
      'Android package selector `${compiledSelectors[index].raw}` in '
      '`$fieldName` matched no installed applications.',
      logLevel: LogLevel.warning,
    );
  }

  return resolvedPackages.toList();
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

final class _CompiledPackageSelector {
  const _CompiledPackageSelector({
    required this.raw,
    required this.pattern,
    required this.include,
    required this.matcher,
    required this.requiresInstalledPackageScan,
  });

  final String raw;
  final String pattern;
  final bool include;
  final bool requiresInstalledPackageScan;
  final bool Function(String packageName) matcher;

  bool matches(String packageName) => matcher(packageName);

  static _CompiledPackageSelector parse(
    String rawValue, {
    required String fieldName,
  }) {
    final normalized = rawValue.trim();
    final isNegated = normalized.startsWith('!');
    final selectorBody = isNegated ? normalized.substring(1).trim() : normalized;
    if (selectorBody.isEmpty) {
      throw FormatException(
        'Profile field `$fieldName` contains an empty Android package selector: '
        '$rawValue',
      );
    }

    final regexBody = _extractRegexBody(selectorBody);
    if (regexBody != null) {
      try {
        final regex = RegExp(regexBody);
        return _CompiledPackageSelector(
          raw: normalized,
          pattern: selectorBody,
          include: !isNegated,
          requiresInstalledPackageScan: true,
          matcher: regex.hasMatch,
        );
      } catch (error) {
        throw FormatException(
          'Profile field `$fieldName` contains an invalid package regular '
          'expression `$selectorBody`: $error',
        );
      }
    }

    if (selectorBody.contains('*')) {
      final glob = RegExp(
        '^${RegExp.escape(selectorBody).replaceAll(r'\*', '.*')}\$',
      );
      return _CompiledPackageSelector(
        raw: normalized,
        pattern: selectorBody,
        include: !isNegated,
        requiresInstalledPackageScan: true,
        matcher: glob.hasMatch,
      );
    }

    return _CompiledPackageSelector(
      raw: normalized,
      pattern: selectorBody,
      include: !isNegated,
      requiresInstalledPackageScan: false,
      matcher: (packageName) => packageName == selectorBody,
    );
  }
}

String? _extractRegexBody(String selector) {
  for (final prefix in const ['re:', 'regex:', 'regexp:']) {
    if (selector.startsWith(prefix)) {
      return selector.substring(prefix.length);
    }
  }
  return null;
}

bool _selectorNeedsInstalledPackageAccess(String rawSelector) {
  final normalized = rawSelector.trim();
  if (normalized.isEmpty) {
    return false;
  }
  final selectorBody = normalized.startsWith('!')
      ? normalized.substring(1).trim()
      : normalized;
  return selectorBody.contains('*') || _extractRegexBody(selectorBody) != null;
}

class _PackageListSource {
  final String? path;
  final String? url;

  const _PackageListSource({this.path, this.url});

  @override
  bool operator ==(Object other) {
    return other is _PackageListSource &&
        other.path == path &&
        other.url == url;
  }

  @override
  int get hashCode => Object.hash(path, url);
}
