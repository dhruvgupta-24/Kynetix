import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Manages keeping the device screen on during active workout sessions.
/// Safe across all platforms and test environments.
class WakelockService {
  WakelockService._();
  static final WakelockService instance = WakelockService._();

  static const MethodChannel _channel = MethodChannel('com.kynetix.app/wakelock');
  bool _isEnabled = false;

  bool get isEnabled => _isEnabled;

  static bool get _isTestEnvironment {
    return WidgetsBinding.instance.runtimeType.toString().contains('Test');
  }

  /// Enable wakelock (keep screen on during workout) - idempotent
  Future<void> enable() async {
    if (_isEnabled) return;
    _isEnabled = true;
    try {
      if (!kIsWeb && !_isTestEnvironment) {
        await _channel.invokeMethod('enable').timeout(const Duration(seconds: 2));
      }
    } catch (e) {
      // Graceful fallback if native channel is unattached (e.g. tests/desktop)
      debugPrint('[WakelockService] Native enable not available: $e');
    }
  }

  /// Disable wakelock (restore normal screen timeout) - idempotent
  Future<void> disable() async {
    if (!_isEnabled) return;
    _isEnabled = false;
    try {
      if (!kIsWeb && !_isTestEnvironment) {
        await _channel.invokeMethod('disable').timeout(const Duration(seconds: 2));
      }
    } catch (e) {
      debugPrint('[WakelockService] Native disable not available: $e');
    }
  }
}
