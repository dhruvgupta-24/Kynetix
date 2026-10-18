// Fasting timer card: start a 16:8 or a vrat, watch the ring fill, end it.
//
// The ring and the clock read from [FastingService]; a 30-second ticker
// (only while a fast runs, only while mounted) moves the numbers. Logging a
// meal ends a no-food fast on its own, and the card offers to resume it.

import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/fasting_service.dart';

class FastingCard extends StatefulWidget {
  const FastingCard({super.key, this.service, this.now});

  /// Defaults to [FastingService.instance]; injectable for tests.
  final FastingService? service;

  /// Fixed clock for tests (also stops the ticker).
  final DateTime Function()? now;

  @override
  State<FastingCard> createState() => _FastingCardState();
}

class _FastingCardState extends State<FastingCard> {
  FastingService get _svc => widget.service ?? FastingService.instance;
  DateTime _now() => widget.now?.call() ?? DateTime.now();

  late final ValueNotifier<DateTime> _clock = ValueNotifier(_now());
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _svc.state.addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void dispose() {
    _svc.state.removeListener(_syncTicker);
    _ticker?.cancel();
    _clock.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final s = _svc.state.value;
    final needsTick = widget.now == null && (s.active != null || s.scheduled != null);
    if (needsTick && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
        _clock.value = _now();
        _svc.refresh(now: _clock.value).ignore();
      });
    } else if (!needsTick) {
      _ticker?.cancel();
      _ticker = null;
    }
    _clock.value = _now();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FastingState>(
      valueListenable: _svc.state,
      builder: (context, state, _) => ValueListenableBuilder<DateTime>(
        valueListenable: _clock,
        builder: (context, now, _) {
          final a = state.active;
          return KCard(
            child: AnimatedSwitcher(
              duration: KMotion.of(context, KMotion.standard),
              switchInCurve: KMotion.emphasizedCurve,
              child: a != null
                  ? _Active(key: const ValueKey('active'), status: FastStatus(a, now), onEnd: _end, onEditEnd: _editEnd)
                  : _Idle(
                      key: const ValueKey('idle'),
                      state: state,
                      now: now,
                      onStart: _openStartSheet,
                      onResume: _resume,
                      onCancelSchedule: () => _svc.cancelSchedule(),
                    ),
            ),
          );
        },
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _end() async {
    KHaptics.commit();
    await _svc.stop(now: _now());
  }

  Future<void> _resume() async {
    final ok = await _svc.resumeLast(now: _now());
    if (ok) KHaptics.commit();
  }

  Future<void> _editEnd() async {
    final a = _svc.state.value.active;
    if (a == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(a.plannedEnd),
      helpText: 'Fast ends at',
    );
    if (picked == null || !mounted) return;
    await _svc.setEnd(_nextAt(a.startedAt, picked, a.plannedEnd));
  }

  Future<void> _openStartSheet({bool schedule = false}) async {
    final chosen = await showKSheet<FastPreset>(
      context: context,
      builder: (ctx) => _PresetSheet(schedule: schedule),
    );
    if (chosen == null || !mounted) return;

    DateTime start = _now();
    if (schedule) {
      final date = await showDatePicker(
        context: context,
        initialDate: start.add(const Duration(days: 1)),
        firstDate: start,
        lastDate: start.add(const Duration(days: 60)),
        helpText: 'Fast starts on',
      );
      if (date == null || !mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 5, minute: 30),
        helpText: 'Starts at',
      );
      if (time == null || !mounted) return;
      start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }

    DateTime? end;
    if (chosen.endsAtClock) {
      final def = chosen.plannedEnd(start);
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(def),
        helpText: switch (chosen.kind) {
          FastKind.roza => 'Iftar at',
          FastKind.karvaChauth => 'Moonrise at',
          FastKind.ekadashi => 'Parana next morning at',
          _ => 'Fast ends at',
        },
      );
      if (time == null || !mounted) return;
      end = _nextAt(start, time, def);
    }

    KHaptics.commit();
    if (schedule) {
      await _svc.schedule(chosen.id, start, endAt: end);
    } else {
      await _svc.start(chosen.id, now: start, endAt: end);
    }
  }

  /// [time] on the day of [hint], moved forward a day until it's after [start].
  static DateTime _nextAt(DateTime start, TimeOfDay time, DateTime hint) {
    var d = DateTime(hint.year, hint.month, hint.day, time.hour, time.minute);
    while (!d.isAfter(start)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}

// ── Idle ──────────────────────────────────────────────────────────────────────

class _Idle extends StatelessWidget {
  const _Idle({
    super.key,
    required this.state,
    required this.now,
    required this.onStart,
    required this.onResume,
    required this.onCancelSchedule,
  });

  final FastingState state;
  final DateTime now;
  final Future<void> Function({bool schedule}) onStart;
  final VoidCallback onResume;
  final VoidCallback onCancelSchedule;

  @override
  Widget build(BuildContext context) {
    final last = state.history.isEmpty ? null : state.history.first;
    final endedByMeal = last != null &&
        last.endReason == FastEndReason.meal &&
        last.endedAt != null &&
        now.difference(last.endedAt!).inMinutes < 120;
    final sc = state.scheduled;

    final String line;
    if (endedByMeal) {
      line = 'Your ${last.preset.label} fast ended when you logged a meal at ${_clockText(context, last.endedAt!)}.';
    } else if (last != null && last.endedAt != null && now.difference(last.endedAt!).inHours < 12) {
      line = last.completed
          ? 'Last fast: ${_dur(last.endedAt!.difference(last.startedAt))}. Goal reached.'
          : 'Last fast: ${_dur(last.endedAt!.difference(last.startedAt))}.';
    } else {
      line = '16:8, a vrat or a roza. Logging a meal ends a no-food fast for you.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KIcon(KIcons.timer, size: KIcons.md, color: KColor.textPrimary),
            const SizedBox(width: KSpacing.sm),
            Expanded(child: Text('Fasting', style: KText.h3)),
          ],
        ),
        const SizedBox(height: KSpacing.xs),
        Text(line, style: KText.body.copyWith(color: KColor.textSecondary)),
        if (sc != null) ...[
          const SizedBox(height: KSpacing.sm),
          Text(
            '${sc.preset.label} planned for ${_dayText(sc.startedAt, now)} at ${_clockText(context, sc.startedAt)}.',
            style: KText.bodyMedium,
          ),
        ],
        const SizedBox(height: KSpacing.md),
        KButton(label: 'Start fast', outlined: true, icon: KIcons.timer, onTap: () => onStart()),
        Wrap(
          spacing: KSpacing.md,
          children: [
            if (endedByMeal) KTextAction('Resume fast', onTap: onResume),
            if (sc == null)
              KTextAction('Plan one for later', onTap: () => onStart(schedule: true))
            else
              KTextAction('Cancel plan', onTap: onCancelSchedule),
          ],
        ),
      ],
    );
  }
}

// ── Active ────────────────────────────────────────────────────────────────────

class _Active extends StatelessWidget {
  const _Active({super.key, required this.status, required this.onEnd, required this.onEditEnd});
  final FastStatus status;
  final VoidCallback onEnd;
  final VoidCallback onEditEnd;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final p = s.session.preset;
    final elapsed = s.elapsed;
    final clock = '${elapsed.inHours}:${(elapsed.inMinutes % 60).toString().padLeft(2, '0')}';
    final endText = _clockText(context, s.session.plannedEnd);
    final headline = s.goalReached
        ? 'Goal reached. Break it when you\'re ready.'
        : '${_dur(s.remaining)} to go, ends $endText';
    final rule = p.allowsVratFoods
        ? 'Phalahar allowed. Kyno suggests vrat foods.'
        : 'Logging a meal ends it.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KRing(
              progress: s.progress,
              colors: [KColor.ink],
              size: 92,
              stroke: 8,
              glow: false,
              semanticsLabel: 'Fast progress',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(clock, style: KText.numMedium.copyWith(fontWeight: FontWeight.w700)),
                  Text('elapsed', style: KText.caption.copyWith(fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: KSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p.label} fast', style: KText.h3),
                  const SizedBox(height: KSpacing.xs),
                  Text(headline, style: KText.body.copyWith(color: s.goalReached ? KColor.textPrimary : KColor.textSecondary)),
                  const SizedBox(height: KSpacing.xs),
                  Text(rule, style: KText.caption),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: KSpacing.md),
        Row(
          children: [
            Expanded(child: KButton(label: 'End fast', outlined: true, onTap: onEnd)),
          ],
        ),
        KTextAction('Change end time', icon: KIcons.edit, onTap: onEditEnd),
      ],
    );
  }
}

// ── Preset sheet ──────────────────────────────────────────────────────────────

class _PresetSheet extends StatelessWidget {
  const _PresetSheet({required this.schedule});
  final bool schedule;

  @override
  Widget build(BuildContext context) {
    final ifPresets = fastPresets.where((p) => p.kind == FastKind.intermittent || p.kind == FastKind.sunriseSunset);
    final vrat = fastPresets.where((p) => p.isReligious);
    Widget row(FastPreset p) => KOptionRow(
          icon: p.isReligious ? KIcons.calendar : KIcons.timer,
          title: p.label,
          subtitle: p.subtitle,
          onTap: () => Navigator.of(context).pop(p),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: KSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KSheetHeader(
              schedule ? 'Plan a fast' : 'Start a fast',
              subtitle: schedule ? 'Pick the fast, then the day it starts.' : 'Starts now. You can change the end time.',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KSectionTitle('Intermittent', padding: const EdgeInsets.only(top: KSpacing.lg)),
                  for (final p in ifPresets) ...[row(p), const KHairline()],
                  KSectionTitle('Vrat and roza', padding: const EdgeInsets.only(top: KSpacing.xl)),
                  for (final p in vrat) ...[row(p), const KHairline()],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _dur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h $m min';
}

String _clockText(BuildContext context, DateTime t) =>
    MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(t));

String _dayText(DateTime d, DateTime now) {
  final a = DateTime(d.year, d.month, d.day);
  final b = DateTime(now.year, now.month, now.day);
  final diff = a.difference(b).inDays;
  if (diff == 0) return 'today';
  if (diff == 1) return 'tomorrow';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]}';
}
