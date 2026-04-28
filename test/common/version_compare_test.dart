import 'package:fl_clash/common/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('version comparison', () {
    final utils = Utils();

    test('treats prerelease tag with zero-padded patch as newer than old stable', () {
      expect(utils.compareVersions('0.9.00-pre1', '0.8.98'), greaterThan(0));
    });

    test('treats stable release as newer than prerelease of same core version', () {
      expect(
        utils.compareVersions('0.9.0', '0.9.0-pre1+2026041303'),
        greaterThan(0),
      );
    });

    test('compares prerelease identifiers numerically when suffix increments', () {
      expect(
        utils.compareVersions('0.9.00-pre2', '0.9.0-pre1+2026041303'),
        greaterThan(0),
      );
    });

    test('uses build metadata as final tie breaker when prerelease is equal', () {
      expect(
        utils.compareVersions('0.9.0-pre1+2026041304', '0.9.00-pre1+2026041303'),
        greaterThan(0),
      );
    });

    test('ignores missing build metadata when release tag matches installed version', () {
      expect(
        utils.compareVersions('0.9.00-pre1', '0.9.0-pre1+2026041303'),
        0,
      );
    });
  });
}
