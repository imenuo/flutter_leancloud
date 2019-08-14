import 'dart:async';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import './im.dart';

class FlutterLeanCloud {
  static final Logger _logger = Logger('FlutterLeanCloud');
  static final FlutterLeanCloud _instance = new FlutterLeanCloud._internal();

  final MethodChannel _channel;
  final EventChannel _eventChannel;
  StreamSubscription _eventChannelSubscription;

  static Future<String> get platformVersion async {
    return 'stub';
  }

  FlutterLeanCloud._internal()
      : _channel = const MethodChannel('flutter_leancloud'),
        _eventChannel = const EventChannel('flutter_leancloud/event') {
    _channel.setMethodCallHandler(_methodCall);
  }

  factory FlutterLeanCloud() {
    return _instance;
  }

  static FlutterLeanCloud get() => _instance;

  Future<AVIMClient> avIMClientGetInstance(String clientId) =>
      AVIMClient.getInstance(_channel, clientId);

  Future<void> avIMClientRegisterMessageHandler() =>
      AVIMClient.registerMessageHandler(_channel);

  Future<void> avIMClientUnregisterMessageHandler() =>
      AVIMClient.unregisterMessageHandler(_channel);

  Future<void> clearEventBuffer() =>
      _channel.invokeMethod('_clearEventBuffer', null);

  void registerEventHandler() {
    if (_eventChannelSubscription != null) return;
    _eventChannelSubscription =
        _eventChannel.receiveBroadcastStream().listen(_onEvent);
  }

  void unregisterEventHandler() {
    _eventChannelSubscription?.cancel();
    _eventChannelSubscription = null;
  }

  Future<dynamic> _methodCall(MethodCall methodCall) async {
    methodCall.noSuchMethod(null);
    _logger.warning('missing handler for message: $methodCall');
  }

  void _onEvent(payload) {
    if (payload is! Map) {
      _logger.warning('expect Map, got ${payload.runtimeType}');
      return;
    }

    var event = payload['event'] as String;
    var data = payload['data'];

    if (event.startsWith('avIMClient_')) {
      AVIMClient.handleEvent(event, data);
    }
  }
}
