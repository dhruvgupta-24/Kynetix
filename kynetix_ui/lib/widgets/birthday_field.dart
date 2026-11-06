import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../config/app_theme.dart';
import '../models/user_profile.dart';

/// Kynetix is for 18 and up (India's DPDP Act asks for a parent's consent
/// below that). The age comes from the birthday, never from a tick box.
const kMinimumAge = 18;

/// Where a picked birthday stands.
enum BirthdayStatus { missing, ok, tooYoung, implausible }

BirthdayStatus birthdayStatus(DateTime? dob, {DateTime? now}) {
  if (dob == null) return BirthdayStatus.missing;
  final age = UserProfile.ageOn(dob, now ?? DateTime.now());
  if (age < kMinimumAge) return BirthdayStatus.tooYoung;
  if (age > 100) return BirthdayStatus.implausible;
  return BirthdayStatus.ok;
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatBirthday(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "When's your birthday?": one tap opens a year-first date picker. Says, in
/// the app's own voice, that the real date is all we want, then shows the
/// age it works out (or why it can't go on).
class BirthdayField extends StatelessWidget {
  const BirthdayField({super.key, required this.value, required this.onChanged, this.enabled = true});

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime(now.year - 24, now.month, 1),
      firstDate: DateTime(now.year - 110),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'YOUR BIRTHDAY',
      confirmText: 'That\'s the one',
      cancelText: 'Not now',
      // Day first, the way India writes dates (06/11/1999 is 6 November).
      // The app itself runs in plain English; only the picker switches.
      builder: (context, child) => Localizations.override(
        context: context,
        locale: const Locale('en', 'IN'),
        delegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        child: child!,
      ),
    );
    if (picked != null) {
      KHaptics.select();
      onChanged(DateTime(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = birthdayStatus(value);
    final age = value == null ? null : UserProfile.ageOn(value!, DateTime.now());
    final note = switch (status) {
      BirthdayStatus.missing =>
        'The real one. No fake ages here, this isn\'t that kind of app. We do the maths, and we might show up on the day.',
      BirthdayStatus.ok => 'That makes you $age. Noted, and the date is saved for later.',
      BirthdayStatus.tooYoung =>
        'Kynetix is built for $kMinimumAge and up for now. Come back on your ${kMinimumAge}th, we\'ll keep the lights on.',
      BirthdayStatus.implausible => 'That\'s a legendary birthday. Double check the year?',
    };
    final bad = status == BirthdayStatus.tooYoung || status == BirthdayStatus.implausible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: value == null ? 'Pick your birthday' : 'Birthday, ${formatBirthday(value!)}. Tap to change',
          excludeSemantics: true,
          child: InkWell(
            key: const ValueKey('birthday-field'),
            borderRadius: KRadius.md,
            onTap: enabled ? () => _pick(context) : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg, vertical: KSpacing.md),
              decoration: BoxDecoration(
                gradient: KShade.sunken(KColor.card),
                borderRadius: KRadius.md,
                border: Border.all(color: bad ? KColor.danger : KColor.hairline),
              ),
              child: Row(
                children: [
                  Icon(Icons.cake_outlined, size: 20, color: value == null ? KColor.textMuted : KColor.ember),
                  const SizedBox(width: KSpacing.md),
                  Expanded(
                    child: Text(
                      value == null ? 'Pick your birthday' : formatBirthday(value!),
                      style: KText.bodyMedium.copyWith(
                        fontSize: 16,
                        color: value == null ? KColor.textMuted : KColor.textPrimary,
                        fontWeight: value == null ? FontWeight.w500 : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (age != null && status == BirthdayStatus.ok)
                    Text('$age', style: KText.numSmall.copyWith(fontSize: 16, color: KColor.textSecondary)),
                  const SizedBox(width: KSpacing.xs),
                  Icon(Icons.expand_more_rounded, size: 20, color: KColor.textMuted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: KSpacing.sm),
        Semantics(
          liveRegion: true,
          child: Text(
            note,
            style: KText.caption.copyWith(
              color: bad ? KColor.danger : KColor.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
