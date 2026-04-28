import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:fl_clash/common/utils.dart';

class ReleaseAsset {
  ReleaseAsset({
    required this.name,
    required this.browserDownloadUrl,
    required this.size,
    this.digest,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: json['name']?.toString() ?? '',
      browserDownloadUrl: json['browser_download_url']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      digest: json['digest']?.toString(),
    );
  }

  static final RegExp _androidAssetPattern = RegExp(
    r'-android(?:-([A-Za-z0-9_]+(?:-[A-Za-z0-9_]+)*))?\.apk$',
  );

  final String name;
  final String browserDownloadUrl;
  final int size;
  final String? digest;

  bool get isAndroidApk => _androidAssetPattern.hasMatch(name);

  String? get androidAbi {
    final match = _androidAssetPattern.firstMatch(name);
    if (match == null) {
      return null;
    }
    return match.group(1);
  }

  String? get sha256Digest {
    final value = digest;
    if (value == null || !value.startsWith('sha256:')) {
      return null;
    }
    final parsed = value.substring('sha256:'.length).trim().toLowerCase();
    return _sha256Pattern.hasMatch(parsed) ? parsed : null;
  }
}

class AppRelease {
  AppRelease({
    required this.tagName,
    required this.body,
    required this.htmlUrl,
    required this.assets,
    required this.prerelease,
    required this.draft,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final rawAssets = json['assets'];
    final assets = rawAssets is List
        ? rawAssets
              .whereType<Map<String, dynamic>>()
              .map(ReleaseAsset.fromJson)
              .toList()
        : <ReleaseAsset>[];
    return AppRelease(
      tagName: json['tag_name']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      htmlUrl: json['html_url']?.toString() ?? '',
      assets: assets,
      prerelease: json['prerelease'] as bool? ?? false,
      draft: json['draft'] as bool? ?? false,
    );
  }

  final String tagName;
  final String body;
  final String htmlUrl;
  final List<ReleaseAsset> assets;
  final bool prerelease;
  final bool draft;

  String get version => tagName.startsWith('v') ? tagName.substring(1) : tagName;

  ReleaseAsset? findSha256AssetFor(ReleaseAsset asset) {
    final expectedName = '${asset.name}.sha256';
    for (final candidate in assets) {
      if (candidate.name == expectedName) {
        return candidate;
      }
    }
    return null;
  }
}

AppRelease? selectLatestRelease(
  Iterable<AppRelease> releases, {
  required bool includePrerelease,
}) {
  AppRelease? latestRelease;
  for (final release in releases) {
    if (release.draft) {
      continue;
    }
    if (!includePrerelease && release.prerelease) {
      continue;
    }
    if (latestRelease == null ||
        utils.compareVersions(release.version, latestRelease.version) > 0) {
      latestRelease = release;
    }
  }
  return latestRelease;
}

class AndroidReleaseAsset {
  const AndroidReleaseAsset({
    required this.apkAsset,
    required this.abi,
    this.checksumAsset,
  });

  final ReleaseAsset apkAsset;
  final String abi;
  final ReleaseAsset? checksumAsset;
}

const _sha256PatternSource = r'^[a-f0-9]{64}$';
final _sha256Pattern = RegExp(_sha256PatternSource);

AndroidReleaseAsset? selectAndroidReleaseAsset(
  AppRelease release, {
  required List<String> supportedAbis,
}) {
  final Map<String, ReleaseAsset> abiAssetMap = {};
  ReleaseAsset? universalAsset;

  for (final asset in release.assets) {
    if (!asset.isAndroidApk) {
      continue;
    }
    final abi = asset.androidAbi;
    if (abi == null || abi.isEmpty) {
      universalAsset ??= asset;
      continue;
    }
    abiAssetMap.putIfAbsent(abi, () => asset);
  }

  for (final abi in supportedAbis) {
    final asset = abiAssetMap[abi];
    if (asset != null) {
      return AndroidReleaseAsset(
        apkAsset: asset,
        abi: abi,
        checksumAsset: release.findSha256AssetFor(asset),
      );
    }
  }

  if (universalAsset != null) {
    return AndroidReleaseAsset(
      apkAsset: universalAsset,
      abi: 'universal',
      checksumAsset: release.findSha256AssetFor(universalAsset),
    );
  }
  return null;
}

Future<List<String>> getSupportedAndroidAbis() async {
  if (!Platform.isAndroid) {
    return const [];
  }
  final androidInfo = await DeviceInfoPlugin().androidInfo;
  return androidInfo.supportedAbis
      .where((abi) => abi.isNotEmpty)
      .toList(growable: false);
}

String? parseSha256Content(String? content) {
  if (content == null || content.trim().isEmpty) {
    return null;
  }
  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    final hash = line.split(RegExp(r'\s+')).first.toLowerCase();
    if (_sha256Pattern.hasMatch(hash)) {
      return hash;
    }
  }
  return null;
}

Future<String> computeFileSha256(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
