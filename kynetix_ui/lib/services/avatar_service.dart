import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'internal/scoped_prefs.dart';

/// The person's profile picture.
///
/// Kept on the phone (per user, so accounts never see each other's photo)
/// and backed up to the private `avatars` storage bucket at
/// `<user id>/avatar.jpg`, so it follows the account to a new phone. Until a
/// photo is set, the Google account picture is used when there is one.
class AvatarService {
  AvatarService._();
  static final AvatarService instance = AvatarService._();

  static const bucket = 'avatars';
  static const _kKey = 'profile_avatar_v1';

  /// The photo's JPEG bytes, or null when none is set.
  final ValueNotifier<Uint8List?> photo = ValueNotifier(null);

  String? _userId;
  SharedPreferences? _prefs;

  String? get _objectPath => _userId == null ? null : '$_userId/avatar.jpg';

  Future<void> initForUser(String userId, {SharedPreferences? prefsOverride}) async {
    _userId = userId;
    _prefs = prefsOverride ?? await SharedPreferences.getInstance();
    final b64 = _prefs!.getString(ScopedPrefs.key(_kKey, userId));
    Uint8List? bytes;
    if (b64 != null) {
      try {
        bytes = base64Decode(b64);
      } catch (_) {}
    }
    photo.value = bytes;
    if (bytes == null) unawaited(_pull(userId));
  }

  void clearMemory() {
    _userId = null;
    photo.value = null;
  }

  /// The account picture from Google sign-in, when there is one.
  String? get accountPhotoUrl {
    try {
      final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
      final url = meta?['avatar_url'] ?? meta?['picture'];
      return url is String && url.isNotEmpty ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// Saves [jpeg] as the photo here and in the cloud. The local copy is set
  /// first, so the new photo shows at once even when the upload is slow.
  Future<void> setPhoto(Uint8List jpeg) async {
    final uid = _userId;
    if (uid == null) return;
    photo.value = jpeg;
    await _prefs?.setString(ScopedPrefs.key(_kKey, uid), base64Encode(jpeg));
    try {
      await Supabase.instance.client.storage.from(bucket).uploadBinary(
            '$uid/avatar.jpg',
            jpeg,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
    } catch (e) {
      debugPrint('[AvatarService] upload failed (kept on this phone): $e');
    }
  }

  /// Removes the photo here and in the cloud.
  Future<void> removePhoto() async {
    final uid = _userId;
    if (uid == null) return;
    photo.value = null;
    await _prefs?.remove(ScopedPrefs.key(_kKey, uid));
    try {
      await Supabase.instance.client.storage.from(bucket).remove(['$uid/avatar.jpg']);
    } catch (e) {
      debugPrint('[AvatarService] remove failed: $e');
    }
  }

  Future<void> _pull(String userId) async {
    final path = _objectPath;
    if (path == null) return;
    try {
      final data = await Supabase.instance.client.storage
          .from(bucket)
          .download(path)
          .timeout(const Duration(seconds: 12));
      // The account may have changed while the download ran.
      if (_userId != userId || data.isEmpty) return;
      photo.value = data;
      await _prefs?.setString(ScopedPrefs.key(_kKey, userId), base64Encode(data));
    } catch (_) {
      // No photo in the cloud yet, offline, or no Supabase in tests.
    }
  }
}
