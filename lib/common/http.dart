import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/controller.dart';

class FlClashHttpOverrides extends HttpOverrides {
  static bool _isLoopbackHost(String host) {
    return {'localhost', localhost, '::1', '[::1]'}.contains(host);
  }

  static String handleFindProxy(Uri url) {
    if (_isLoopbackHost(url.host)) {
      return 'DIRECT';
    }
    final port = appController.config.patchClashConfig.mixedPort;
    final isStart = appController.isStart;
    final vpnEnabled = appController.config.vpnProps.enable;
    commonPrint.log('find $url proxy:$isStart');
    if (!shouldUseLocalProxyForRequests(
      isAndroid: system.isAndroid,
      vpnEnabled: vpnEnabled,
      isStart: isStart,
      port: port,
    )) {
      return 'DIRECT';
    }
    return 'PROXY localhost:$port';
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (_, host, _) => _isLoopbackHost(host);
    client.findProxy = handleFindProxy;
    return client;
  }
}
