import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/cupertino.dart';

class Request {
  late final Dio dio;
  late final Dio _clashDio;
  String? userAgent;

  Request() {
    dio = Dio(BaseOptions(headers: {'User-Agent': browserUa}));
    _clashDio = Dio();
    _clashDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (Uri uri) {
          client.userAgent = appController.ua;
          return FlClashHttpOverrides.handleFindProxy(uri);
        };
        return client;
      },
    );
  }

  Future<Response<Uint8List>> getFileResponseForUrl(String url) async {
    try {
      return await _clashDio.get<Uint8List>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
    } catch (e) {
      commonPrint.log('getFileResponseForUrl error ${e.toString()}');
      if (e is DioException) {
        if (e.type == DioExceptionType.unknown) {
          throw appLocalizations.unknownNetworkError;
        } else if (e.type == DioExceptionType.badResponse) {
          throw appLocalizations.networkException;
        }
        rethrow;
      }
      throw appLocalizations.unknownNetworkError;
    }
  }

  Future<Response<String>> getTextResponseForUrl(String url) async {
    final response = await _clashDio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return response;
  }

  Future<MemoryImage?> getImage(String url) async {
    if (url.isEmpty) return null;
    final response = await dio.get<Uint8List>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null) return null;
    return MemoryImage(data);
  }

  Future<AppRelease?> getLatestRelease() async {
    return getLatestReleaseForChannel(includePrerelease: false);
  }

  Future<List<AppRelease>> getReleases({int perPage = 100}) async {
    final response = await dio
        .get(
          'https://api.github.com/repos/$repository/releases',
          queryParameters: {'per_page': perPage},
          options: Options(responseType: ResponseType.json),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || response.data is! List) {
      return const [];
    }
    return (response.data as List)
        .whereType<Map<String, dynamic>>()
        .map(AppRelease.fromJson)
        .toList(growable: false);
  }

  Future<AppRelease?> getLatestReleaseForChannel({
    required bool includePrerelease,
  }) async {
    if (includePrerelease) {
      final releases = await getReleases();
      return selectLatestRelease(releases, includePrerelease: true);
    }
    final response = await dio
        .get(
          'https://api.github.com/repos/$repository/releases/latest',
          options: Options(responseType: ResponseType.json),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || response.data is! Map<String, dynamic>) {
      return null;
    }
    return AppRelease.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AppRelease?> checkForUpdate({bool includePrerelease = false}) async {
    try {
      final release = await getLatestReleaseForChannel(
        includePrerelease: includePrerelease,
      );
      if (release == null) return null;
      final version = globalState.packageInfo.version;
      final hasUpdate =
          utils.compareVersions(release.version, version) > 0;
      if (!hasUpdate) return null;
      return release;
    } catch (e) {
      commonPrint.log('checkForUpdate failed', logLevel: LogLevel.warning);
      return null;
    }
  }

  Future<String?> getExpectedSha256(
    AppRelease release,
    ReleaseAsset asset,
  ) async {
    final digest = asset.sha256Digest;
    if (digest != null) {
      return digest;
    }
    final checksumAsset = release.findSha256AssetFor(asset);
    if (checksumAsset == null) {
      return null;
    }
    try {
      final response = await dio
          .get<String>(
            checksumAsset.browserDownloadUrl,
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(const Duration(seconds: 20));
      return parseSha256Content(response.data);
    } catch (error) {
      if (error is DioException) {
        if (error.type == DioExceptionType.cancel) {
          rethrow;
        }
        throw appLocalizations.networkException;
      }
      rethrow;
    }
  }

  Future<File> downloadReleaseAsset(
    ReleaseAsset asset,
    String savePath, {
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final file = File(savePath);
    await file.parent.create(recursive: true);
    if (await file.exists()) {
      await file.delete();
    }
    try {
      await dio.download(
        asset.browserDownloadUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
    } catch (error) {
      await file.safeDelete();
      if (error is DioException) {
        if (error.type == DioExceptionType.cancel) {
          rethrow;
        }
        throw appLocalizations.networkException;
      }
      rethrow;
    }
    return file;
  }

  final Map<String, IpInfo Function(Map<String, dynamic>)> _ipInfoSources = {
    'https://ipwho.is': IpInfo.fromIpWhoIsJson,
    'https://api.myip.com': IpInfo.fromMyIpJson,
    'https://ipapi.co/json': IpInfo.fromIpApiCoJson,
    'https://ident.me/json': IpInfo.fromIdentMeJson,
    'http://ip-api.com/json': IpInfo.fromIpAPIJson,
    'https://api.ip.sb/geoip': IpInfo.fromIpSbJson,
    'https://ipinfo.io/json': IpInfo.fromIpInfoIoJson,
  };

  Future<Result<IpInfo?>> checkIp({CancelToken? cancelToken}) async {
    var failureCount = 0;
    final token = cancelToken ?? CancelToken();
    final futures = _ipInfoSources.entries.map((source) async {
      final Completer<Result<IpInfo?>> completer = Completer();
      handleFailRes() {
        if (!completer.isCompleted && failureCount == _ipInfoSources.length) {
          completer.complete(Result.success(null));
        }
      }

      final future = dio
          .get<Map<String, dynamic>>(
            source.key,
            cancelToken: token,
            options: Options(responseType: ResponseType.json),
          )
          .timeout(const Duration(seconds: 10));
      future
          .then((res) {
            if (res.statusCode == HttpStatus.ok && res.data != null) {
              completer.complete(Result.success(source.value(res.data!)));
              return;
            }
            failureCount++;
            handleFailRes();
          })
          .catchError((e) {
            failureCount++;
            if (e is DioException && e.type == DioExceptionType.cancel) {
              completer.complete(Result.error('cancelled'));
            }
            handleFailRes();
          });
      return completer.future;
    });
    final res = await Future.any(futures);
    token.cancel();
    return res;
  }

  Future<bool> pingHelper() async {
    try {
      final response = await dio
          .get(
            'http://$localhost:$helperPort/ping',
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(const Duration(milliseconds: 2000));
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      return (response.data as String) == globalState.coreSHA256;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startCoreByHelper(String arg) async {
    try {
      final response = await dio
          .post(
            'http://$localhost:$helperPort/start',
            data: jsonEncode({'path': appPath.corePath, 'arg': arg}),
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(const Duration(milliseconds: 2000));
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final data = response.data as String;
      return data.isEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopCoreByHelper() async {
    try {
      final response = await dio
          .post(
            'http://$localhost:$helperPort/stop',
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(const Duration(milliseconds: 2000));
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final data = response.data as String;
      return data.isEmpty;
    } catch (_) {
      return false;
    }
  }
}

final request = Request();
