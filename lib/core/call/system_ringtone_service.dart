import 'package:flutter/services.dart';

class SystemRingtoneService {
  static const MethodChannel _channel =
      MethodChannel('hiddenly/system_ringtone');

  static Future<void> start() async {
    try {
      await _channel.invokeMethod('start');
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}