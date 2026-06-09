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
import 'cloud_sync_service.dart';
import '../services/persistence_service.dart';
import 'workout_service.dart';
import 'nutrition_target_engine.dart';

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

  Map<String, WeeklyReport>    _weekly       = {};
  Map<String, MonthlyReport>   _monthly      = {};
  Map<String, YearlyReport>    _yearly       = {};
  PersonalBests?               _personalBests;
  List<Achievement>            _achievements = [];
  Map<String, InsightsSummary> _aiSummaries  = {};
  DateTime?                    _lastComputed;

  // ── Init (called in PersistenceService.load()) ─────────────────────────────
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final weeklyRaw = prefs.getString(_kWeekly);
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
              debugPrint('[InsightsReportService] Error parsing weekly report $k: $inner');
            }
          });
        } catch (outer) {
          debugPrint('[InsightsReportService] Error decoding weekly cache: $outer');
        }
      }

      final monthlyRaw = prefs.getString(_kMonthly);
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
              debugPrint('[InsightsReportService] Error parsing monthly report $k: $inner');
            }
          });
        } catch (outer) {
          debugPrint('[InsightsReportService] Error decoding monthly cache: $outer');
        }
      }

      final yearlyRaw = prefs.getString(_kYearly);
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
              debugPrint('[InsightsReportService] Error parsing yearly report $k: $inner');
            }
          });
        } catch (outer) {
          debugPrint('[InsightsReportService] Error decoding yearly cache: $outer');
        }
      }

      final pbRaw = prefs.getString(_kPersonalBests);
      if (pbRaw != null) {
        try {
          final pb = PersonalBests.fromJson(jsonDecode(pbRaw) as Map<String, dynamic>);
          if (pb.schemaVersion == kInsightsSchemaVersion) {
            _personalBests = pb;
          }
        } catch (e) {
          debugPrint('[InsightsReportService] Error parsing personal bests cache: $e');
        }
      }

      final achievementsRaw = prefs.getString(_kAchievements);
      if (achievementsRaw != null) {
        try {
          final list = jsonDecode(achievementsRaw) as List<dynamic>;
          _achievements = list
              .map((item) => Achievement.fromJson(item as Map<String, dynamic>))
              .toList();
        } catch (e) {
          debugPrint('[InsightsReportService] Error parsing achievements cache: $e');
        }
      }

      final aiRaw = prefs.getString(_kAiSummaries);
      if (aiRaw != null) {
        try {
          final map = jsonDecode(aiRaw) as Map<String, dynamic>;
          _aiSummaries = map.map((k, v) => MapEntry(k, InsightsSummary.fromJson(v as Map<String, dynamic>)));
        } catch (e) {
          debugPrint('[InsightsReportService] Error parsing AI summaries cache: $e');
        }
      }

      final lastComputedRaw = prefs.getString(_kLastComputed);
      if (lastComputedRaw != null) {
        _lastComputed = DateTime.tryParse(lastComputedRaw);
      }
    } catch (e) {
      debugPrint('[InsightsReportService] Error loading cached insights: $e');
    }
  }

  // ── Compute triggers ───────────────────────────────────────────────────────
  // Post-hydration: only recomputes if > 60 min stale or never computed
  Future<void> maybeRecompute(UserProfile profile) async {
    final now = DateTime.now();
    if (_lastComputed == null || now.difference(_lastComputed!).inMinutes > 60) {
      await _recompute(profile);
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
          debugPrint('[InsightsReportService] On-demand compute for week $key failed: $e');
        }
      }
    }
    return _weekly[key];
  }

  MonthlyReport? monthlyFor(String key) {
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
          debugPrint('[InsightsReportService] On-demand compute for month $key failed: $e');
        }
      }
    }
    return _monthly[key];
  }

  YearlyReport? yearlyFor(String key) {
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
          debugPrint('[InsightsReportService] On-demand compute for year $key failed: $e');
        }
      }
    }
    return _yearly[key];
  }
  PersonalBests?          get personalBests      => _personalBests;
  List<Achievement>       get achievements       => List.unmodifiable(_achievements);
  int                     get newAchievementCount => _achievements.where((a) => a.isNew).length;
  InsightsSummary?        aiSummaryFor(String k) => _aiSummaries[k];
  DateTime?               get lastComputed       => _lastComputed;

  // AchievementProgress is computed on call — NOT cached, NOT in build()
  List<AchievementProgress> get progress =>
      InsightsEngine.computeProgress(_achievements, dayLogStore, ProfileService.instance.currentUserProfile ?? const UserProfile(name: '', age: 0, gender: '', height: 0, weight: 0, workoutDaysMin: 0, workoutDaysMax: 0, goal: ''), WorkoutService.instance.sessions);

  Map<String, WeeklyReport> get weeklyCache => Map.unmodifiable(_weekly);
  Map<String, MonthlyReport> get monthlyCache => Map.unmodifiable(_monthly);
  Map<String, YearlyReport> get yearlyCache => Map.unmodifiable(_yearly);

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
      await prefs.setString(_kAchievements, jsonEncode(_achievements.map((a) => a.toJson()).toList()));
      notifyListeners();
    }
  }

  Future<void> mergeAchievementsFromCloud(List<Achievement> cloud) async {
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
      await prefs.setString(_kAchievements, jsonEncode(_achievements.map((a) => a.toJson()).toList()));
      notifyListeners();
    }
  }

  Future<void> reset() async {
    _weekly.clear();
    _monthly.clear();
    _yearly.clear();
    _personalBests = null;
    _achievements.clear();
    _aiSummaries.clear();
    _lastComputed = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kWeekly);
    await prefs.remove(_kMonthly);
    await prefs.remove(_kYearly);
    await prefs.remove(_kPersonalBests);
    await prefs.remove(_kAchievements);
    await prefs.remove(_kAiSummaries);
    await prefs.remove(_kLastComputed);

    notifyListeners();
  }

  // ── Internal ──────────────────────────────────────────────────────────────
  Future<void> _recompute(UserProfile profile) async {
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
    await prefs.setString(_kWeekly, jsonEncode(_weekly.map((k, v) => MapEntry(k, v.toJson()))));
    await prefs.setString(_kMonthly, jsonEncode(_monthly.map((k, v) => MapEntry(k, v.toJson()))));
    await prefs.setString(_kYearly, jsonEncode(_yearly.map((k, v) => MapEntry(k, v.toJson()))));
    if (_personalBests != null) {
      await prefs.setString(_kPersonalBests, jsonEncode(_personalBests!.toJson()));
    }
    await prefs.setString(_kAchievements, jsonEncode(_achievements.map((a) => a.toJson()).toList()));
    await prefs.setString(_kAiSummaries, jsonEncode(_aiSummaries.map((k, v) => MapEntry(k, v.toJson()))));
    if (_lastComputed != null) {
      await prefs.setString(_kLastComputed, _lastComputed!.toIso8601String());
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
  Future<void> _generateAiSummaryIfNeeded(WeeklyReport report, UserProfile profile) async {
    final existing = _aiSummaries[report.weekKey];
    if (existing != null && !existing.isStale) return;

    try {
      final status = await ChatGptLinkService.getStatus();
      if (!status.isConnected) return;

      final systemPrompt = 'You are Kyno, an elite Indian-first fat-loss nutrition coach. Analyze the user\'s weekly report data and write a highly encouraging, 2-3 sentence summary of their week. Focus on consistency, protein target hit rate, and workout habits. Avoid technical or developer jargon. Do not mention "adherence score", "pipeline", "delta", or "regression" in your summary. Be brief, specific, and actionable.';
      final userPrompt = 'Weekly Report Data:\n'
          '- Week: ${report.weekKey}\n'
          '- Consistency Score: ${report.consistencyScore.score}/100\n'
          '- Logged Days: ${report.loggedDaysCount}/7\n'
          '- Gym Days: ${report.gymDaysCount}\n'
          '- Avg Calories: ${report.avgCalories.round()} kcal\n'
          '- Avg Protein: ${report.avgProtein.round()}g\n'
          '${report.deltaVsPrior != null ? '- Score change vs last week: ${report.deltaVsPrior!.consistencyScoreDelta ?? 0} pts' : ''}\n'
          '${report.topImprovement != null ? '- Top improvement: ${report.topImprovement!.label}' : ''}\n'
          'User Name: ${profile.name}';

      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;

      final res = await Supabase.instance.client.functions.invoke(
        'ai-chat-router',
        body: {
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ]
        },
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );

      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        final narrative = data['response'] as String? ?? '';
        if (narrative.isNotEmpty) {
          _aiSummaries[report.weekKey] = InsightsSummary(
            weekKey: report.weekKey,
            narrative: narrative.trim(),
            generatedAt: DateTime.now(),
            isStale: false,
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kAiSummaries, jsonEncode(_aiSummaries.map((k, v) => MapEntry(k, v.toJson()))));
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[InsightsReportService] AI Summary generation error: $e');
    }
  }

  Future<void> recomputeForDate(DateTime date, UserProfile profile) async {
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
    await _save();
    notifyListeners();

    // Trigger AI summary generation if connected and latest weekly report exists
    final latestW = latestWeekly();
    if (latestW != null && latestW.weekKey == wKey) {
      _generateAiSummaryIfNeeded(latestW, profile).ignore();
    }
  }

  Future<void> mergeCacheFromCloud(Map<String, dynamic> cache) async {
    try {
      final weeklyJson = cache['weekly_json'] as Map<String, dynamic>?;
      final monthlyJson = cache['monthly_json'] as Map<String, dynamic>?;
      final yearlyJson = cache['yearly_json'] as Map<String, dynamic>?;
      final pbJson = cache['personal_bests_json'] as Map<String, dynamic>?;

      if (weeklyJson != null) {
        _weekly = weeklyJson.map((k, v) => MapEntry(k, WeeklyReport.fromJson(v as Map<String, dynamic>)));
      }
      if (monthlyJson != null) {
        _monthly = monthlyJson.map((k, v) => MapEntry(k, MonthlyReport.fromJson(v as Map<String, dynamic>)));
      }
      if (yearlyJson != null) {
        _yearly = yearlyJson.map((k, v) => MapEntry(k, YearlyReport.fromJson(v as Map<String, dynamic>)));
      }
      if (pbJson != null) {
        _personalBests = PersonalBests.fromJson(pbJson);
      }
      _lastComputed = DateTime.now();
      await _save();
      notifyListeners();
    } catch (e) {
      debugPrint('[InsightsReportService] Error merging cache from cloud: $e');
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

  bool _isProteinHit(DayLog log, UserProfile profile, DateTime date) {
    if (log.isEmpty) return false;
    final session = WorkoutService.instance.sessionFor(date);
    final isGymDay = (log.gymDay?.didGym == true) || (session != null && !session.isEmpty);
    final target = NutritionTargetEngine.instance.dayTarget(
      profile,
      isGymDay: isGymDay,
      session: session,
      workoutTypeName: log.gymDay?.workoutType?.displayName ?? log.gymDay?.splitDayName,
      date: date,
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
    final session = WorkoutService.instance.sessionFor(date);
    final isGymDay = (log.gymDay?.didGym == true) || (session != null && !session.isEmpty);
    final target = NutritionTargetEngine.instance.dayTarget(
      profile,
      isGymDay: isGymDay,
      session: session,
      workoutTypeName: log.gymDay?.workoutType?.displayName ?? log.gymDay?.splitDayName,
      date: date,
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
