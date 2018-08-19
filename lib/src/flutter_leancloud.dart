import 'dart:async';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import './im.dart';

class FlutterLeanCloud {
  static final Logger _logger = Logger('FlutterLeanCloud');
  static FlutterLeanCloud _instance;

  final MethodChannel _channel;

  static Future<String> get platformVersion async {
    return 'stub';
  }

  FlutterLeanCloud._internal()
      : _channel = const MethodChannel('flutter_leancloud') {
    _channel.setMethodCallHandler(_methodCall);
  }

  factory FlutterLeanCloud() {
    if (_instance == null) _instance = FlutterLeanCloud._internal();
    return _instance;
  }

  static FlutterLeanCloud get() => new FlutterLeanCloud();

  Future<AVIMClient> avIMClientGetInstance(String clientId) =>
      AVIMClient.getInstance(_channel, clientId);

  Future<void> avIMClientRegisterMessageHandler() =>
      AVIMClient.registerMessageHandler(_channel);

  Future<dynamic> _methodCall(MethodCall methodCall) async {
    var method = methodCall.method;
    var args = methodCall.arguments;
    if (method == 'avIMClient_messageHandler_onMessage') {
      await AVIMClient.handleMessageHandlerOnMessage(args);
      return null;
    } else if (method.startsWith('avIMClient_')) {
      String clientId = methodCall.arguments['_clientId'];
      AVIMClient client = await avIMClientGetInstance(clientId);
      return await client.onClientMethodCall(methodCall);
    }

    _logger.warning('missing handler for message: $methodCall');
  }
}
