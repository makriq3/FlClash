import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/dialog.dart';
import 'package:flutter/material.dart';

enum UpdateReleaseAction { later, skipRelease, install }

class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({
    super.key,
    required this.release,
  });

  final AppRelease release;

  List<String> get _notes {
    final notes = utils.parseReleaseBody(release.body);
    if (notes.isNotEmpty) {
      return notes;
    }
    final body = release.body.trim();
    if (body.isEmpty) {
      return const [];
    }
    return body
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    final textTheme = Theme.of(context).textTheme;
    return CommonDialog(
      title: appLocalizations.discoverNewVersion,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(UpdateReleaseAction.later);
          },
          child: Text(appLocalizations.later),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(UpdateReleaseAction.skipRelease);
          },
          child: Text(appLocalizations.skipRelease),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(UpdateReleaseAction.install);
          },
          child: Text(
            system.isAndroid
                ? appLocalizations.downloadAndInstall
                : appLocalizations.goDownload,
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(release.tagName, style: textTheme.headlineSmall),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final note in notes) ...[
              Text('- $note', style: textTheme.bodyMedium),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

enum _AndroidUpdateStage { preparing, downloading, verifying, installing, error }

class AndroidUpdateDialog extends StatefulWidget {
  const AndroidUpdateDialog({
    super.key,
    required this.release,
  });

  final AppRelease release;

  @override
  State<AndroidUpdateDialog> createState() => _AndroidUpdateDialogState();
}

class _AndroidUpdateDialogState extends State<AndroidUpdateDialog> {
  final CancelToken _cancelToken = CancelToken();

  _AndroidUpdateStage _stage = _AndroidUpdateStage.preparing;
  AndroidReleaseAsset? _androidAsset;
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _cancelToken.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final supportedAbis = await getSupportedAndroidAbis();
      final androidAsset = selectAndroidReleaseAsset(
        widget.release,
        supportedAbis: supportedAbis,
      );
      if (androidAsset == null) {
        throw appLocalizations.updateNoCompatiblePackage;
      }
      _setState(() {
        _androidAsset = androidAsset;
      });

      final expectedSha256 = await request.getExpectedSha256(
        widget.release,
        androidAsset.apkAsset,
      );
      if (expectedSha256 == null) {
        throw appLocalizations.updateChecksumUnavailable;
      }

      final apkPath = await appPath.getUpdateFilePath(androidAsset.apkAsset.name);
      final apkFile = File(apkPath);

      if (await apkFile.exists()) {
        _setStage(_AndroidUpdateStage.verifying);
        final existingSha256 = await computeFileSha256(apkFile);
        if (existingSha256 == expectedSha256) {
          await _openInstaller(apkFile.path);
          return;
        }
        await apkFile.delete();
      }

      final tempPath = '$apkPath.part';
      final tempFile = File(tempPath);
      await tempFile.parent.create(recursive: true);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      _setStage(_AndroidUpdateStage.downloading);
      await request.downloadReleaseAsset(
        androidAsset.apkAsset,
        tempPath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (!mounted) {
            return;
          }
          setState(() {
            _progress = total > 0 ? received / total : null;
          });
        },
      );

      _setStage(_AndroidUpdateStage.verifying);
      final actualSha256 = await computeFileSha256(tempFile);
      if (actualSha256 != expectedSha256) {
        await tempFile.delete();
        throw appLocalizations.updateChecksumMismatch;
      }

      if (await apkFile.exists()) {
        await apkFile.delete();
      }
      await tempFile.rename(apkPath);
      await _openInstaller(apkPath);
    } catch (error) {
      if (_cancelToken.isCancelled || !mounted) {
        return;
      }
      _setState(() {
        _stage = _AndroidUpdateStage.error;
        _progress = null;
        _error = error.toString();
      });
    }
  }

  Future<void> _openInstaller(String path) async {
    _setStage(_AndroidUpdateStage.installing);
    await _stopVpnBeforeInstall();
    final opened = await app?.openFile(path) ?? false;
    if (!opened) {
      throw appLocalizations.updateInstallerError;
    }
    if (!mounted) {
      return;
    }
    globalState.showNotifier(appLocalizations.updateInstallerOpened);
    Navigator.of(context).pop(true);
  }

  Future<void> _stopVpnBeforeInstall() async {
    if (!system.isAndroid) {
      return;
    }
    final runtimeBeforeInstall = await service?.getRunTime();
    if (runtimeBeforeInstall == null) {
      return;
    }
    commonPrint.log(
      'Stopping Android VPN before launching in-app installer',
    );
    await service?.stop();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final runtime = await service?.getRunTime();
      if (runtime == null) {
        return;
      }
    }
    commonPrint.log(
      'Android VPN was still reported as active before installer launch; '
      'continuing with best-effort update flow.',
      logLevel: LogLevel.warning,
    );
  }

  void _setStage(_AndroidUpdateStage stage) {
    _setState(() {
      _stage = stage;
      _progress = null;
      _error = null;
    });
  }

  void _setState(VoidCallback callback) {
    if (!mounted) {
      return;
    }
    setState(callback);
  }

  String get _statusText {
    return switch (_stage) {
      _AndroidUpdateStage.preparing => appLocalizations.updatePreparing,
      _AndroidUpdateStage.downloading => appLocalizations.updateDownloading,
      _AndroidUpdateStage.verifying => appLocalizations.updateVerifying,
      _AndroidUpdateStage.installing => appLocalizations.updateOpeningInstaller,
      _AndroidUpdateStage.error => appLocalizations.updateFailed,
    };
  }

  Widget _buildAssetInfo() {
    final androidAsset = _androidAsset;
    if (androidAsset == null) {
      return const SizedBox.shrink();
    }
    final asset = androidAsset.apkAsset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.release.tagName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(asset.name, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(
          '${androidAsset.abi}  ·  ${asset.size.traffic.show}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    if (_stage != _AndroidUpdateStage.error) {
      return const [];
    }
    return [
      TextButton(
        onPressed: () {
          Navigator.of(context).pop(false);
        },
        child: Text(appLocalizations.cancel),
      ),
      TextButton(
        onPressed: () async {
          Navigator.of(context).pop(false);
          await globalState.openUrl(widget.release.htmlUrl);
        },
        child: Text(appLocalizations.goDownload),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return CommonDialog(
      title: appLocalizations.update,
      overrideScroll: true,
      actions: _buildActions(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAssetInfo(),
          const SizedBox(height: 16),
          Text(_statusText, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          if (_stage != _AndroidUpdateStage.error)
            LinearProgressIndicator(value: progress),
          if (_stage == _AndroidUpdateStage.downloading && progress != null) ...[
            const SizedBox(height: 8),
            Text(
              '${(progress * 100).fixed(decimals: 0)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_stage == _AndroidUpdateStage.error && _error != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
