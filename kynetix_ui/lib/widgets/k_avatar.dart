import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/profile_service.dart';
import '../services/avatar_service.dart';
import '../services/day_fuel.dart';
import '../services/persistence_service.dart';
import '../services/workout_service.dart';

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

/// The avatar wearing today's rings: calories outside, protein inside, the
/// same numbers the dashboard's fuel card prints, each capped at a full lap.
/// The rings follow meals as they are logged (eased, only when a number
/// changes); [face] draws the picture inside them, [KAvatar] by default.
class KFuelAvatar extends StatelessWidget {
  const KFuelAvatar({super.key, required this.size, this.stroke = 1.6, this.face});

  /// Outer size, rings included.
  final double size;
  final double stroke;

  /// Builds the picture at the size left inside the rings.
  final Widget Function(double faceSize)? face;

  /// The ring change: long enough to see the arc move, short enough to read
  /// as an answer to the meal that moved it.
  static const Duration arcDuration = Duration(milliseconds: 600);

  /// Width the two rings and their gaps take from each side. Mirrors the
  /// ring painter: outer stroke, a 0.42 gap, an inner ring at 0.78, then
  /// one more gap before the picture.
  static double ringBand(double stroke) => stroke * (1 + 0.42 + 0.78 + 0.42) + 1;

  @override
  Widget build(BuildContext context) {
    final faceSize = size - 2 * ringBand(stroke);
    final inner = face?.call(faceSize) ?? KAvatar(size: faceSize);
    return ListenableBuilder(
      listenable: Listenable.merge([PersistenceService.dayLogNotifier, WorkoutService.instance]),
      // The picture is built once and handed through, so a meal change
      // repaints the rings only.
      child: inner,
      builder: (context, child) {
        final fuel = DayFuel.of(DateTime.now());
        return KDabbaRings(
          size: size,
          stroke: stroke,
          sweepIn: false,
          duration: arcDuration,
          curve: KMotion.easeOut,
          track: KColor.track.withValues(alpha: KColor.track.a * 0.5),
          rings: [
            KRingSpec(fuel.kcalRatio.clamp(0.0, 1.0), KRingColors.calories),
            KRingSpec(fuel.proteinRatio.clamp(0.0, 1.0), KRingColors.protein),
          ],
          child: child,
        );
      },
    );
  }
}
