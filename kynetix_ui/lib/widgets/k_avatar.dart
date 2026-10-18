import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/profile_service.dart';
import '../services/avatar_service.dart';

/// The person's picture in a circle: their photo, else the Google account
/// picture, else the first letter of their name.
class KAvatar extends StatelessWidget {
  const KAvatar({super.key, required this.size, this.ring});

  final double size;

  /// Draws a ring of this colour around the picture (used by the nav bar).
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: AvatarService.instance.photo,
      builder: (context, bytes, _) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final px = (size * dpr).round();
        final url = AvatarService.instance.accountPhotoUrl;
        final name = ProfileService.instance.currentUserProfile?.name.trim() ?? '';
        final letter = Center(
          child: Text(
            name.isEmpty ? 'K' : name[0].toUpperCase(),
            style: KText.h3.copyWith(
              fontFamily: KText.displayFace,
              fontSize: size * 0.42,
              height: 1,
              fontWeight: FontWeight.w600,
              color: KColor.textPrimary,
            ),
          ),
        );
        Widget child;
        if (bytes != null) {
          child = Image.memory(bytes, fit: BoxFit.cover, cacheWidth: px, gaplessPlayback: true);
        } else if (url != null) {
          child = Image.network(url, fit: BoxFit.cover, cacheWidth: px, errorBuilder: (_, _, _) => letter);
        } else {
          child = letter;
        }
        return Container(
          width: size,
          height: size,
          padding: ring == null ? null : EdgeInsets.all(size * 0.06),
          decoration: ring == null ? null : BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: 1.6)),
          child: ClipOval(
            child: ColoredBox(color: KColor.cardHigh, child: SizedBox.expand(child: child)),
          ),
        );
      },
    );
  }
}
