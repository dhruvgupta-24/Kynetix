import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_theme.dart';
import '../services/feedback_service.dart';
import '../ui/k_segmented.dart';

// ─── Analytics (curators only) ────────────────────────────────────────────────
// Reads the curator-only analytics_* SQL functions. They check the caller is
// in app_curators and raise otherwise, so this screen shows nothing to anyone
// else even if they reached it.

class _Overview {
  _Overview(Map<String, dynamic> j)
      : total = _int(j['total_users']),
        dau = _int(j['dau']),
        wau = _int(j['wau']),
        mau = _int(j['mau']),
        activeToday = _int(j['active_today']),
        newToday = _int(j['new_today']),
        days = [
          for (final d in (j['series'] as List? ?? const []))
            (
              day: DateTime.tryParse('${(d as Map)['day']}') ?? DateTime(2000),
              fresh: _int(d['new_users']),
              active: _int(d['active_users']),
            ),
        ];
  final int total, dau, wau, mau, activeToday, newToday;
  final List<({DateTime day, int fresh, int active})> days;
}

class _Cohort {
  _Cohort(Map<String, dynamic> j)
      : week = DateTime.tryParse('${j['cohort_week']}') ?? DateTime(2000),
        users = _int(j['users']),
        d1 = _num(j['d1']),
        d7 = _num(j['d7']),
        d30 = _num(j['d30']);
  final DateTime week;
  final int users;
  final double? d1, d7, d30;
}

class _Feature {
  _Feature(Map<String, dynamic> j)
      : name = '${j['name']}',
        events = _int(j['events']),
        users = _int(j['users']);
  final String name;
  final int events, users;
}

class _User {
  _User(Map<String, dynamic> j)
      : id = '${j['user_id']}',
        email = (j['email'] as String?) ?? '',
        name = ((j['name'] as String?) ?? '').trim(),
        signedUp = _time(j['signed_up_at']),
        lastSeen = _time(j['last_seen_at']),
        activeDays = _int(j['active_days']),
        meals = _int(j['meals_logged']),
        workouts = _int(j['workouts_finished']),
        kyno = _int(j['kyno_messages']),
        shares = _int(j['share_exports']),
        widgets = _int(j['widgets_added']),
        version = j['app_version'] as String?;
  final String id, email, name;
  final DateTime? signedUp, lastSeen;
  final int activeDays, meals, workouts, kyno, shares, widgets;
  final String? version;

  String get title => name.isNotEmpty ? name : (email.isNotEmpty ? email : 'No name');
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

String _seen(DateTime? t) => t == null ? 'never' : FeedbackService.relativeTime(t);

String _date(DateTime t) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${months[t.month - 1]}';
}

SupabaseClient get _db => Supabase.instance.client;
const _timeout = Duration(seconds: 20);

enum _Tab { overview, users }

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  _Tab _tab = _Tab.overview;
  int _days = 30;
  _Overview? _overview;
  List<_Cohort>? _cohorts;
  List<_Feature>? _features;
  List<_User>? _users;
  bool _failed = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _db.rpc('analytics_overview', params: {'days': _days}).timeout(_timeout),
        _db.rpc('analytics_retention').timeout(_timeout),
        _db.rpc('analytics_feature_usage', params: {'days': _days}).timeout(_timeout),
        _db.rpc('analytics_user_list', params: {'days': _days}).timeout(_timeout),
      ]);
      if (!mounted) return;
      List<Map<String, dynamic>> rows(Object? r) => [for (final x in (r as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
      setState(() {
        _overview = _Overview(Map<String, dynamic>.from(results[0] as Map));
        _cohorts = rows(results[1]).map(_Cohort.new).toList();
        _features = rows(results[2]).map(_Feature.new).toList();
        _users = rows(results[3]).map(_User.new).toList();
        _failed = false;
      });
    } catch (e) {
      debugPrint('[ANALYTICS_SCREEN] load failed: $e');
      // A failed refresh keeps whatever was already on screen.
      if (mounted) setState(() => _failed = true);
    }
  }

  void _setDays(int d) {
    setState(() => _days = d);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final loaded = _overview != null;
    final pad = EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, KSpacing.xxxl + bottom);

    final Widget body;
    if (!loaded && !_failed) {
      body = const Center(child: KSpinner(size: 22));
    } else if (!loaded) {
      body = RefreshIndicator(
        onRefresh: _load,
        color: KColor.ink,
        backgroundColor: KColor.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(KSpacing.p, 96, KSpacing.p, KSpacing.xxxl),
          children: [
            Text("Couldn't load the numbers.", textAlign: TextAlign.center, style: KText.h3),
            const SizedBox(height: KSpacing.xs),
            Text('Check your connection, then pull to try again.', textAlign: TextAlign.center, style: KText.caption.copyWith(color: KColor.textMuted)),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        color: KColor.ink,
        backgroundColor: KColor.surface,
        child: _tab == _Tab.overview ? _overviewList(pad) : _userList(pad),
      );
    }

    return KPage(
      tone: KTone.neutral,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: KColor.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Analytics', style: KText.h2),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.xs, KSpacing.p, 0),
            child: Row(
              children: [
                Expanded(
                  child: KSegmented<_Tab>(
                    dense: true,
                    segments: [
                      const KSegment(_Tab.overview, 'Overview'),
                      KSegment(_Tab.users, _users == null ? 'Users' : 'Users (${_users!.length})'),
                    ],
                    value: _tab,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                ),
                const SizedBox(width: KSpacing.sm),
                KSegmented<int>(
                  dense: true,
                  segmentWidth: 46,
                  segments: const [KSegment(7, '7d'), KSegment(30, '30d'), KSegment(90, '90d')],
                  value: _days,
                  onChanged: _setDays,
                ),
              ],
            ),
          ),
          if (_failed && loaded)
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.sm, KSpacing.p, 0),
              child: Text("Couldn't refresh. Showing what we had.", style: KText.caption.copyWith(color: KColor.textMuted)),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }

  // ── Overview ───────────────────────────────────────────────────────────────

  Widget _overviewList(EdgeInsets pad) {
    final o = _overview!;
    final cohorts = _cohorts ?? const <_Cohort>[];
    final features = _features ?? const <_Feature>[];
    final top = features.isEmpty ? 1 : features.map((f) => f.events).reduce(math.max);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pad,
      children: [
        Row(
          children: [
            Expanded(child: _Stat(label: 'DAU', value: o.dau)),
            const SizedBox(width: KSpacing.md),
            Expanded(child: _Stat(label: 'WAU', value: o.wau)),
            const SizedBox(width: KSpacing.md),
            Expanded(child: _Stat(label: 'MAU', value: o.mau)),
          ],
        ),
        const SizedBox(height: KSpacing.md),
        Row(
          children: [
            Expanded(child: _Stat(label: 'Users', value: o.total)),
            const SizedBox(width: KSpacing.md),
            Expanded(child: _Stat(label: 'Active today', value: o.activeToday)),
            const SizedBox(width: KSpacing.md),
            Expanded(child: _Stat(label: 'New today', value: o.newToday)),
          ],
        ),
        const _Heading('Active users a day'),
        KCard(child: _Bars(days: o.days, value: (d) => d.active, color: KColor.ink)),
        const _Heading('New users a day'),
        KCard(child: _Bars(days: o.days, value: (d) => d.fresh, color: KColor.ember)),
        const _Heading('Retention by signup week'),
        KCard(
          padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.md, KSpacing.lg, KSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _CohortRow(cells: ['Week', 'Users', 'D1', 'D7', 'D30'], header: true),
              for (final c in cohorts)
                _CohortRow(cells: [_date(c.week), '${c.users}', _pct(c.d1), _pct(c.d7), _pct(c.d30)]),
              if (cohorts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: KSpacing.md),
                  child: Text('No signups in the last 12 weeks.', style: KText.caption.copyWith(color: KColor.textMuted)),
                ),
              const SizedBox(height: KSpacing.sm),
              Text(
                'Share of each week that came back on or after day 1, 7 and 30. Counts start when analytics went live.',
                style: KText.caption.copyWith(fontSize: 11.5, color: KColor.textMuted),
              ),
            ],
          ),
        ),
        _Heading('Feature usage, last $_days days'),
        KCard(
          padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.sm, KSpacing.lg, KSpacing.sm),
          child: features.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: KSpacing.md),
                  child: Text('Nothing tracked yet. Give it a day.', style: KText.caption.copyWith(color: KColor.textMuted)),
                )
              : Column(
                  children: [
                    for (final f in features) _FeatureRow(feature: f, share: f.events / top),
                  ],
                ),
        ),
      ],
    );
  }

  static String _pct(double? v) => v == null ? '-' : '${v.round()}%';

  // ── Users ──────────────────────────────────────────────────────────────────

  Widget _userList(EdgeInsets pad) {
    final q = _query.trim().toLowerCase();
    final users = [
      for (final u in _users ?? const <_User>[])
        if (q.isEmpty || u.email.toLowerCase().contains(q) || u.name.toLowerCase().contains(q)) u,
    ];
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pad,
      itemCount: users.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: KSpacing.md),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: KText.body.copyWith(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search name or email',
                hintStyle: KText.body.copyWith(color: KColor.textMuted),
                prefixIcon: Icon(Icons.search_rounded, color: KColor.textMuted),
                filled: true,
                fillColor: KColor.card,
                contentPadding: const EdgeInsets.symmetric(vertical: KSpacing.md),
                border: OutlineInputBorder(borderRadius: KRadius.md, borderSide: BorderSide(color: KColor.hairline)),
                enabledBorder: OutlineInputBorder(borderRadius: KRadius.md, borderSide: BorderSide(color: KColor.hairline)),
                focusedBorder: OutlineInputBorder(borderRadius: KRadius.md, borderSide: BorderSide(color: KColor.textSecondary)),
              ),
            ),
          );
        }
        final u = users[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: KSpacing.sm),
          child: Pressable(
            onTap: () {
              KHaptics.select();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => _UserScreen(user: u, days: _days)));
            },
            scale: 0.98,
            borderRadius: KRadius.lg,
            semanticLabel: '${u.title}, seen ${_seen(u.lastSeen)}',
            child: KCard(
              padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.md, KSpacing.md, KSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: KText.bodyMedium.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
                        if (u.name.isNotEmpty && u.email.isNotEmpty)
                          Text(u.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: KText.caption.copyWith(fontSize: 12, color: KColor.textMuted)),
                        const SizedBox(height: 4),
                        Text(
                          '${u.activeDays} active ${u.activeDays == 1 ? 'day' : 'days'}  ·  ${u.meals} meals  ·  ${u.workouts} workouts',
                          style: KText.caption.copyWith(fontSize: 12, color: KColor.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: KSpacing.sm),
                  Text(_seen(u.lastSeen), style: KText.caption.copyWith(fontSize: 12, color: KColor.textMuted)),
                  Icon(Icons.chevron_right_rounded, size: 20, color: KColor.textMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── One user ─────────────────────────────────────────────────────────────────

class _UserScreen extends StatefulWidget {
  const _UserScreen({required this.user, required this.days});
  final _User user;
  final int days;

  @override
  State<_UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<_UserScreen> {
  List<Map<String, dynamic>>? _events;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db.rpc('analytics_user_timeline', params: {'uid': widget.user.id, 'max_rows': 200}).timeout(_timeout);
      if (!mounted) return;
      setState(() {
        _events = [for (final x in (r as List)) Map<String, dynamic>.from(x as Map)];
        _failed = false;
      });
    } catch (e) {
      debugPrint('[ANALYTICS_SCREEN] timeline failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final events = _events;
    return KPage(
      tone: KTone.neutral,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: KColor.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(u.title, style: KText.h2, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: KColor.ink,
        backgroundColor: KColor.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, KSpacing.xxxl + bottom),
          children: [
            if (u.email.isNotEmpty) SelectableText(u.email, style: KText.body.copyWith(color: KColor.textSecondary)),
            const SizedBox(height: 2),
            Text(
              [
                if (u.signedUp != null) 'Joined ${_date(u.signedUp!)} ${u.signedUp!.year}',
                'seen ${_seen(u.lastSeen)}',
                ?u.version,
              ].join('  ·  '),
              style: KText.caption.copyWith(color: KColor.textMuted),
            ),
            const SizedBox(height: KSpacing.lg),
            Text('Last ${widget.days} days', style: KText.caption.copyWith(color: KColor.textMuted)),
            const SizedBox(height: KSpacing.sm),
            Row(
              children: [
                Expanded(child: _Stat(label: 'Active days', value: u.activeDays)),
                const SizedBox(width: KSpacing.md),
                Expanded(child: _Stat(label: 'Meals', value: u.meals)),
                const SizedBox(width: KSpacing.md),
                Expanded(child: _Stat(label: 'Workouts', value: u.workouts)),
              ],
            ),
            const SizedBox(height: KSpacing.md),
            Row(
              children: [
                Expanded(child: _Stat(label: 'Kyno', value: u.kyno)),
                const SizedBox(width: KSpacing.md),
                Expanded(child: _Stat(label: 'Shares', value: u.shares)),
                const SizedBox(width: KSpacing.md),
                Expanded(child: _Stat(label: 'Widgets', value: u.widgets)),
              ],
            ),
            const _Heading('Timeline'),
            if (events == null && !_failed)
              const Padding(padding: EdgeInsets.all(KSpacing.xl), child: Center(child: KSpinner(size: 22)))
            else if (events == null)
              Text("Couldn't load the timeline. Pull to try again.", style: KText.caption.copyWith(color: KColor.textMuted))
            else if (events.isEmpty)
              Text('No events yet.', style: KText.caption.copyWith(color: KColor.textMuted))
            else
              KCard(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg, vertical: KSpacing.xs),
                child: Column(
                  children: [
                    for (var i = 0; i < events.length; i++) ...[
                      if (i > 0) const KHairline(),
                      _EventRow(event: events[i]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Pieces ───────────────────────────────────────────────────────────────────

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, top: KSpacing.xl, bottom: KSpacing.sm),
        child: Semantics(
          header: true,
          child: Text(text, style: KText.h3.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => KCard(
        padding: const EdgeInsets.fromLTRB(KSpacing.md, KSpacing.md, KSpacing.sm, KSpacing.md),
        borderRadius: KRadius.md,
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, maxLines: 1, style: KText.caption.copyWith(fontSize: 12, color: KColor.textMuted)),
              const SizedBox(height: 6),
              Text(thousands(value), style: KText.numMedium.copyWith(fontSize: 22)),
            ],
          ),
        ),
      );
}

/// One bar a day, scaled to the busiest day, with the peak and the date
/// range underneath. Plain rectangles: no gradients, no glow.
class _Bars extends StatelessWidget {
  const _Bars({required this.days, required this.value, required this.color});
  final List<({DateTime day, int fresh, int active})> days;
  final int Function(({DateTime day, int fresh, int active})) value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox(height: 40);
    final values = days.map(value).toList();
    final peak = values.reduce(math.max);
    final total = values.fold<int>(0, (s, v) => s + v);
    final muted = KText.caption.copyWith(fontSize: 11.5, color: KColor.textMuted);
    return Semantics(
      label: '$total in total, peak $peak a day',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(thousands(total), style: KText.numMedium.copyWith(fontSize: 20)),
              const SizedBox(width: KSpacing.sm),
              Text('total', style: muted),
              const Spacer(),
              Text('peak $peak', style: muted),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          SizedBox(
            height: 88,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final v in values)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: values.length > 45 ? 0.5 : 1.5),
                      child: Container(
                        height: peak == 0 ? 2 : math.max(2, 88 * v / peak),
                        decoration: BoxDecoration(
                          color: v == 0 ? KColor.track : color,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: KSpacing.xs),
          Row(
            children: [
              Text(_date(days.first.day), style: muted),
              const Spacer(),
              Text(_date(days.last.day), style: muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _CohortRow extends StatelessWidget {
  const _CohortRow({required this.cells, this.header = false});
  final List<String> cells;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final style = header
        ? KText.caption.copyWith(fontSize: 12, color: KColor.textMuted, fontWeight: FontWeight.w600)
        : KText.body.copyWith(fontSize: 14, fontFeatures: const [FontFeature.tabularFigures()]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(cells[0], style: style)),
          for (final c in cells.skip(1)) Expanded(flex: 2, child: Text(c, textAlign: TextAlign.end, style: style)),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature, required this.share});
  final _Feature feature;
  final double share;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: KSpacing.sm),
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(feature.name.replaceAll('_', ' '), style: KText.bodyMedium.copyWith(fontSize: 14))),
                  Text(
                    '${thousands(feature.events)}  ·  ${feature.users} ${feature.users == 1 ? 'user' : 'users'}',
                    style: KText.caption.copyWith(fontSize: 12, color: KColor.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              KBar(progress: share, colors: [KColor.ember], height: 4),
            ],
          ),
        ),
      );
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final t = _time(event['created_at']);
    final props = event['props'] is Map ? (event['props'] as Map) : const {};
    final detail = [for (final e in props.entries) '${e.key} ${e.value}'].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${event['name']}'.replaceAll('_', ' '), style: KText.bodyMedium.copyWith(fontSize: 14)),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(detail, style: KText.caption.copyWith(fontSize: 12, color: KColor.textMuted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: KSpacing.sm),
          Text(_seen(t), style: KText.caption.copyWith(fontSize: 12, color: KColor.textMuted)),
        ],
      ),
    );
  }
}
