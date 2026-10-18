import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens this app's page in the system settings, so a person who refused the
/// camera can allow it. Returns false when the platform could not open it;
/// the caller then tells them where to go instead.
///
/// - iOS: the `app-settings:` URL.
/// - Android: the `openAppSettings` call on `com.kynetix.app/settings`
///   (Settings.ACTION_APPLICATION_DETAILS_SETTINGS). Until that handler is in
///   MainActivity this returns false and the caller shows the path in words.
class BarcodeAppSettings {
  BarcodeAppSettings._();

  static const channel = MethodChannel('com.kynetix.app/settings');

  static Future<bool> open() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isIOS) {
        return await launchUrl(Uri.parse('app-settings:'));
      }
      final ok = await channel.invokeMethod<bool>('openAppSettings');
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Where to go by hand when [open] could not do it.
  static const manualPath =
      'Open Settings, then Apps, Kynetix, Permissions, and allow Camera.';
}
