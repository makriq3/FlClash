import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/controller.dart';

class FlClashHttpOverrides extends HttpOverrides {
  static String handleFindProxy(Uri url) {
    if ({localhost, '::1', '[::1]'}.contains(url.host)) {
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
    client.badCertificateCallback = (_, _, _) => true;
    client.findProxy = handleFindProxy;
    return client;
  }
}
