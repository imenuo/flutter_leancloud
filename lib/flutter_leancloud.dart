import 'dart:async';

import 'package:flutter/services.dart';

class FlutterLeanCloud {
  static const MethodChannel _channel =
      const MethodChannel('flutter_leancloud');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
