import 'package:fl_clash/common/update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('android release asset selection', () {
    final release = AppRelease(
      tagName: 'v0.8.95',
      body: '',
      htmlUrl: 'https://github.com/makriq-org/FlClash/releases/tag/v0.8.95',
      prerelease: false,
      draft: false,
      assets: [
        ReleaseAsset(
          name: 'FlClash-0.8.95-android-arm64-v8a.apk',
          browserDownloadUrl: 'https://example.com/arm64.apk',
          size: 1,
          digest:
              'sha256:1111111111111111111111111111111111111111111111111111111111111111',
        ),
        ReleaseAsset(
          name: 'FlClash-0.8.95-android-arm64-v8a.apk.sha256',
          browserDownloadUrl: 'https://example.com/arm64.apk.sha256',
          size: 1,
        ),
        ReleaseAsset(
          name: 'FlClash-0.8.95-android-armeabi-v7a.apk',
          browserDownloadUrl: 'https://example.com/armv7.apk',
          size: 1,
        ),
      ],
    );

    test('selects the first compatible abi from device preference order', () {
      final selected = selectAndroidReleaseAsset(
        release,
        supportedAbis: const ['x86_64', 'arm64-v8a', 'armeabi-v7a'],
      );

      expect(selected, isNotNull);
      expect(selected!.abi, 'arm64-v8a');
      expect(selected.apkAsset.name, contains('arm64-v8a'));
      expect(selected.checksumAsset?.name, endsWith('.apk.sha256'));
    });

    test('returns null when release has no compatible abi', () {
      final selected = selectAndroidReleaseAsset(
        release,
        supportedAbis: const ['x86_64'],
      );

      expect(selected, isNull);
    });
  });

  test('parses sha256 sidecar file content', () {
    final parsed = parseSha256Content(
      'c330912450ff08461b11f755bc3733c6b6a9c71396324a2e3e40d1589bdff62e  FlClash.apk',
    );

    expect(
      parsed,
      'c330912450ff08461b11f755bc3733c6b6a9c71396324a2e3e40d1589bdff62e',
    );
  });

  group('latest release selection', () {
    AppRelease buildRelease(
      String tagName, {
      bool prerelease = false,
      bool draft = false,
    }) {
      return AppRelease(
        tagName: tagName,
        body: '',
        htmlUrl: 'https://github.com/makriq-org/FlClash/releases/tag/$tagName',
        assets: const [],
        prerelease: prerelease,
        draft: draft,
      );
    }

    test('stable channel ignores prereleases', () {
      final release = selectLatestRelease([
        buildRelease('v0.8.95'),
        buildRelease('v0.9.00-pre1', prerelease: true),
      ], includePrerelease: false);

      expect(release?.tagName, 'v0.8.95');
    });

    test('pre-release channel can select the newest prerelease', () {
      final release = selectLatestRelease([
        buildRelease('v0.8.95'),
        buildRelease('v0.9.00-pre1', prerelease: true),
      ], includePrerelease: true);

      expect(release?.tagName, 'v0.9.00-pre1');
    });

    test('pre-release channel still prefers stable of same version core', () {
      final release = selectLatestRelease([
        buildRelease('v0.9.00-pre1', prerelease: true),
        buildRelease('v0.9.0'),
      ], includePrerelease: true);

      expect(release?.tagName, 'v0.9.0');
    });

    test('draft releases are ignored for all channels', () {
      final release = selectLatestRelease([
        buildRelease('v0.9.01', draft: true),
        buildRelease('v0.8.95'),
      ], includePrerelease: true);

      expect(release?.tagName, 'v0.8.95');
    });
  });
}
