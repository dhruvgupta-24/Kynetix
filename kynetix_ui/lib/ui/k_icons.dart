/// Kynetix icon language. One family, one weight, one size scale.
///
/// Every icon in the app is a Material *outlined* glyph (single stroke, the
/// same optical weight), drawn at one of three sizes. Emoji are never used as
/// UI icons. Colour follows the usual rule: neutral (`KColor.textSecondary`)
/// unless the icon carries meaning (fuel, protein, train, danger).
///
/// ## API (stable; other screens build on it)
///
/// Sizes
/// - `KIcons.sm` 16 (inline with caption text), `KIcons.md` 20 (rows, chips),
///   `KIcons.lg` 24 (app bars, primary controls).
///
/// Lookups (all pure, never null)
/// - `KIcons.meal(MealSection s)`      → icon for a meal section.
/// - `KIcons.mealTime(MealSection s)`  → quiet time-of-day hint ("Morning").
/// - `KIcons.workout(WorkoutType t)`   → icon for a workout type.
/// - `KIcons.split(String name)`       → icon for a free-text split day
///                                       ("Chest + Triceps", "Push", "Legs").
/// - Muscle groups have no icon: use `MuscleThumb` (widgets/muscle_body_map.dart),
///   which lights the real muscle on an anatomical body.
/// - `KIcons.food(String name)`        → icon for a food/quick-add name.
///
/// Semantic constants (use these instead of picking ad-hoc icons)
/// - Nutrition: `calories`, `protein`, `carbs`, `fat`, `fiber`, `water`,
///   `plate`, `scan`, `quickAdd`, `library`, `target`.
/// - Training: `train`, `push`, `pull`, `legs`, `upper`, `core`, `cardio`,
///   `rest`, `record` (a personal record), `baseline` (a first-ever set),
///   `history`, `timer`.
/// - Chrome: `add`, `edit`, `delete`, `close`, `back`, `forward`, `prev`,
///   `next`, `calendar`, `settings`, `info`, `done`, `send`, `kyno`.
///
/// Widgets
/// - `KIcon(data, {size, color, semanticLabel})` — an [Icon] at a scale size,
///   neutral by default, excluded from semantics unless labelled.
/// - `KynoMark({size, outlined, color})` — Kyno's monochrome mark: a solid ink
///   disc with a lowercase "k" knocked out (or a hairline ring when
///   [outlined]). Use it wherever Kyno speaks or is summoned. On an ink fill
///   pass `color: KColor.onInk`. Never pair it with a gradient.
/// - `KDot({color, size})` — the 6dp colour dot used in "● 201 kcal" stats.
library;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/day_log.dart';

abstract final class KIcons {
  // ── Size scale ────────────────────────────────────────────────────────────
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;

  // ── Nutrition ─────────────────────────────────────────────────────────────
  static const IconData calories = Icons.local_fire_department_outlined;
  static const IconData protein = Icons.egg_outlined;
  static const IconData carbs = Icons.grain_outlined;
  static const IconData fat = Icons.water_drop_outlined;
  static const IconData fiber = Icons.eco_outlined;
  static const IconData water = Icons.local_drink_outlined;
  static const IconData plate = Icons.restaurant_outlined;
  static const IconData scan = Icons.qr_code_scanner_outlined;
  static const IconData quickAdd = Icons.bolt_outlined;
  static const IconData library = Icons.menu_book_outlined;
  static const IconData target = Icons.track_changes_outlined;

  // ── Training ──────────────────────────────────────────────────────────────
  // Push = a pressing figure, pull = rowing. Bare arrows read as "trending".
  static const IconData train = Icons.fitness_center_outlined;
  // Day types share the dumbbell: Material's figure icons (gymnast, rower,
  // walker) read as the wrong body part.
  static const IconData push = Icons.fitness_center_outlined;
  static const IconData pull = Icons.fitness_center_outlined;
  static const IconData legs = Icons.fitness_center_outlined;
  static const IconData upper = Icons.accessibility_new_outlined;
  static const IconData core = Icons.fitness_center_outlined;
  static const IconData cardio = Icons.directions_run_outlined;
  static const IconData rest = Icons.bedtime_outlined;
  static const IconData record = Icons.workspace_premium_outlined;
  static const IconData baseline = Icons.flag_outlined;
  static const IconData history = Icons.history_outlined;
  static const IconData timer = Icons.timer_outlined;

  // ── Chrome ────────────────────────────────────────────────────────────────
  static const IconData add = Icons.add;
  static const IconData edit = Icons.edit_outlined;
  static const IconData delete = Icons.delete_outline;
  static const IconData close = Icons.close;
  static const IconData back = Icons.arrow_back;
  static const IconData forward = Icons.arrow_forward;
  static const IconData prev = Icons.chevron_left;
  static const IconData next = Icons.chevron_right;
  static const IconData calendar = Icons.calendar_today_outlined;
  static const IconData settings = Icons.settings_outlined;
  static const IconData info = Icons.info_outline;
  static const IconData done = Icons.check;
  static const IconData send = Icons.arrow_upward;
  static const IconData kyno = Icons.chat_bubble_outline;

  // ── Lookups ───────────────────────────────────────────────────────────────

  static IconData meal(MealSection s) => switch (s) {
        MealSection.breakfast => Icons.wb_twilight_outlined,
        MealSection.lunch => Icons.light_mode_outlined,
        MealSection.eveningSnack => Icons.coffee_outlined,
        MealSection.dinner => Icons.dark_mode_outlined,
        MealSection.lateNight => Icons.bedtime_outlined,
      };

  /// A quiet time-of-day hint shown beside a meal section's name.
  static String mealTime(MealSection s) => switch (s) {
        MealSection.breakfast => 'Morning',
        MealSection.lunch => 'Midday',
        MealSection.eveningSnack => 'Evening',
        MealSection.dinner => 'Night',
        MealSection.lateNight => 'Late',
      };

  static IconData workout(WorkoutType t) => switch (t) {
        WorkoutType.push => push,
        WorkoutType.pull => pull,
        WorkoutType.legs => legs,
        WorkoutType.upper => upper,
        WorkoutType.cardio => cardio,
        WorkoutType.rest => rest,
        WorkoutType.other => train,
      };

  /// Icon for a free-text split day such as "Chest + Triceps" or "Pull".
  static IconData split(String name) =>
      workout(WorkoutType.fromSplitName(name));

  static IconData food(String name) {
    final n = name.toLowerCase();
    if (n.contains('egg')) return Icons.egg_outlined;
    if (n.contains('whey') || n.contains('shake') || n.contains('milk') ||
        n.contains('lassi') || n.contains('smoothie') || n.contains('juice')) {
      return Icons.local_drink_outlined;
    }
    if (n.contains('chai') || n.contains('tea') || n.contains('coffee')) {
      return Icons.coffee_outlined;
    }
    if (n.contains('rice') || n.contains('dal') || n.contains('curry') ||
        n.contains('khichdi') || n.contains('poha') || n.contains('oats')) {
      return Icons.rice_bowl_outlined;
    }
    if (n.contains('roti') || n.contains('bread') || n.contains('paratha') ||
        n.contains('biscuit') || n.contains('toast')) {
      return Icons.bakery_dining_outlined;
    }
    if (n.contains('banana') || n.contains('apple') || n.contains('fruit')) {
      return Icons.spa_outlined;
    }
    return plate;
  }
}

/// An [Icon] on the Kynetix scale. Neutral unless given a colour; decorative
/// (excluded from semantics) unless given a [semanticLabel].
class KIcon extends StatelessWidget {
  const KIcon(this.icon, {super.key, this.size = KIcons.md, Color? color, this.semanticLabel})
      : _color = color;

  final IconData icon;
  final double size;
  final Color? _color;
  Color get color => _color ?? KColor.textSecondary;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final i = Icon(icon, size: size, color: color, semanticLabel: semanticLabel);
    return semanticLabel == null ? ExcludeSemantics(child: i) : i;
  }
}

/// The small colour dot that keys a number to its meaning: "● 201 kcal".
class KDot extends StatelessWidget {
  const KDot({super.key, Color? color, this.size = 6}) : _color = color;
  final Color? _color;
  Color get color => _color ?? KColor.textMuted;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      );
}

/// Kyno's mark: a monochrome ink disc with a lowercase "k" knocked out of it.
/// [outlined] draws a hairline ring with an ink "k" instead, for places where
/// a solid disc would be too loud (inline in text, list rows).
class KynoMark extends StatelessWidget {
  const KynoMark({super.key, this.size = 28, this.outlined = false, Color? color})
      : _color = color;

  final double size;
  final bool outlined;
  final Color? _color;
  Color get color => _color ?? KColor.ink;

  @override
  Widget build(BuildContext context) {
    final letter = Text(
      'k',
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontFamily: KText.family,
        fontWeight: FontWeight.w800,
        fontSize: size * 0.62,
        height: 1.0,
        letterSpacing: 0,
        color: outlined ? color : (color == KColor.ink ? KColor.onInk : KColor.ink),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: outlined ? null : color,
            border: outlined
                ? Border.all(color: color.withValues(alpha: 0.55), width: 1.2)
                : null,
          ),
          // Optical centring: the "k" has an ascender and no descender.
          child: Padding(
            padding: EdgeInsets.only(bottom: size * 0.06, left: size * 0.02),
            child: Center(child: letter),
          ),
        ),
      ),
    );
  }
}
