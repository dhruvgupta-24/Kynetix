import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/kyno_notes_service.dart';

/// "What Kyno remembers": short standing notes sent with every question.
Future<void> showKynoNotesSheet(BuildContext context) {
  return showKSheet<void>(context: context, builder: (_) => const _KynoNotesSheet());
}

class _KynoNotesSheet extends StatefulWidget {
  const _KynoNotesSheet();

  @override
  State<_KynoNotesSheet> createState() => _KynoNotesSheetState();
}

class _KynoNotesSheetState extends State<_KynoNotesSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  static const _ideas = [
    'Vegetarian on Tuesdays and Thursdays',
    'Left knee hurts on deep squats',
    "I don't take whey",
    'I eat at my hostel mess on weekdays',
    'Training for a 10K in December',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add(String text) async {
    final ok = await KynoNotesService.instance.add(text);
    if (!mounted) return;
    if (ok) {
      KHaptics.commit();
      _ctrl.clear();
    } else {
      KHaptics.reject();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: KSpacing.md),
          child: ValueListenableBuilder<List<String>>(
            valueListenable: KynoNotesService.instance.notes,
            builder: (context, notes, _) {
              final full = notes.length >= KynoNotesService.maxNotes;
              final unused = _ideas.where((i) => !notes.any((n) => n.toLowerCase() == i.toLowerCase())).take(3).toList();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const KSheetHeader(
                    'What Kyno remembers',
                    subtitle: 'Short notes Kyno keeps in mind in every answer. They stay on this phone.',
                  ),
                  const SizedBox(height: KSpacing.md),
                  if (notes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                      child: Text(
                        'Nothing yet. Add diet days, injuries, foods you skip, or what you are training for.',
                        style: KText.body.copyWith(color: KColor.textSecondary),
                      ),
                    ),
                  for (final n in notes)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(KSpacing.p, 0, KSpacing.sm, 0),
                      child: Row(
                        children: [
                          Icon(Icons.push_pin_outlined, size: 16, color: KColor.kyno),
                          const SizedBox(width: KSpacing.sm),
                          Expanded(child: Text(n, style: KText.body)),
                          IconButton(
                            tooltip: 'Forget "$n"',
                            icon: Icon(Icons.close_rounded, size: 18, color: KColor.textMuted),
                            onPressed: () {
                              KHaptics.select();
                              KynoNotesService.instance.remove(n);
                            },
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: KSpacing.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      enabled: !full,
                      maxLength: KynoNotesService.maxLength,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onSubmitted: _add,
                      decoration: InputDecoration(
                        hintText: full ? 'That is the limit. Remove one to add another.' : 'Add a note for Kyno',
                        suffixIcon: IconButton(
                          tooltip: 'Add note',
                          icon: Icon(Icons.add_rounded, color: KColor.kyno),
                          onPressed: full ? null : () => _add(_ctrl.text),
                        ),
                      ),
                    ),
                  ),
                  if (!full && unused.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(KSpacing.p, 0, KSpacing.p, KSpacing.md),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final i in unused)
                            ActionChip(
                              label: Text(i, style: KText.caption.copyWith(color: KColor.textSecondary)),
                              onPressed: () {
                                _ctrl.text = i;
                                _focus.requestFocus();
                              },
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
