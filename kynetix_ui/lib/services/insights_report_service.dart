import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/day_log.dart';
import '../models/insights_models.dart';
import '../models/user_profile.dart';
import 'profile_service.dart';
import 'chatgpt_link_service.dart';
import 'insights_engine.dart';
import 'user_session_coordinator.dart';
import 'cloud_sync_service.dart';
import '../services/persistence_service.dart';
import 'workout_service.dart';
import 'nutrition_target_engine.dart';
import 'nutrition_hydration_guard.dart';
import 'ai_router_error.dart';
import 'internal/net_timeouts.dart';

// Logging in this file is debug-only: release builds skip the console I/O.
void _debugLog(String? message, {int? wrapWidth}) {
  if (kDebugMode) debugPrint(message, wrapWidth: wrapWidth);
}

// ─── InsightsReportService ───────────────────────────────────────────────────
class InsightsReportService extends ChangeNotifier {
  static final InsightsReportService instance = InsightsReportService._();
  InsightsReportService._();

  static const _kWeekly        = 'insights_weekly_v1';
  static const _kMonthly       = 'insights_monthly_v1';
  static const _kYearly        = 'insights_yearly_v1';
  static const _kPersonalBests = 'insights_personal_bests_v1';
  static const _kAchievements  = 'insights_achievements_v1';
  static const _kAiSummaries   = 'insights_ai_summaries_v1';
  static const _kLastComputed  = 'insights_last_computed_v1';

  static const _maxWeekly  = 52;
  static const _maxMonthly = 24;
  static const _maxYearly  = 5;

  String? _currentUserId;
  String _scopedKey(String base) => _currentUserId != null ? '${base}_$_currentUserId' : base;

  /// This account's own value; the old device-wide key is only ever read by
  /// the account that owns the device's legacy data (never by a new account,
  /// which would otherwise see someone else's weekly totals).
  String? _readKey(SharedPreferences prefs, String base) {
    final own = prefs.getString(_scopedKey(base));
    if (own != null || _currentUserId == null) return own ?? prefs.getString(base);
    return UserSessionCoordinator.legacyOwner(prefs) == _currentUserId
        ? prefs.getString(base)
        : null;
  }

  Map<String, WeeklyReport>    _weekly       = {};
  Map<String, MonthlyReport>   _monthly      = {};
  Map<String, YearlyReport>    _yearly       = {};
  PersonalBests?               _personalBests;
  List<Achievement>            _achievements = [];
  Map<String, InsightsSummary> _aiSummaries  = {};
  DateTime?                    _lastComputed;

  // Dates whose targeted recompute was requested by a save but not run yet,
  // keyed by their (week, month, year) bucket — dates in the same bucket
  // produce identical results, so one recompute per bucket is enough.
  final Map<String, DateTime> _pendingRecompute = {};
  UserProfile? _pendingRecomputeProfile;

  /// Load for specific authenticated user
  Future<void> initForUser(String userId, {SharedPreferences? prefsOverride}) async {
    _currentUserId = userId;
    clearMemory();
    await init(prefsOverride: prefsOverride);
  }

  /// Flush in-memory state without deleting persisted disk stores
  void clearMemory() {
    cancelPendingRecompute();
    _weekly.clear();
    _monthly.clear();
    _yearly.clear();
    _personalBests = null;
    _achievements.clear();
    _aiSummaries.clear();
    _lastComputed = null;
    notifyListeners();
  }

  // ── Init (called in PersistenceService.load()) ─────────────────────────────
  Future<void> init({SharedPreferences? prefsOverride}) async {
    try {
      final prefs = prefsOverride ?? await SharedPreferences.getInstance();

      final weeklyRaw = _readKey(prefs, _kWeekly);
      if (weeklyRaw != null) {
        try {
          final map = jsonDecode(weeklyRaw) as Map<String, dynamic>;
          _weekly = {};
          map.forEach((k, v) {
            try {
              final report = WeeklyReport.fromJson(v as Map<String, dynamic>);
              if (report.schemaVersion == kInsightsSchemaVersion) {
                _weekly[k] = report;
              }
            } catch (inner) {
              _debugLog('[InsightsReportService] Error parsing weekly report $k: $inner');
            }
          });
        } catch (outer) {
          _debugLog('[InsightsReportService] Error decoding weekly cache: $outer');
        }
      }

      final monthlyRaw = _readKey(prefs, _kMonthly);
      if (monthlyRaw != null) {
        try {
          final map = jsonDecode(monthlyRaw) as Map<String, dynamic>;
          _monthly = {};
          map.forEach((k, v) {
            try {
              final report = MonthlyReport.fromJson(v as Map<String, dynamic>);
              if (report.schemaVersion == kInsightsSchemaVersion) {
                _monthly[k] = report;
              }
            } catch (inner) {
              _debugLog('[InsightsReportService] Error parsing monthly report $k: $inner');
            }
          });
        } catch (outer) {
          _debugLog('[InsightsReportService] Error decoding monthly cache: $outer');
        }
      }

      final yearlyRaw = _readKey(prefs, _kYearly);
      if (yearlyRaw != null) {
        try {
          final map = jsonDecode(yearlyRaw) as Map<String, dynamic>;
          _yearly = {};
          map.forEach((k, v) {
            try {
              final report = YearlyReport.fromJson(v as Map<String, dynamic>);
              if (report.schemaVersion == kInsightsSchemaVersion) {
                _yearly[k] = report;
              }
            } catch (inner) {
              _debugLog('[InsightsReportService] Error parsing yearly report $k: $inner');
            }
          });
        } catch (outer) {
          _debugLog('[InsightsReportService] Error decoding yearly cache: $outer');
        }
      }

      final pbRaw = _readKey(prefs, _kPersonalBests);
      if (pbRaw != null) {
        try {
          final pb = PersonalBests.fromJson(jsonDecode(pbRaw) as Map<String, dynamic>);
          if (pb.schemaVersion == kInsightsSchemaVersion) {
            _personalBests = pb;
          }
        } catch (e) {
          _debugLog('[InsightsReportService] Error parsing personal bests cache: $e');
        }
      }

      final achievementsRaw = _readKey(prefs, _kAchievements);
      if (achievementsRaw != null) {
        try {
          final list = jsonDecode(achievementsRaw) as List<dynamic>;
          _achievements = list
              .map((item) => Achievement.fromJson(item as Map<String, dynamic>))
              .toList();
        } catch (e) {
          _debugLog('[InsightsReportService] Error parsing achievements cache: $e');
        }
      }

      final aiRaw = _readKey(prefs, _kAiSummaries);
      if (aiRaw != null) {
        try {
          final map = jsonDecode(aiRaw) as Map<String, dynamic>;
          _aiSummaries = map.map((k, v) => MapEntry(k, InsightsSummary.fromJson(v as Map<String, dynamic>)));
        } catch (e) {
          _debugLog('[InsightsReportService] Error parsing AI summaries cache: $e');
        }
      }

      final lastComputedRaw = _readKey(prefs, _kLastComputed);
      if (lastComputedRaw != null) {
        _lastComputed = DateTime.tryParse(lastComputedRaw);
      }
    } catch (e) {
      _debugLog('[InsightsReportService] Error loading cached insights: $e');
    }
  }

  // ── Compute triggers ───────────────────────────────────────────────────────
  Future<void> maybeRecompute(UserProfile profile) async {
    if (!NutritionHydrationGuard.instance.isReadyForCurrentUser) {
      _debugLog('[InsightsReportService] Hydration guard is not ready. Skipping maybeRecompute.');
      return;
    }
    // Apply any queued targeted recompute first so the freshness check below
    // sees the same _lastComputed it would have without deferral.
    await flushPendingRecompute();
    final now = DateTime.now();
    final workoutsChanged = WorkoutService.instance.lastWorkoutsChangedAt;
    final logsChanged = PersistenceService.lastLogsChangedAt;

    _debugLog('[InsightsReportService] maybeRecompute check:');
    _debugLog('  - now: $now');
    _debugLog('  - _lastComputed: $_lastComputed');
    _debugLog('  - workoutsChanged: $workoutsChanged');
    _debugLog('  - logsChanged: $logsChanged');
    _debugLog('  - workoutHydrationCompletedAt: ${WorkoutService.lastWorkoutsHydratedAt}');
    _debugLog('  - dayLogHydrationCompletedAt: ${PersistenceService.lastDayLogsHydratedAt}');
    _debugLog('  - historicalRepairCompletedAt: ${PersistenceService.lastHistoricalRepairCompletedAt}');

    if (_lastComputed == null ||
        _lastComputed!.isBefore(workoutsChanged) ||
        _lastComputed!.isBefore(logsChanged) ||
        now.difference(_lastComputed!).inMinutes > 60) {
      _debugLog('[InsightsReportService] Condition met. Starting recomputation...');
      await _recompute(profile);
    } else {
      _debugLog('[InsightsReportService] Cache is up-to-date. Skipping recomputation.');
    }
  }

  // User-triggered (pull-to-refresh): always recomputes
  Future<void> forceRecompute(UserProfile profile) async {
    await _recompute(profile);
  }

  // ── Pure getters — ZERO computation, ZERO async ───────────────────────────
  WeeklyReport?           latestWeekly()         => weeklyFor(_currentWeekKey());
  MonthlyReport?          latestMonthly()        => monthlyFor(_currentMonthKey());
  YearlyReport?           latestYearly()         => yearlyFor(_currentYearKey());
  WeeklyReport? weeklyFor(String key) {
    _flushPendingForRead();
    if (!_weekly.containsKey(key)) {
      final profile = ProfileService.instance.currentUserProfile;
      if (profile != null) {
        try {
          final report = InsightsEngine.computeWeek(
            weekKey: key,
            profile: profile,
            logs: dayLogStore,
            sessions: WorkoutService.instance.sessions,
            priorWeek: null,
          );
          if (report != null) {
            _weekly[key] = report;
            _save().ignore();
          }
        } catch (e) {
          _debugLog('[InsightsReportService] On-demand compute for week $key failed: $e');
        }
      }
    }
    return _weekly[key];
  }

  MonthlyReport? monthlyFor(String key) {
    _flushPendingForRead();
    if (!_monthly.containsKey(key)) {
      final profile = ProfileService.instance.currentUserProfile;
      if (profile != null) {
        try {
          final report = InsightsEngine.computeMonth(
            monthKey: key,
            profile: profile,
            logs: dayLogStore,
            sessions: WorkoutService.instance.sessions,
            priorMonth: null,
          );
          if (report != null) {
            _monthly[key] = report;
            _save().ignore();
          }
        } catch (e) {
          _debugLog('[InsightsReportService] On-demand compute for month $key failed: $e');
        }
      }
    }
    return _monthly[key];
  }

  YearlyReport? yearlyFor(String key) {
    _flushPendingForRead();
    if (!_yearly.containsKey(key)) {
      final profile = ProfileService.instance.currentUserProfile;
      if (profile != null) {
        try {
          final report = InsightsEngine.computeYear(
            yearKey: key,
            profile: profile,
            logs: dayLogStore,
            monthlyCache: _monthly,
          );
          if (report != null) {
            _yearly[key] = report;
            _save().ignore();
          }
        } catch (e) {
          _debugLog('[InsightsReportService] On-demand compute for year $key failed: $e');
        }
      }
    }
    return _yearly[key];
  }
  PersonalBests?          get personalBests      { _flushPendingForRead(); return _personalBests; }
  List<Achievement>       get achievements       { _flushPendingForRead(); return List.unmodifiable(_achievements); }
  int                     get newAchievementCount { _flushPendingForRead(); return _achievements.where((a) => a.isNew).length; }
  InsightsSummary?        aiSummaryFor(String k) => _aiSummaries[k];
  DateTime?               get lastComputed       { _flushPendingForRead(); return _lastComputed; }

  // AchievementProgress is computed on call — NOT cached, NOT in build()
  List<AchievementProgress> get progress {
    _flushPendingForRead();
    return InsightsEngine.computeProgress(_achievements, dayLogStore, ProfileService.instance.currentUserProfile ?? const UserProfile(name: '', age: 0, gender: '', height: 0, weight: 0, workoutDaysMin: 0, workoutDaysMax: 0, goal: ''), WorkoutService.instance.sessions);
  }

  Map<String, WeeklyReport> get weeklyCache { _flushPendingForRead(); return Map.unmodifiable(_weekly); }
  Map<String, MonthlyReport> get monthlyCache { _flushPendingForRead(); return Map.unmodifiable(_monthly); }
  Map<String, YearlyReport> get yearlyCache { _flushPendingForRead(); return Map.unmodifiable(_yearly); }

  // ── Write ──────────────────────────────────────────────────────────────────
  Future<void> markAchievementsViewed() async {
    bool changed = false;
    for (int i = 0; i < _achievements.length; i++) {
      if (_achievements[i].isNew) {
        _achievements[i] = _achievements[i].copyWith(isNew: false);
        changed = true;
      }
    }
    if (changed) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_scopedKey(_kAchievements), jsonEncode(_achievements.map((a) => a.toJson()).toList()));
      notifyListeners();
    }
  }

  /// [stillCurrent] (cloud hydration) must hold at the merge and again before
  /// the write; otherwise the session ended and the rows are dropped.
  Future<void> mergeAchievementsFromCloud(
    List<Achievement> cloud, {
    bool Function()? stillCurrent,
  }) async {
    if (stillCurrent != null && !stillCurrent()) return;
    final localMap = {for (final a in _achievements) a.id: a};
    bool changed = false;
    for (final ca in cloud) {
      if (!localMap.containsKey(ca.id)) {
        // cloud restored is never new
        final completeObj = AchievementRegistry.fromId(ca.id, earnedAt: ca.earnedAt, isNew: false);
        if (completeObj != null) {
          _achievements.add(completeObj);
          changed = true;
        }
      }
    }
    if (changed) {
      // Sort chronologically (oldest first, to preserve presentation order if needed)
      _achievements.sort((a, b) => a.earnedAt.compareTo(b.earnedAt));
      final prefs = await SharedPreferences.getInstance();
      if (stillCurrent != null && !stillCurrent()) return;
      await prefs.setString(_scopedKey(_kAchievements), jsonEncode(_achievements.map((a) => a.toJson()).toList()));
      notifyListeners();
    }
  }

  Future<void> reset() async {
    cancelPendingRecompute();
    _weekly.clear();
    _monthly.clear();
    _yearly.clear();
    _personalBests = null;
    _achievements.clear();
    _aiSummaries.clear();
    _lastComputed = null;

    final prefs = await SharedPreferences.getInstance();
    for (final k in const [_kWeekly, _kMonthly, _kYearly, _kPersonalBests,
        _kAchievements, _kAiSummaries, _kLastComputed]) {
      await prefs.remove(k);
      if (_currentUserId != null) await prefs.remove(_scopedKey(k));
    }

    notifyListeners();
  }

  Future<void> _recompute(UserProfile profile) async {
    final startTime = DateTime.now();
    _debugLog('[InsightsReportService] _recompute started at: $startTime');

    // Run historical repair migration for DayLogs with null gymDay on training days
    await PersistenceService.runHistoricalRepairMigration();

    final weekKeys = <String>{};
    final monthKeys = <String>{};
    final yearKeys = <String>{};

    for (final dateStr in dayLogStore.keys) {
      final log = dayLogStore[dateStr]!;
      if (log.isEmpty) continue;
      final date = DateTime.tryParse(dateStr);
      if (date != null) {
        weekKeys.add(InsightsEngine.weekKeyOf(date));
        monthKeys.add(InsightsEngine.monthKeyOf(date));
        yearKeys.add(date.year.toString());
      }
    }

    // Include current week/month/year to ensure they are evaluated if they have data
    final now = DateTime.now();
    weekKeys.add(InsightsEngine.weekKeyOf(now));
    monthKeys.add(InsightsEngine.monthKeyOf(now));
    yearKeys.add(now.year.toString());

    final sortedWeeks = weekKeys.toList()..sort();
    final sortedMonths = monthKeys.toList()..sort();
    final sortedYears = yearKeys.toList()..sort();

    final sessions = WorkoutService.instance.sessions;

    // 1. Weekly reports
    final newWeekly = <String, WeeklyReport>{};
    WeeklyReport? priorWeek;
    for (final wKey in sortedWeeks) {
      final report = InsightsEngine.computeWeek(
        weekKey: wKey,
        profile: profile,
        logs: dayLogStore,
        sessions: sessions,
        priorWeek: priorWeek,
      );
      if (report != null) {
        newWeekly[wKey] = report;
        priorWeek = report;
      }
    }
    _weekly = newWeekly;

    // 2. Monthly reports
    final newMonthly = <String, MonthlyReport>{};
    MonthlyReport? priorMonth;
    for (final mKey in sortedMonths) {
      final report = InsightsEngine.computeMonth(
        monthKey: mKey,
        profile: profile,
        logs: dayLogStore,
        sessions: sessions,
        priorMonth: priorMonth,
      );
      if (report != null) {
        newMonthly[mKey] = report;
        priorMonth = report;
      }
    }
    _monthly = newMonthly;

    // 3. Yearly reports
    final newYearly = <String, YearlyReport>{};
    for (final yKey in sortedYears) {
      final report = InsightsEngine.computeYear(
        yearKey: yKey,
        profile: profile,
        logs: dayLogStore,
        monthlyCache: _monthly,
      );
      if (report != null) {
        newYearly[yKey] = report;
      }
    }
    _yearly = newYearly;

    // 4. Personal Bests
    _personalBests = InsightsEngine.computePersonalBests(
      profile: profile,
      logs: dayLogStore,
      weeklyCache: _weekly,
      monthlyCache: _monthly,
    );

    // 5. Achievements
    _achievements = InsightsEngine.evaluateAchievements(
      logs: dayLogStore,
      profile: profile,
      sessions: sessions,
      existingAchievements: _achievements,
      weeklyReports: _weekly.values.toList()..sort((a, b) => a.weekKey.compareTo(b.weekKey)),
      monthlyReports: _monthly.values.toList()..sort((a, b) => a.monthKey.compareTo(b.monthKey)),
      currentPBs: _personalBests,
    );

    _lastComputed = DateTime.now();
    final endTime = DateTime.now();
    _debugLog('[InsightsReportService] _recompute ended at: $endTime. Duration: ${endTime.difference(startTime).inMilliseconds}ms');

    await _save();
    notifyListeners();

    // Trigger AI summary generation if connected and latest weekly report exists
    final latestW = latestWeekly();
    if (latestW != null) {
      _generateAiSummaryIfNeeded(latestW, profile).ignore();
    }
  }

  Future<void> _save() async {
    _pruneWeekly();
    _pruneMonthly();
    _pruneYearly();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey(_kWeekly), jsonEncode(_weekly.map((k, v) => MapEntry(k, v.toJson()))));
    await prefs.setString(_scopedKey(_kMonthly), jsonEncode(_monthly.map((k, v) => MapEntry(k, v.toJson()))));
    await prefs.setString(_scopedKey(_kYearly), jsonEncode(_yearly.map((k, v) => MapEntry(k, v.toJson()))));
    if (_personalBests != null) {
      await prefs.setString(_scopedKey(_kPersonalBests), jsonEncode(_personalBests!.toJson()));
    }
    await prefs.setString(_scopedKey(_kAchievements), jsonEncode(_achievements.map((a) => a.toJson()).toList()));
    await prefs.setString(_scopedKey(_kAiSummaries), jsonEncode(_aiSummaries.map((k, v) => MapEntry(k, v.toJson()))));
    if (_lastComputed != null) {
      await prefs.setString(_scopedKey(_kLastComputed), _lastComputed!.toIso8601String());
    } else {
      await prefs.remove(_scopedKey(_kLastComputed));
    }

    // Fire-and-forget cloud sync
    CloudSyncService.instance.syncInsightsCacheBackground().ignore();
    CloudSyncService.instance.syncAchievementsBackground().ignore();
  }

  void _pruneWeekly() {
    if (_weekly.length <= _maxWeekly) return;
    final sorted = _weekly.keys.toList()..sort();
    for (final key in sorted.take(_weekly.length - _maxWeekly)) {
      _weekly.remove(key);
      _aiSummaries.remove(key);
    }
  }

  void _pruneMonthly() {
    if (_monthly.length <= _maxMonthly) return;
    final sorted = _monthly.keys.toList()..sort();
    for (final key in sorted.take(_monthly.length - _maxMonthly)) {
      _monthly.remove(key);
    }
  }

  void _pruneYearly() {
    if (_yearly.length <= _maxYearly) return;
    final sorted = _yearly.keys.toList()..sort();
    for (final key in sorted.take(_yearly.length - _maxYearly)) {
      _yearly.remove(key);
    }
  }

  // ── AI narrative (weekly only, V1) ─────────────────────────────────────────
  /// Last weekly-summary AI failure (rate limit, too long, generic), or null
  /// after a success. Exposed for the Insights UI; never holds raw bodies.
  final ValueNotifier<AiRouterException?> lastAiSummaryError =
      ValueNotifier<AiRouterException?>(null);

  /// ai-chat-router body for the weekly summary. The server owns the system
  /// prompt for purpose 'weekly_summary'; only the user message is sent.
  @visibleForTesting
  static Map<String, dynamic> weeklySummaryRequestBody(String userPrompt) => {
        'purpose': 'weekly_summary',
        'messages': [
          {'role': 'user', 'content': userPrompt},
        ],
      };

  Future<void> _generateAiSummaryIfNeeded(WeeklyReport report, UserProfile profile) async {
    final existing = _aiSummaries[report.weekKey];
    if (existing != null && !existing.isStale) return;

    try {
      final status = await ChatGptLinkService.getStatus();
      if (!status.isConnected) return;

      // The system prompt is server-owned (purpose 'weekly_summary').
      final protein = _weekProteinStats(report, profile);
      final userPrompt = 'Weekly Report Data:\n'
          '- Week: ${report.weekKey}\n'
          '- Consistency Score: ${report.consistencyScore.score}/100\n'
          '- Logged Days: ${report.loggedDaysCount}/7\n'
          '- Gym Days: ${report.gymDaysCount}\n'
          '- Avg Calories: ${report.avgCalories.round()} kcal\n'
          '- Avg Protein: ${report.avgProtein.round()}g\n'
          '${protein != null ? '- Protein target: ${protein.target}g\n' : ''}'
          '${protein != null ? '- Days protein target hit: ${protein.hitDays}/7\n' : ''}'
          '${report.deltaVsPrior != null ? '- Score change vs last week: ${report.deltaVsPrior!.consistencyScoreDelta ?? 0} pts' : ''}\n'
          '${report.topImprovement != null ? '- Top improvement: ${report.topImprovement!.label}' : ''}\n'
          'User Name: ${profile.name}';

      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;

      final FunctionResponse res;
      try {
        res = await Supabase.instance.client.functions.invoke(
          'ai-chat-router',
          body: weeklySummaryRequestBody(userPrompt),
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ).within(NetTimeouts.ai, 'weekly summary');
      } on FunctionException catch (e) {
        // Rate limit / too long: keep the calm, typed error for the UI and
        // retry on a later recompute. Never surface the raw body.
        lastAiSummaryError.value = AiRouterException.from(e);
        _debugLog('[InsightsReportService] AI summary skipped: ${lastAiSummaryError.value}');
        return;
      }

      final data = res.data is Map ? (res.data as Map).cast<String, dynamic>() : null;
      if (data == null || data['success'] != true) {
        lastAiSummaryError.value = AiRouterException.fromResponse(res.status, data);
        return;
      }
      lastAiSummaryError.value = null;
      {
        final narrative = data['response'] as String? ?? '';
        if (narrative.isNotEmpty) {
          _aiSummaries[report.weekKey] = InsightsSummary(
            weekKey: report.weekKey,
            narrative: narrative.trim(),
            generatedAt: DateTime.now(),
            isStale: false,
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_scopedKey(_kAiSummaries), jsonEncode(_aiSummaries.map((k, v) => MapEntry(k, v.toJson()))));
          notifyListeners();
        }
      }
    } catch (e) {
      _debugLog('[InsightsReportService] AI Summary generation error: $e');
    }
  }

  Future<void> recomputeForDate(DateTime date, UserProfile profile) async {
    final wKey = _recomputeForDateCore(date, profile);
    await _save();
    notifyListeners();

    // Trigger AI summary generation if connected and latest weekly report exists
    final latestW = latestWeekly();
    if (latestW != null && latestW.weekKey == wKey) {
      _generateAiSummaryIfNeeded(latestW, profile).ignore();
    }
  }

  /// Synchronous part of [recomputeForDate]; returns the affected week key.
  String _recomputeForDateCore(DateTime date, UserProfile profile) {
    final wKey = InsightsEngine.weekKeyOf(date);
    final mKey = InsightsEngine.monthKeyOf(date);
    final yKey = date.year.toString();

    final sessions = WorkoutService.instance.sessions;

    // 1. Recompute affected week report
    final weekKeys = _weekly.keys.toSet()..add(wKey);
    final sortedWeeks = weekKeys.toList()..sort();
    final idx = sortedWeeks.indexOf(wKey);
    WeeklyReport? priorWeek;
    if (idx > 0) {
      priorWeek = _weekly[sortedWeeks[idx - 1]];
    }
    final newWeekReport = InsightsEngine.computeWeek(
      weekKey: wKey,
      profile: profile,
      logs: dayLogStore,
      sessions: sessions,
      priorWeek: priorWeek,
    );
    if (newWeekReport != null) {
      _weekly[wKey] = newWeekReport;
    } else {
      _weekly.remove(wKey);
    }

    // 2. Recompute affected month report
    final monthKeys = _monthly.keys.toSet()..add(mKey);
    final sortedMonths = monthKeys.toList()..sort();
    final mIdx = sortedMonths.indexOf(mKey);
    MonthlyReport? priorMonth;
    if (mIdx > 0) {
      priorMonth = _monthly[sortedMonths[mIdx - 1]];
    }
    final newMonthReport = InsightsEngine.computeMonth(
      monthKey: mKey,
      profile: profile,
      logs: dayLogStore,
      sessions: sessions,
      priorMonth: priorMonth,
    );
    if (newMonthReport != null) {
      _monthly[mKey] = newMonthReport;
    } else {
      _monthly.remove(mKey);
    }

    // 3. Recompute affected year report
    final newYearReport = InsightsEngine.computeYear(
      yearKey: yKey,
      profile: profile,
      logs: dayLogStore,
      monthlyCache: _monthly,
    );
    if (newYearReport != null) {
      _yearly[yKey] = newYearReport;
    } else {
      _yearly.remove(yKey);
    }

    // 4. Personal Bests
    _personalBests = InsightsEngine.computePersonalBests(
      profile: profile,
      logs: dayLogStore,
      weeklyCache: _weekly,
      monthlyCache: _monthly,
    );

    // 5. Achievements
    _achievements = InsightsEngine.evaluateAchievements(
      logs: dayLogStore,
      profile: profile,
      sessions: sessions,
      existingAchievements: _achievements,
      weeklyReports: _weekly.values.toList()..sort((a, b) => a.weekKey.compareTo(b.weekKey)),
      monthlyReports: _monthly.values.toList()..sort((a, b) => a.monthKey.compareTo(b.monthKey)),
      currentPBs: _personalBests,
    );

    _lastComputed = DateTime.now();
    return wKey;
  }

  // ── Deferred targeted recompute ────────────────────────────────────────────
  //
  // Saves queue the affected date instead of recomputing on the interaction
  // frame. The queue is applied (same computation as recomputeForDate) when:
  //   • PersistenceService runs its debounced post-save effects,
  //   • any cached report / achievement getter is read (so readers never see
  //     stale data), or
  //   • maybeRecompute / app pause flushes it.

  bool get hasPendingRecompute => _pendingRecompute.isNotEmpty;

  void queueRecomputeForDate(DateTime date, UserProfile profile) {
    final bucket = '${InsightsEngine.weekKeyOf(date)}|'
        '${InsightsEngine.monthKeyOf(date)}|${date.year}';
    _pendingRecompute.putIfAbsent(bucket, () => date);
    _pendingRecomputeProfile = profile;
  }

  void cancelPendingRecompute() {
    _pendingRecompute.clear();
    _pendingRecomputeProfile = null;
  }

  /// Applies queued recomputes synchronously. Returns the affected week keys.
  Set<String> _applyPendingRecomputes() {
    final profile = _pendingRecomputeProfile;
    if (_pendingRecompute.isEmpty || profile == null) {
      cancelPendingRecompute();
      return const {};
    }
    final dates = _pendingRecompute.values.toList();
    cancelPendingRecompute();
    final weeks = <String>{};
    for (final d in dates) {
      weeks.add(_recomputeForDateCore(d, profile));
    }
    _lastAppliedProfile = profile;
    return weeks;
  }

  UserProfile? _lastAppliedProfile;

  void _afterAppliedRecompute(Set<String> weeks) {
    final profile = _lastAppliedProfile;
    final latestW = latestWeekly();
    if (profile != null && latestW != null && weeks.contains(latestW.weekKey)) {
      _generateAiSummaryIfNeeded(latestW, profile).ignore();
    }
  }

  /// Runs queued recomputes now, persists and notifies (like recomputeForDate).
  Future<void> flushPendingRecompute() async {
    if (_pendingRecompute.isEmpty) return;
    final weeks = _applyPendingRecomputes();
    if (weeks.isEmpty) return;
    await _save();
    notifyListeners();
    _afterAppliedRecompute(weeks);
  }

  /// Read-path flush: getters must return fresh data, but may run during a
  /// build, so listeners are notified in a microtask instead of synchronously.
  void _flushPendingForRead() {
    if (_pendingRecompute.isEmpty) return;
    final weeks = _applyPendingRecomputes();
    if (weeks.isEmpty) return;
    _save().ignore();
    scheduleMicrotask(() {
      notifyListeners();
      _afterAppliedRecompute(weeks);
    });
  }

  /// [stillCurrent] (cloud hydration) must hold when the merge starts;
  /// otherwise the session ended and the cache is dropped.
  Future<void> mergeCacheFromCloud(
    Map<String, dynamic> cache, {
    bool Function()? stillCurrent,
  }) async {
    if (stillCurrent != null && !stillCurrent()) return;
    try {
      final weeklyJson = cache['weekly_json'] as Map?;
      final monthlyJson = cache['monthly_json'] as Map?;
      final yearlyJson = cache['yearly_json'] as Map?;
      final pbJson = cache['personal_bests_json'] as Map?;

      if (weeklyJson != null) {
        _weekly = weeklyJson.map((k, v) => MapEntry(k as String, WeeklyReport.fromJson(Map<String, dynamic>.from(v as Map))));
      }
      if (monthlyJson != null) {
        _monthly = monthlyJson.map((k, v) => MapEntry(k as String, MonthlyReport.fromJson(Map<String, dynamic>.from(v as Map))));
      }
      if (yearlyJson != null) {
        _yearly = yearlyJson.map((k, v) => MapEntry(k as String, YearlyReport.fromJson(Map<String, dynamic>.from(v as Map))));
      }
      if (pbJson != null) {
        _personalBests = PersonalBests.fromJson(Map<String, dynamic>.from(pbJson));
      }
      // Force a local recompute after merging to ensure data consistency with hydrated logs/workouts.
      _lastComputed = null;
      await _save();
      notifyListeners();
    } catch (e) {
      _debugLog('[InsightsReportService] Error merging cache from cloud: $e');
    }
  }

  String _currentWeekKey() => InsightsEngine.weekKeyOf(DateTime.now());
  String _currentMonthKey() => InsightsEngine.monthKeyOf(DateTime.now());
  String _currentYearKey() => DateTime.now().year.toString();

  // ─── Nutrition Adherence Streaks ───────────────────────────────────────────

  int getLoggingStreak() {
    int streak = 0;
    final now = DateTime.now();

    // Check today
    final todayKey = dateKey(now);
    final todayLog = dayLogStore[todayKey];
    final todayLogged = todayLog != null && !todayLog.isEmpty;

    DateTime startCountingFrom;
    if (todayLogged) {
      streak = 1;
      startCountingFrom = now.subtract(const Duration(days: 1));
    } else {
      // If today is not logged, check yesterday.
      final yesterdayDate = now.subtract(const Duration(days: 1));
      final yesterdayKey = dateKey(yesterdayDate);
      final yesterdayLog = dayLogStore[yesterdayKey];
      final yesterdayLogged = yesterdayLog != null && !yesterdayLog.isEmpty;
      if (yesterdayLogged) {
        streak = 1;
        startCountingFrom = yesterdayDate.subtract(const Duration(days: 1));
      } else {
        return 0; // No active streak
      }
    }

    while (true) {
      final key = dateKey(startCountingFrom);
      final log = dayLogStore[key];
      if (log != null && !log.isEmpty) {
        streak++;
        startCountingFrom = startCountingFrom.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  /// Protein target (average over the week's logged days, or all 7 days when
  /// none are logged) and the days that reached it, from the same engine and
  /// 90% rule as the protein streak. Null when no target can be computed.
  ({int target, int hitDays})? _weekProteinStats(WeeklyReport report, UserProfile profile) {
    final start = DateTime(report.weekStart.year, report.weekStart.month, report.weekStart.day);
    final loggedTargets = <double>[];
    final allTargets = <double>[];
    var hitDays = 0;
    for (var i = 0; i < 7; i++) {
      final date = DateTime(start.year, start.month, start.day + i);
      final target = NutritionTargetEngine.instance
          .effectiveTargetForDate(date, profile: profile)
          .protein;
      allTargets.add(target);
      final log = dayLogStore[dateKey(date)];
      if (log == null || log.isEmpty) continue;
      loggedTargets.add(target);
      if (_isProteinHit(log, profile, date)) hitDays++;
    }
    final source = loggedTargets.isNotEmpty ? loggedTargets : allTargets;
    final avg = source.fold<double>(0, (a, t) => a + t) / source.length;
    if (!avg.isFinite || avg <= 0) return null;
    return (target: avg.round(), hitDays: hitDays);
  }

  bool _isProteinHit(DayLog log, UserProfile profile, DateTime date) {
    if (log.isEmpty) return false;
    final target = NutritionTargetEngine.instance.effectiveTargetForDate(
      date,
      profile: profile,
    );

    final pro = log.totalProteinMid;
    final proRat = pro / target.protein.clamp(1.0, double.infinity);
    return proRat >= 0.90;
  }

  int getProteinStreak(UserProfile profile) {
    int streak = 0;
    final now = DateTime.now();

    // Check today
    final todayKey = dateKey(now);
    final todayLog = dayLogStore[todayKey];
    final todayLogged = todayLog != null && !todayLog.isEmpty;

    DateTime startCountingFrom;
    if (todayLogged) {
      if (_isProteinHit(todayLog, profile, now)) {
        streak = 1;
        startCountingFrom = now.subtract(const Duration(days: 1));
      } else {
        return 0; // Today is logged but target missed
      }
    } else {
      // Today is not logged yet, check yesterday
      final yesterdayDate = now.subtract(const Duration(days: 1));
      final yesterdayKey = dateKey(yesterdayDate);
      final yesterdayLog = dayLogStore[yesterdayKey];
      final yesterdayLogged = yesterdayLog != null && !yesterdayLog.isEmpty;
      if (yesterdayLogged && _isProteinHit(yesterdayLog, profile, yesterdayDate)) {
        streak = 1;
        startCountingFrom = yesterdayDate.subtract(const Duration(days: 1));
      } else {
        return 0;
      }
    }

    while (true) {
      final key = dateKey(startCountingFrom);
      final log = dayLogStore[key];
      if (log != null && !log.isEmpty && _isProteinHit(log, profile, startCountingFrom)) {
        streak++;
        startCountingFrom = startCountingFrom.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  bool _isCalorieHit(DayLog log, UserProfile profile, DateTime date) {
    if (log.isEmpty) return false;
    final target = NutritionTargetEngine.instance.effectiveTargetForDate(
      date,
      profile: profile,
    );

    final cals = log.totalCaloriesMid;
    final calRat = cals / target.calories.clamp(1.0, double.infinity);
    return calRat >= 0.88 && calRat <= 1.08;
  }

  int getCalorieStreak(UserProfile profile) {
    int streak = 0;
    final now = DateTime.now();

    // Check today
    final todayKey = dateKey(now);
    final todayLog = dayLogStore[todayKey];
    final todayLogged = todayLog != null && !todayLog.isEmpty;

    DateTime startCountingFrom;
    if (todayLogged) {
      if (_isCalorieHit(todayLog, profile, now)) {
        streak = 1;
        startCountingFrom = now.subtract(const Duration(days: 1));
      } else {
        return 0; // Today is logged but target missed
      }
    } else {
      // Today is not logged yet, check yesterday
      final yesterdayDate = now.subtract(const Duration(days: 1));
      final yesterdayKey = dateKey(yesterdayDate);
      final yesterdayLog = dayLogStore[yesterdayKey];
      final yesterdayLogged = yesterdayLog != null && !yesterdayLog.isEmpty;
      if (yesterdayLogged && _isCalorieHit(yesterdayLog, profile, yesterdayDate)) {
        streak = 1;
        startCountingFrom = yesterdayDate.subtract(const Duration(days: 1));
      } else {
        return 0;
      }
    }

    while (true) {
      final key = dateKey(startCountingFrom);
      final log = dayLogStore[key];
      if (log != null && !log.isEmpty && _isCalorieHit(log, profile, startCountingFrom)) {
        streak++;
        startCountingFrom = startCountingFrom.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }
}
