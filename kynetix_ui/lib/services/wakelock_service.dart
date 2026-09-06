import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Manages keeping the device screen on during active workout sessions.
/// Safe across all platforms and test environments.
class WakelockService {
  WakelockService._();
  static final WakelockService instance = WakelockService._();

  static const MethodChannel _channel = MethodChannel('com.kynetix.app/wakelock');
  bool _isEnabled = false;

  bool get isEnabled => _isEnabled;

  /// Enable wakelock (keep screen on during workout)
  Future<void> enable() async {
    _isEnabled = true;
    try {
      if (!kIsWeb) {
        await _channel.invokeMethod('enable');
      }
    } catch (e) {
      // Graceful fallback if native channel is unattached (e.g. tests/desktop)
      debugPrint('[WakelockService] Native enable not available: $e');
    }
  }

  /// Disable wakelock (restore normal screen timeout)
  Future<void> disable() async {
    _isEnabled = false;
    try {
      if (!kIsWeb) {
        await _channel.invokeMethod('disable');
      }
    } catch (e) {
      debugPrint('[WakelockService] Native disable not available: $e');
    }
  }
}
