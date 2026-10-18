import 'dart:io' show Platform;

/// `flutter test` sets FLUTTER_TEST=true in the test process environment.
final bool isRunningInFlutterTest =
    Platform.environment['FLUTTER_TEST'] == 'true';
