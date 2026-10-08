import 'package:flutter/services.dart';

class WatchBridge {
  WatchBridge._();
  static const _channel = MethodChannel('gymmane/watch');

  static Future<bool> _send(String command, String sessionId) async {
    try {
      return await _channel.invokeMethod<bool>(command, {'sessionId': sessionId}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> start(String sessionId) => _send('start', sessionId);
  static Future<bool> pause(String sessionId) => _send('pause', sessionId);
  static Future<bool> resume(String sessionId) => _send('resume', sessionId);
  static Future<bool> stop(String sessionId) => _send('stop', sessionId);
}
