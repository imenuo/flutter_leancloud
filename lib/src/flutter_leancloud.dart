import 'dart:async';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import './im.dart';

class FlutterLeanCloud {
  static const MethodChannel _channel =
      const MethodChannel('flutter_leancloud');
  static final Logger _logger = Logger('FlutterLeanCloud');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  static Future<void> initialize(String appId, String appKey) async {
    _channel.setMethodCallHandler(_methodCall);
    await _channel.invokeMethod('initialize', <String>[appId, appKey]);
  }

  static Future<void> setDebugLogEnabled(bool enabled) async {
    await _channel.invokeMethod('setDebugLogEnabled', enabled);
  }

  static Future<AVIMClient> avIMClientGetInstance(String clientId) =>
      AVIMClient.getInstance(_channel, clientId);

  static Future<dynamic> _methodCall(MethodCall methodCall) async {
    var method = methodCall.method;
    if (method.startsWith('avIMClient_')) {
      String clientId = methodCall.arguments['_clientId'];
      AVIMClient client = await avIMClientGetInstance(clientId);
      return await client.onMethodCall(methodCall);
    }

    _logger.warning('missing handler for message: $methodCall');
  }
}
