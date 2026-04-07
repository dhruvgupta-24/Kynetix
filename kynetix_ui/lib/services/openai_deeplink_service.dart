import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// App-level singleton that listens for kynetix://openai-auth/callback deep links.
/// Lives for the entire app lifetime — ProfileScreen reads from it.
class OpenAiDeepLinkService {
  OpenAiDeepLinkService._();
  static final instance = OpenAiDeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  /// Notifies whenever a valid openai-auth callback URI arrives.
  final pending = ValueNotifier<Uri?>(null);

  void init() {
    debugPrint('[AI DEEPLINK] service init()');

    // Warm-start: app already running, Android fires onNewIntent
    _sub = _appLinks.uriLinkStream.listen((uri) {
      debugPrint('[AI DEEPLINK] uriLinkStream event: $uri');
      _maybeNotify(uri);
    });

    // Cold/resume start: app was killed or was in the background
    _appLinks.getInitialLink().then((uri) {
      debugPrint('[AI DEEPLINK] getInitialLink: $uri');
      if (uri != null) _maybeNotify(uri);
    }).catchError((e) {
      debugPrint('[AI DEEPLINK] getInitialLink error: $e');
    });
  }

  void _maybeNotify(Uri uri) {
    if (uri.scheme == 'kynetix' &&
        uri.host == 'openai-auth' &&
        uri.path == '/callback') {
      debugPrint('[AI DEEPLINK] matched callback — notifying listeners');
      pending.value = uri;
    } else {
      debugPrint('[AI DEEPLINK] URI did not match openai-auth/callback: $uri');
    }
  }

  /// Call after the callback has been consumed so it doesn't replay.
  void consume() {
    pending.value = null;
  }

  void dispose() {
    _sub?.cancel();
  }
}
