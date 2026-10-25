import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../ui/k_brand_intro.dart' show KShearWordmark;
import '../ui/k_toast.dart';
import '../services/ai_coach_service.dart';
import '../services/chatgpt_link_service.dart';
import '../models/day_log.dart';
import '../services/health_service.dart' show WeightContext;
import '../services/kyno_assistant_service.dart';
import '../services/kyno_brief_service.dart';
import '../services/kyno_coaching_insight_service.dart';
import '../services/kyno_context_service.dart' show KynoInsightItem;
import '../services/kyno_fuel_planner.dart';
import '../services/persistence_service.dart';
import '../services/profile_service.dart';
import '../services/user_session_coordinator.dart';
import '../services/workout_service.dart';
import '../widgets/kyno_avatar.dart';
import '../widgets/kyno_notes_sheet.dart';
import '../services/kyno_notes_service.dart';
import '../services/kyno_report_service.dart';
import '../widgets/kyno_presence.dart';
import '../widgets/k_typing_dots.dart';
import 'add_meal_screen.dart';
import 'day_detail_screen.dart';
import '../services/analytics_service.dart';

// ─── Chat message model ───────────────────────────────────────────────────────

enum _Role { user, assistant }

class _ChatMessage {
  final _Role      role;
  final String     text;
  final List<Uint8List>? imagesBytes;

  /// Food options that fit the day, shown under a "what should I eat" answer.
  final FuelPlan?  fuel;

  /// Answered on the phone because there was no connection.
  final bool       offline;

  const _ChatMessage({
    required this.role,
    required this.text,
    this.imagesBytes,
    this.fuel,
    this.offline = false,
  });
}

// ─── AiCoachScreen ────────────────────────────────────────────────────────────
// Motion moments (all through KMotion; reduced motion = end state):
// • Bubble entrance — each NEW message slides in from its own side once.
//   History that already existed when the screen opened appears in place.
// • Kyno tail       — typing dots then the live streaming bubble share ONE
//   entrance; token updates only rebuild the markdown, never the entrance.
//   When the stream commits, the final message is pre-marked as entered.
// • Thinking        — KOrbitLoader + a KLoadingLabel line in the Kyno tail.
// • Plan status     — "Using ChatGPT plan" chip, or a calm fallback notice,
//   swapped above the composer with AnimatedSwitcher + AnimatedSize.
// • Send            — squash on press, pop + KHaptics.commit() on a real send.
// • Empty state     — one orchestrated stagger (orb, title, chips).

class AiCoachScreen extends StatefulWidget {
  final String  dateKey;    // YYYY-MM-DD
  final bool?   isGymDay;   // real-time gym state from DayDetailScreen
  final String? workoutType; // e.g. 'Push', 'Pull'
  final double? targetCaloriesOverride; // active manual calorie override for this day
  final WeightContext? weightContext;   // compact weight summary from Health Connect

  /// True when this is the Kyno tab inside the app shell: no back button,
  /// transparent so the aurora shows, composer above the dock, and "today"
  /// is always the current day.
  final bool embedded;

  const AiCoachScreen({
    super.key,
    required this.dateKey,
    this.isGymDay,
    this.workoutType,
    this.targetCaloriesOverride,
    this.weightContext,
    this.embedded = false,
  });

  /// The Kyno tab.
  factory AiCoachScreen.tab({Key? key}) =>
      AiCoachScreen(key: key, dateKey: '', embedded: true);

  @override
  State<AiCoachScreen> createState() => _AiCoachScreenState();
}

class _AiCoachScreenState extends State<AiCoachScreen>
    with WidgetsBindingObserver {
  final _controller    = TextEditingController();
  final _scrollCtrl    = ScrollController();
  final _imagePicker   = ImagePicker();
  final _inputFocusNode = FocusNode();

  // Per account, so a second account on the phone never sees the first one's
  // chat. Static so the chat survives tab switches and navigation.
  static final Map<String, List<_ChatMessage>> _historyByUser = {};
  // Today's chat is shared by the tab and the day screen; a past day has
  // its own thread.
  String get _threadKey {
    final user = UserSessionCoordinator.instance.currentUserId ?? '_signed_out';
    return _isToday ? user : '$user:${widget.dateKey}';
  }
  List<_ChatMessage> get _messages =>
      _historyByUser.putIfAbsent(_threadKey, () => <_ChatMessage>[]);

  bool        _loading      = false;
  bool        _isStreaming  = false;
  final ValueNotifier<String> _streamingTextNotifier = ValueNotifier<String>('');
  final List<Uint8List> _pendingImages = [];
  bool        _isInputFocused = false;

  // Messages whose entrance already played (or that pre-date this screen).
  final Set<_ChatMessage> _entered = Set<_ChatMessage>.identity();
  // One entrance per Kyno reply "tail" (typing → streaming).
  int _tailSeq = 0;
  final Set<int> _enteredTails = {};

  // ChatGPT plan status (OpenAI UI rules): a chip while the plan answers, a
  // one-line notice when the server fell back to the standard model.
  ChatGptLinkStatus? _planStatus;
  String? _planNotice;
  bool _sawReply = false;

  // Kyno's face: a short wave when the screen first opens, then it follows
  // what's happening (listening, thinking, talking).
  bool _greeting = true;
  Timer? _greetTimer;
  KynoBrief? _brief;

  String get _dateKey => widget.embedded ? dateKey(DateTime.now()) : widget.dateKey;
  bool get _isToday => _dateKey == dateKey(DateTime.now());

  @override
  void initState() {
    super.initState();
    _entered.addAll(_messages);
    WidgetsBinding.instance.addObserver(this);
    _planNotice = AiCoachService.instance.planFallbackReason.value;
    AiCoachService.instance.planFallbackReason.addListener(_onPlanReason);
    _loadPlanStatus();
    _inputFocusNode.addListener(() {
      setState(() {
        _isInputFocused = _inputFocusNode.hasFocus;
      });
    });
    _controller.addListener(_onTyping);
    PersistenceService.dayLogNotifier.addListener(_invalidateBrief);
    _greetTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _greeting = false);
    });
  }

  bool _hadText = false;
  void _onTyping() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hadText) {
      _hadText = has;
      setState(() {});
    }
  }

  void _invalidateBrief() {
    if (!mounted) return;
    setState(() => _brief = null);
  }

  DateTime? _briefAt;
  Object? _briefStamp;

  /// The app brief for today, rebuilt when logs or workouts change (some
  /// save paths don't notify), or when it's more than 20 s old.
  KynoBrief? get _todayBrief {
    if (!_isToday) return null;
    final stamp = (
      PersistenceService.lastLogsChangedAt,
      WorkoutService.instance.lastWorkoutsChangedAt,
      dayLogStore[dateKey(DateTime.now())]?.allEntries.length ?? 0,
    );
    final stale = _brief == null ||
        _briefStamp != stamp ||
        _briefAt == null ||
        DateTime.now().difference(_briefAt!) > const Duration(seconds: 20);
    try {
      if (stale) {
        _brief = KynoBriefService.instance.build();
        _briefAt = DateTime.now();
        _briefStamp = stamp;
      }
      return _brief;
    } catch (e) {
      debugPrint('[KYNO] Brief unavailable: $e');
      return null;
    }
  }

  KynoMood get _mood {
    if (_isStreaming) return KynoMood.talking;
    if (_loading) return KynoMood.thinking;
    if (_isInputFocused && _hadText) return KynoMood.listening;
    if (_greeting && _messages.isEmpty) return KynoMood.celebrate;
    return KynoMood.idle;
  }

  @override
  void didChangeMetrics() {
    // Keyboard opened/closed — scroll to bottom so last message stays visible
    final kb = WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom;
    // Follows the keyboard frame by frame with jumps (only when the reader
    // is at the end); restarting an eased scroll every frame would stutter.
    if (kb > 50) _scrollToBottom(follow: true);
  }

  Future<void> _loadPlanStatus() async {
    try {
      final status = await ChatGptLinkService.getStatus();
      if (!mounted) return;
      setState(() {
        _planStatus = status;
        // Until a reply says otherwise, a paused, ineligible or expired plan
        // means Kyno is already on the standard model.
        if (!_sawReply && _planNotice == null && status.usesChatGptPlan) {
          final paused = status.planPausedUntil?.isAfter(DateTime.now()) ?? false;
          if (paused) {
            _planNotice = status.fallbackReason ?? 'usage_limit';
          } else if (status.fallbackReason == 'not_eligible') {
            _planNotice = 'not_eligible';
          } else if (status.tokenExpired) {
            _planNotice = 'expired';
          }
        }
      });
    } catch (e) {
      debugPrint('[AI_COACH_SCREEN] Plan status unavailable: $e');
    }
  }

  void _onPlanReason() {
    if (!mounted) return;
    setState(() {
      _sawReply = true;
      _planNotice = AiCoachService.instance.planFallbackReason.value;
    });
  }

  Future<void> _openManageUsage() async {
    final toaster = KToaster.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(ChatGptLinkService.manageUsageUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('[AI_COACH_SCREEN] Could not open usage settings: $e');
    }
    if (!opened) {
      _showToast(toaster, 'Couldn\'t open ChatGPT settings. Try again in a moment.', error: true);
    }
  }

  @override
  void dispose() {
    _greetTimer?.cancel();
    PersistenceService.dayLogNotifier.removeListener(_invalidateBrief);
    AiCoachService.instance.planFallbackReason.removeListener(_onPlanReason);
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollCtrl.dispose();
    _inputFocusNode.dispose();
    _streamingTextNotifier.dispose();
    super.dispose();
  }

  /// Coalesces scroll requests: streaming calls this once per token, so a
  /// frame runs at most one scroll, after layout (when the new extent is known).
  bool _scrollQueued = false;

  /// True while the reader is at the end of the thread. A drag away from the
  /// end clears it (Kyno stops pulling them down mid-read); coming back to
  /// the end, or sending, sets it again.
  bool _pinned = true;
  bool _userDragging = false;
  bool _easing = false;

  /// [follow]: content is growing under the reader (streaming tokens, the
  /// keyboard opening). The end is held with a jump each frame, and only
  /// when pinned: the growth itself is the motion. Otherwise one eased
  /// scroll to the end (a new message).
  void _scrollToBottom({bool follow = false}) {
    if (_scrollQueued) return;
    _scrollQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollQueued = false;
      if (!mounted || !_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      final target = pos.maxScrollExtent;
      if ((target - pos.pixels).abs() < 0.5) return;
      if (follow) {
        // An eased scroll in flight lands first, then catches up (below).
        if (!_pinned || _easing || _userDragging) return;
        _scrollCtrl.jumpTo(target);
        return;
      }
      _pinned = true;
      final d = KMotion.of(context, KMotion.standard);
      if (d == Duration.zero) {
        _scrollCtrl.jumpTo(target);
        return;
      }
      _easing = true;
      _scrollCtrl.animateTo(target, duration: d, curve: Curves.easeOutCubic).whenComplete(() {
        _easing = false;
        if (mounted) _scrollToBottom(follow: true);
      });
    });
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _userDragging = true;
    } else if (n is ScrollUpdateNotification && n.dragDetails != null) {
      _userDragging = true;
      _pinned = false;
    } else if (n is ScrollEndNotification && _userDragging) {
      _userDragging = false;
      final m = n.metrics;
      _pinned = m.maxScrollExtent - m.pixels < 48;
    }
    return false;
  }

  /// The coach backend accepts at most this many photos per message.
  static const int maxPhotosPerMessage = 6;

  /// ...and rejects any single photo over about 2 MB.
  static const int maxPhotoBytes = 2 * 1024 * 1024;

  static const String photoCapMessage =
      'Kyno can look at 6 photos per message. Send these first, then add more.';
  static const String photoTooLargeMessage =
      "That photo's too large for Kyno. Try a smaller one.";

  Future<void> _pickImage() async {
    final toaster = KToaster.of(context);
    if (_pendingImages.length >= maxPhotosPerMessage) {
      KHaptics.reject();
      _showToast(toaster, photoCapMessage);
      return;
    }
    final source = await showKSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: KSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const KSheetHeader('Add a photo', subtitle: 'Menus, plates or delivery screenshots'),
              _SheetOption(
                icon: Icons.camera_alt_rounded,
                label: 'Take photo',
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              _SheetOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from gallery',
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null || !mounted) return;

    final remaining = maxPhotosPerMessage - _pendingImages.length;
    if (remaining <= 0) return;

    final List<XFile> xFiles;
    if (source == ImageSource.camera || remaining == 1) {
      // pickMultiImage needs a limit of at least 2, so one free slot picks one.
      final xFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1024,
      );
      xFiles = xFile == null ? const [] : [xFile];
    } else {
      xFiles = await _imagePicker.pickMultiImage(
        imageQuality: 75,
        maxWidth: 1024,
        limit: remaining,
      );
    }
    if (xFiles.isEmpty || !mounted) return;

    final accepted = <Uint8List>[];
    var tooLarge = 0;
    var overCap = 0;
    for (final xFile in xFiles) {
      if (_pendingImages.length + accepted.length >= maxPhotosPerMessage) {
        overCap++;
        continue;
      }
      final bytes = await xFile.readAsBytes();
      if (!mounted) return;
      if (bytes.length > maxPhotoBytes) {
        tooLarge++;
        continue;
      }
      accepted.add(bytes);
    }
    if (accepted.isNotEmpty) {
      setState(() {
        // Re-check: the cap holds even if another pick landed meanwhile.
        for (final b in accepted) {
          if (_pendingImages.length >= maxPhotosPerMessage) {
            overCap++;
            break;
          }
          _pendingImages.add(b);
        }
      });
    }
    if (overCap > 0) {
      _showToast(toaster, photoCapMessage);
    } else if (tooLarge > 0) {
      _showToast(toaster, photoTooLargeMessage, error: true);
    }
  }

  bool get _canSend =>
      (_controller.text.trim().isNotEmpty || _pendingImages.isNotEmpty) &&
      !_loading &&
      !_isStreaming;

  /// "What should I eat…", "how do I hit my protein", "dinner ideas"…
  static final RegExp _foodQuestion = RegExp(
    r'\b(eat|eating|food|foods|meal|meals|snack|dinner|lunch|breakfast|macro|macros|'
    r'protein left|hit my|hungry|khana|khaana|order|recipe|calories left)\b',
    caseSensitive: false,
  );

  Future<void> _send([String? overrideText]) async {
    final text = (overrideText ?? _controller.text).trim();
    if ((text.isEmpty && _pendingImages.isEmpty) || _loading || _isStreaming) return;

    final imageList = List<Uint8List>.from(_pendingImages);
    AnalyticsService.instance.track('kyno_message_sent', {'has_photo': imageList.isNotEmpty});
    setState(() {
      _messages.add(_ChatMessage(role: _Role.user, text: text, imagesBytes: imageList));
      _loading       = true;
      _isStreaming   = false;
      _streamingTextNotifier.value = '';
      _pendingImages.clear();
      _tailSeq++;
      _greeting = false;
    });
    _controller.clear();
    _scrollToBottom();

    // Fresh brief for every question: it reads the log as it is right now.
    _brief = null;
    final brief = _todayBrief;
    final plan = brief?.fuelPlan;
    final wantsFood = imageList.isEmpty && _foodQuestion.hasMatch(text);

    try {
      // Everything before this question. Photos stay in the thread as a note
      // (Kyno's reply already describes them); answers written on the phone
      // while the AI was down aren't the model's words, so they're left out.
      // Only the latest [maxHistoryMessages] go up, oldest first, so a long
      // chat never grows the request without bound.
      final thread = _messages
          .take(_messages.length - 1)
          .where((m) => !m.offline)
          .map((m) {
            final photos = m.imagesBytes?.length ?? 0;
            final note = photos == 0 ? '' : (photos == 1 ? '[sent a photo]' : '[sent $photos photos]');
            final content = [if (note.isNotEmpty) note, if (m.text.isNotEmpty) m.text].join(' ');
            return {
              'role': m.role == _Role.user ? 'user' : 'assistant',
              'content': content,
            };
          })
          .where((h) => (h['content'] as String).isNotEmpty)
          .toList();
      final history = recentHistory(thread);

      final dayPlan = widget.embedded ? WorkoutService.instance.planFor(DateTime.now()) : null;
      final stream = AiCoachService.instance.streamMessage(
        message:                text,
        imagesBytes:            imageList,
        dateKey:                _dateKey,
        isGymDay:               widget.isGymDay ?? dayPlan?.isTraining,
        workoutType:            widget.workoutType ?? dayPlan?.name,
        targetCaloriesOverride: widget.targetCaloriesOverride,
        conversationHistory:    history,
        weightContext:          widget.weightContext,
        appContext:             brief?.json,
      );

      bool firstChunk = true;
      await for (final token in stream) {
        if (!mounted) return;
        if (firstChunk) {
          setState(() {
            _loading     = false;   // hide typing dots
            _isStreaming = true;    // show live bubble
          });
          firstChunk   = false;
        }
        _streamingTextNotifier.value += token;
        _scrollToBottom(follow: true);
      }

      // Stream completed — commit to history
      if (!mounted) return;
      final finalResponseText = _streamingTextNotifier.value;
      setState(() {
        _isStreaming = false;
        _loading     = false;
        if (finalResponseText.isNotEmpty) {
          final committed = _ChatMessage(
            role: _Role.assistant,
            text: finalResponseText,
            fuel: wantsFood && plan != null && !plan.isEmpty ? plan : null,
          );
          // The live bubble already entered; the committed copy must not
          // replay the entrance.
          _entered.add(committed);
          _messages.add(committed);
        }
        _streamingTextNotifier.value = '';
      });
      _scrollToBottom(follow: true);

    } catch (e) {
      if (!mounted) return;
      debugPrint('[AI_COACH_SCREEN] Stream failed: $e');
      // No connection, or the AI service is down (5xx): answer from the
      // phone instead of a dead end.
      final serverDown = (_aiCoachStatusOf(e) ?? 0) >= 500;
      if ((_isOffline(e) || serverDown) && imageList.isEmpty && text.isNotEmpty) {
        final local = await _localAnswer(text, wantsFood ? plan : null, serverDown: serverDown);
        if (!mounted) return;
        setState(() {
          _loading = false;
          _isStreaming = false;
          _messages.add(local);
          _streamingTextNotifier.value = '';
        });
        _scrollToBottom();
        return;
      }
      // Keep the question (and photos) so the user can retry without retyping.
      if (_controller.text.isEmpty && text.isNotEmpty) {
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
      setState(() {
        _loading     = false;
        _isStreaming = false;
        if (_pendingImages.isEmpty) _pendingImages.addAll(imageList);
        _messages.add(_ChatMessage(
          role: _Role.assistant,
          text: '${_friendlyError(e)}\n\n'
              'Your question\'s back in the box, so just tap send.',
        ));
        _streamingTextNotifier.value = '';
      });
      _scrollToBottom();
    }
  }

  static bool _isOffline(Object e) {
    final raw = e.toString().toLowerCase();
    return raw.contains('socket') ||
        raw.contains('failed host lookup') ||
        raw.contains('clientexception') ||
        raw.contains('connection');
  }

  /// Kyno's on-device answer: the rule-based reader plus today's food plan.
  Future<_ChatMessage> _localAnswer(String text, FuelPlan? plan, {bool serverDown = false}) async {
    final buf = StringBuffer(serverDown
        ? "_Kyno's AI is unavailable right now, so this is from your logs on the phone._\n\n"
        : '_No connection, so this is from your logs on the phone._\n\n');
    try {
      final reply = await KynoAssistantService.instance.processQuery(text);
      buf.writeln(reply.text);
      for (final i in reply.structuredInsights ?? const <KynoInsightItem>[]) {
        buf.writeln('\n**${i.title}**  \n${i.detail}');
      }
    } catch (_) {
      buf.writeln(plan?.headline ?? "I can't read your logs right now.");
    }
    return _ChatMessage(role: _Role.assistant, text: buf.toString().trim(), fuel: plan, offline: true);
  }

  /// Logs a suggested food or combo: the meal screen opens with it typed in
  /// and estimates it, so the numbers are confirmed before anything is saved.
  Future<void> _logSuggestion(String text) async {
    KHaptics.select();
    final now = DateTime.now();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddMealScreen(
          section: DayDetailScreen.getSectionForTimeAndDate(now, now),
          date: now,
          initialText: text,
        ),
      ),
    );
    if (mounted) _invalidateBrief();
  }

  void _newChat() {
    KHaptics.select();
    setState(() {
      _messages.clear();
      _entered.clear();
      _greeting = true;
    });
    _greetTimer?.cancel();
    _greetTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _greeting = false);
    });
  }

  /// Calm, actionable copy for a failed reply. Never raw exception text.
  static String _friendlyError(Object e) => aiCoachFriendlyError(e);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // On the tab: depend on TickerMode so coming back to Kyno rebuilds it
    // (the shell keeps the same widget instance), refreshing today's numbers.
    if (widget.embedded) TickerMode.valuesOf(context);
    final body = Column(
      children: [
        if (widget.embedded) _buildTabHeader(),
        Expanded(
          child: (_messages.isEmpty && !_isStreaming)
              ? _buildEmptyState()
              : _buildMessageList(),
        ),
        if (_pendingImages.isNotEmpty) _buildImagePreview(),
        _buildInputBar(),
      ],
    );
    if (widget.embedded) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: SafeArea(bottom: false, child: body),
      );
    }
    return KPage(
      tone: KTone.kyno,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: body,
    );
  }

  String get _status {
    if (_isStreaming) return 'Answering…';
    if (_loading) return 'Reading your logs…';
    if (!_isToday) return 'Looking at ${_prettyDate(_dateKey)}';
    return 'Your coach for food, training and recovery';
  }

  static String _prettyDate(String key) {
    final d = DateTime.tryParse(key);
    if (d == null) return key;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]}';
  }

  Widget _buildTabHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.sm, KSpacing.sm, KSpacing.xs),
      child: Row(
        children: [
          KynoAvatar(size: 46, mood: _mood),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Kyno', style: KText.h2),
                AnimatedSwitcher(
                  duration: KMotion.of(context, KMotion.quick),
                  child: Text(
                    _status,
                    key: ValueKey(_status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KText.caption.copyWith(color: KColor.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<List<String>>(
            valueListenable: KynoNotesService.instance.notes,
            builder: (context, notes, _) => IconButton(
              tooltip: notes.isEmpty ? 'What Kyno remembers' : 'What Kyno remembers, ${notes.length}',
              onPressed: () => showKynoNotesSheet(context),
              icon: Badge(
                isLabelVisible: notes.isNotEmpty,
                backgroundColor: KColor.ember,
                smallSize: 7,
                child: Icon(Icons.bookmark_border_rounded, color: KColor.textSecondary),
              ),
            ),
          ),
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: 'New chat',
              onPressed: (_loading || _isStreaming) ? null : _newChat,
              icon: Icon(Icons.edit_note_rounded, color: KColor.textSecondary),
            ),
        ],
      ),
    );
  }

  /// One-tap coaching modes: each asks a fuller question than a chip could.
  static const _focusModes = <(String, IconData, String)>[
    ('Check-in', Icons.wb_twilight_rounded,
        "Give me today's check-in: where I stand on calories, protein and training, and the one thing to do next."),
    ('Week review', Icons.calendar_view_week_rounded,
        'Review my last 7 days against the 7 before: eating, protein, training volume, steps and weight. What improved, what slipped, and one change for next week.'),
    ('Meal idea', Icons.restaurant_rounded,
        'Suggest my next meal from foods I usually eat so I land close to my targets today. Exact quantities please.'),
    ('Training', Icons.fitness_center_rounded,
        'How is my training going? Which lifts are moving, which are stuck, and why, using my eating and sets per muscle.'),
    ('Body', Icons.monitor_weight_outlined,
        'Is my weight trend on pace for my goal? Use the smoothed trend, not single weigh-ins, and tell me if my calories need to change.'),
  ];

  Widget _buildFocusModes() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _focusModes.length,
        separatorBuilder: (_, _) => const SizedBox(width: KSpacing.sm),
        itemBuilder: (context, i) {
          final (label, icon, prompt) = _focusModes[i];
          return Pressable(
            onTap: () {
              kHapticSelect();
              _send(prompt);
            },
            borderRadius: KRadius.pill,
            semanticLabel: 'Ask Kyno: $label',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: KColor.card,
                borderRadius: KRadius.pill,
                border: Border.all(color: KColor.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: KColor.textPrimary),
                  const SizedBox(width: 6),
                  Text(label, style: KText.bodyMedium.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: KColor.textPrimary),
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          KynoAvatar(size: 38, mood: _mood),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Kyno', style: KText.h2),
                Text(
                  _status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KText.caption.copyWith(color: KColor.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Questions worth asking right now, from the user's own data.
  List<String> _suggestions(KynoBrief? brief) {
    final out = <String>[];
    final today = brief?.json['today'] as Map<String, dynamic>?;
    final remaining = today?['remaining'] as Map<String, dynamic>?;
    final proteinLeft = (remaining?['protein_g'] as num?) ?? 0;
    final kcalLeft = (remaining?['kcal'] as num?) ?? 0;
    if (proteinLeft > 10 || kcalLeft > 200) {
      out.add('What should I eat to hit my macros today?');
    }
    final training = brief?.json['training'] as Map<String, dynamic>?;
    final lifts = (training?['lifts'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final l in lifts) {
      final trend = l['trend'];
      final name = (l['exercise'] as String?)?.toLowerCase();
      if (name == null) continue;
      if (trend == 'up') {
        out.add('Why is my $name going up?');
        break;
      }
      if (trend == 'down' || trend == 'flat') {
        out.add('Why is my $name stuck?');
        break;
      }
    }
    out.add('Is my diet slipping this week?');
    out.add("Plan tomorrow's food around my training");
    out.add('How is my recovery looking?');
    if (out.length < 5) out.add('Give me a cheaper high-protein swap for what I eat');
    return out.take(5).toList();
  }

  Widget _buildEmptyState() {
    var i = 0;
    final brief = _todayBrief;
    final name = ProfileService.instance.currentUserProfile?.name.trim();
    final first = (name == null || name.isEmpty) ? null : name.split(' ').first;
    final hour = DateTime.now().hour;
    final hello = hour < 12 ? 'Morning' : (hour < 17 ? 'Afternoon' : 'Evening');
    final insights = _isToday
        ? KynoCoachingInsightService.instance.getActiveInsights()
        : const <KynoCoachingInsight>[];
    // A blank chat carries the mark: a big, faint sheared K behind the
    // greeting. It goes the moment the first message lands.
    return Stack(
      children: [
        Positioned(
          top: -KSpacing.md,
          right: KSpacing.sm,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: KShearWordmark(
                fontSize: 170,
                kOnly: true,
                ink: KColor.textPrimary.withValues(alpha: KColor.isDark ? 0.06 : 0.07),
                ember: KColor.ember.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
        _emptyList(i, brief, first, hello, insights),
      ],
    );
  }

  Widget _emptyList(int i, KynoBrief? brief, String? first, String hello, List<KynoCoachingInsight> insights) {
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.lg, KSpacing.p, KSpacing.xxl),
      children: [
        if (!widget.embedded) ...[
          KReveal(index: i++, child: Center(child: KynoAvatar(size: 104, mood: _mood))),
          const SizedBox(height: KSpacing.lg),
        ],
        KReveal(
          index: i++,
          child: Semantics(
            header: true,
            child: Text(
              first == null ? '$hello.' : '$hello, $first.',
              style: KText.display.copyWith(fontSize: 32, height: 1.08),
            ),
          ),
        ),
        const SizedBox(height: KSpacing.sm),
        KReveal(
          index: i++,
          child: Text(
            _isToday
                ? "I've read your last two weeks: meals, lifts, steps and weight. Ask me anything, "
                    "or start with one of these."
                : 'Ask about what you ate on ${_prettyDate(_dateKey)}.',
            style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 15, height: 1.5),
          ),
        ),
        if (brief != null) ...[
          const SizedBox(height: KSpacing.xl),
          KReveal(index: i++, child: _TodayBand(brief: brief)),
        ],
        if (_isToday) ...[
          const SizedBox(height: KSpacing.lg),
          KReveal(index: i++, child: _buildFocusModes()),
        ],
        if (insights.isNotEmpty) ...[
          const SizedBox(height: KSpacing.lg),
          KReveal(
            index: i++,
            child: _CheckInCard(
              insight: insights.first,
              onAsk: () => _send('Tell me more about this: ${insights.first.title}'),
              onDismiss: () => setState(() {
                KynoCoachingInsightService.instance.dismissInsight(insights.first.id);
              }),
            ),
          ),
        ],
        const SizedBox(height: KSpacing.xl),
        KReveal(
          index: i++,
          child: Semantics(
            header: true,
            child: Text(
              'Try asking',
              style: KText.caption.copyWith(color: KColor.textMuted, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: KSpacing.xs),
        for (final s in _suggestions(brief))
          KReveal(
            index: i++,
            rise: 8,
            child: _QuickChip(label: s, onTap: () => _send(s)),
          ),
        Container(height: 1, color: _hairline()),
        const SizedBox(height: KSpacing.xl),
        // Image upload hint: a quiet note, not a card.
        KReveal(
          index: i++,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: KIcon(Icons.add_photo_alternate_outlined, size: KIcons.md),
              ),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Snap a menu or your plate', style: KText.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      'Swiggy and Zomato screenshots work too. Numbers from a photo are Kyno\'s estimate.',
                      style: KText.caption.copyWith(color: KColor.textMuted, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    final hasTail = _loading || _isStreaming;
    // Lazily built; every row keyed by its message (the tail by its reply
    // number), so rows keep their element and entrance state as the
    // thread grows.
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.sm, KSpacing.lg, KSpacing.lg),
        itemCount: _messages.length + (hasTail ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _messages.length) {
            // Typing dots, then the live streaming bubble — one entrance.
            return _Entrance(
              key: ValueKey('kyno_tail_$_tailSeq'),
              animate: _enteredTails.add(_tailSeq),
              child: _KynoTail(
                streaming: _isStreaming,
                textListenable: _streamingTextNotifier,
                lookingAtPhoto: _messages.isNotEmpty &&
                    _messages.last.role == _Role.user &&
                    (_messages.last.imagesBytes?.isNotEmpty ?? false),
              ),
            );
          }
          final msg = _messages[i];
          return _Entrance(
            key: ObjectKey(msg),
            animate: _entered.add(msg),
            fromUser: msg.role == _Role.user,
            child: _ChatBubble(
              message: msg,
              role: msg.role,
              imagesBytes: msg.imagesBytes,
              onLog: _logSuggestion,
              prompt: msg.role == _Role.assistant ? _promptBefore(i) : null,
            ),
          );
        },
      ),
    );
  }

  /// The user's question just before the reply at [index], for a report.
  String? _promptBefore(int index) {
    for (var j = index - 1; j >= 0; j--) {
      final m = _messages[j];
      if (m.role == _Role.user) return m.text;
    }
    return null;
  }

  Widget _buildImagePreview() {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      height: 92,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.md, KSpacing.lg, KSpacing.xs),
        itemCount: _pendingImages.length,
        itemBuilder: (context, index) {
          final bytes = _pendingImages[index];
          return Padding(
            padding: const EdgeInsets.only(right: KSpacing.sm),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: KRadius.md,
                    border: Border.all(color: _hairline()),
                  ),
                  child: ClipRRect(
                    borderRadius: KRadius.md,
                    child: Image.memory(
                      bytes,
                      width: 72,
                      height: 72,
                      cacheWidth: (72 * dpr).round(),
                      fit: BoxFit.cover,
                      semanticLabel: 'Attached photo ${index + 1}',
                    ),
                  ),
                ),
                Positioned(
                  top: -14,
                  right: -14,
                  child: Semantics(
                    button: true,
                    label: 'Remove photo ${index + 1}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        KHaptics.select();
                        setState(() {
                          _pendingImages.removeAt(index);
                        });
                      },
                      child: SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              color: KColor.ink,
                              shape: BoxShape.circle,
                              border: Border.all(color: KColor.bg, width: 1.5),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              color: KColor.onInk,
                              size: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// "Using ChatGPT plan" chip, or the fallback notice, above the composer.
  Widget _buildPlanStrip() {
    final notice = _planNotice;
    final onPlan = notice == null &&
        (_planStatus?.isConnected ?? false) &&
        (_planStatus?.usesChatGptPlan ?? false);
    final Widget child;
    if (notice != null) {
      child = Padding(
        key: ValueKey('plan_notice_$notice'),
        padding: const EdgeInsets.only(bottom: KSpacing.sm),
        child: _PlanNotice(reason: notice, onManageUsage: _openManageUsage),
      );
    } else if (onPlan) {
      child = Padding(
        key: const ValueKey('plan_chip'),
        padding: const EdgeInsets.only(bottom: KSpacing.xs),
        child: _PlanChip(onManageUsage: _openManageUsage),
      );
    } else {
      child = const SizedBox(key: ValueKey('plan_none'), width: double.infinity, height: KSpacing.xs);
    }
    return AnimatedSize(
      duration: KMotion.of(context, KMotion.standard),
      curve: KMotion.emphasizedCurve,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: KMotion.of(context, KMotion.standard),
        switchInCurve: KMotion.decelerate,
        switchOutCurve: KMotion.accelerate,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.bottomCenter,
          children: [...previous, ?current],
        ),
        child: child,
      ),
    );
  }

  Widget _buildInputBar() {
    final disabled = _loading || _isStreaming;
    // On the tab, the padding already carries the floating dock and the
    // keyboard arrives as a view inset (the tab's Scaffold doesn't resize).
    final bottom = MediaQuery.paddingOf(context).bottom +
        (widget.embedded ? MediaQuery.viewInsetsOf(context).bottom : 0);
    return Padding(
      padding: EdgeInsets.fromLTRB(KSpacing.md, KSpacing.xs, KSpacing.md, bottom + KSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPlanStrip(),
          AnimatedContainer(
            duration: KMotion.of(context, KMotion.quick),
            curve: KMotion.emphasizedCurve,
            decoration: BoxDecoration(
              borderRadius: KRadius.xl,
              border: Border.all(
                color: _isInputFocused
                    ? KColor.fg.withValues(alpha: KColor.isDark ? 0.32 : 0.38)
                    : Colors.transparent,
                width: 1.2,
              ),
              boxShadow: KShadow.card,
            ),
            child: KGlass(
              borderRadius: KRadius.xl,
              tint: KColor.surface.withValues(alpha: KColor.isDark ? 0.84 : 0.92),
              padding: const EdgeInsets.all(KSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedOpacity(
                    duration: KMotion.of(context, KMotion.quick),
                    opacity: disabled ? 0.4 : 1.0,
                    child: _IconBtn(
                      icon: Icons.add_photo_alternate_rounded,
                      color: _pendingImages.isNotEmpty ? KColor.textPrimary : KColor.textSecondary,
                      semanticLabel: 'Attach photo',
                      onTap: disabled ? () {} : _pickImage,
                    ),
                  ),
                  const SizedBox(width: KSpacing.xs),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: TextField(
                        controller: _controller,
                        focusNode: _inputFocusNode,
                        enabled: !disabled,
                        autofocus: !widget.embedded,
                        cursorColor: KColor.ink,
                        style: KText.body.copyWith(
                          color: disabled ? KColor.textDisabled : KColor.textPrimary,
                          fontSize: 15,
                          height: 1.45,
                        ),
                        maxLines:   null,
                        minLines:   1,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText:       'Ask Kyno anything',
                          hintStyle:      KText.body.copyWith(color: KColor.textMuted),
                          border:         InputBorder.none,
                          enabledBorder:  InputBorder.none,
                          focusedBorder:  InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled:         false,
                          contentPadding: const EdgeInsets.symmetric(horizontal: KSpacing.sm, vertical: 11),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: KSpacing.xs),
                  _SendBtn(
                    loading: disabled,
                    text: _controller,
                    hasImages: _pendingImages.isNotEmpty,
                    canSend: () => _canSend,
                    onTap: _send,
                  ),
                ],
              ),
            ),
          ),
          // Always there, never in the way: one quiet line under the box.
          const SizedBox(height: 6),
          Semantics(
            label: _kDisclaimer,
            excludeSemantics: true,
            child: Text(
              _kDisclaimer,
              textAlign: TextAlign.center,
              style: KText.caption.copyWith(color: KColor.textMuted, fontSize: 11.5, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

const _kDisclaimer = 'Kyno can be wrong. Not medical advice.';

// ─── _Entrance — rise + fade a row in, decided once at mount ─────────────────
// A short 8 px rise and fade (220 ms, ease-out): quick enough to feel like
// the message just landed. Reduced motion: it is simply there.

class _Entrance extends StatefulWidget {
  final Widget child;
  final bool animate;
  final bool fromUser;
  const _Entrance({
    super.key,
    required this.child,
    required this.animate,
    this.fromUser = false,
  });

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> {
  // Fixed at mount: later rebuilds (streaming tokens, focus changes) keep the
  // same tree shape and never replay the entrance.
  late final bool _animate = widget.animate;

  @override
  Widget build(BuildContext context) {
    if (!_animate) return widget.child;
    return KReveal(
      rise: 8,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: widget.child,
    );
  }
}

// ─── Surfaces ─────────────────────────────────────────────────────────────────

/// Hairline that follows the active theme (white-on-black on Carbon, warm
/// border on Paper). A function, never cached.
Color _hairline() =>
    KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border;

const _kUserBubbleRadius = BorderRadius.only(
  topLeft:     Radius.circular(18),
  topRight:    Radius.circular(18),
  bottomLeft:  Radius.circular(18),
  bottomRight: Radius.circular(4),
);

void _copyToClipboard(BuildContext context, String textToCopy) {
  if (textToCopy.isEmpty) return;
  Clipboard.setData(ClipboardData(text: textToCopy));
  kHapticMedium();
  _showToast(KToaster.of(context), 'Copied.', success: true);
}

// ─── Reply actions: Copy / Report this reply ──────────────────────────────────
// Every Kyno reply can be reported in the app (Google Play generative AI
// policy). Long-press or the options button opens this sheet.

Future<void> _showReplyActions(BuildContext context, {required String text, String? prompt}) async {
  if (text.isEmpty) return;
  KHaptics.select();
  final action = await showKSheet<String>(
    context: context,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: KSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const KSheetHeader("Kyno's reply"),
            _SheetOption(
              icon: Icons.copy_rounded,
              label: 'Copy',
              onTap: () => Navigator.of(sheet).pop('copy'),
            ),
            _SheetOption(
              icon: Icons.flag_outlined,
              label: 'Report this reply',
              onTap: () => Navigator.of(sheet).pop('report'),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  if (action == 'copy') _copyToClipboard(context, text);
  if (action == 'report') {
    await showKSheet<void>(
      context: context,
      builder: (_) => _ReportReplySheet(message: text, prompt: prompt),
    );
  }
}

class _ReportReplySheet extends StatefulWidget {
  const _ReportReplySheet({required this.message, this.prompt});
  final String message;
  final String? prompt;

  @override
  State<_ReportReplySheet> createState() => _ReportReplySheetState();
}

class _ReportReplySheetState extends State<_ReportReplySheet> {
  final _note = TextEditingController();
  KynoReportReason? _reason;
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    final toaster = KToaster.of(context);
    final navigator = Navigator.of(context);
    setState(() => _sending = true);
    try {
      await KynoReportService.instance.report(
        reason: reason,
        message: widget.message,
        prompt: widget.prompt,
        note: _note.text,
      );
      AnalyticsService.instance.track('kyno_reply_reported', {'reason': reason.code});
      KHaptics.success();
      if (navigator.mounted) navigator.pop();
      _showToast(toaster, "Thanks. Kyno's team will review it.", success: true);
    } catch (e) {
      debugPrint('[AI_COACH_SCREEN] Report failed: $e');
      if (mounted) setState(() => _sending = false);
      final signedOut = e.toString().contains('not authenticated');
      _showToast(
        toaster,
        signedOut
            ? 'Sign in again to send a report.'
            : "Couldn't send the report. Check your connection and try again.",
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: KSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KSheetHeader(
                'Report this reply',
                subtitle: 'Tell us what went wrong. The reply and your question are sent with it.',
              ),
              const SizedBox(height: KSpacing.sm),
              for (final r in KynoReportReason.values)
                _ReasonRow(
                  label: r.label,
                  selected: _reason == r,
                  onTap: _sending
                      ? null
                      : () {
                          KHaptics.select();
                          setState(() => _reason = r);
                        },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, 0),
                child: TextField(
                  controller: _note,
                  enabled: !_sending,
                  maxLength: KynoReportService.maxNoteLength,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  style: KText.body.copyWith(fontSize: 15, height: 1.4),
                  decoration: InputDecoration(
                    hintText: 'Add a note (optional)',
                    hintStyle: KText.body.copyWith(color: KColor.textMuted),
                    filled: true,
                    fillColor: KColor.card,
                    contentPadding: const EdgeInsets.all(KSpacing.md),
                    border: OutlineInputBorder(borderRadius: KRadius.md, borderSide: BorderSide(color: _hairline())),
                    enabledBorder: OutlineInputBorder(borderRadius: KRadius.md, borderSide: BorderSide(color: _hairline())),
                    focusedBorder: OutlineInputBorder(borderRadius: KRadius.md, borderSide: BorderSide(color: KColor.textSecondary)),
                    disabledBorder: OutlineInputBorder(borderRadius: KRadius.md, borderSide: BorderSide(color: _hairline())),
                  ),
                ),
              ),
              const SizedBox(height: KSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                child: KButton(
                  label: 'Send report',
                  loading: _sending,
                  onTap: _reason == null ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One reason in the report sheet: a radio mark (shape, not colour, says
/// which is picked) and the label.
class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpacing.p, vertical: KSpacing.sm),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: selected ? KColor.textPrimary : KColor.textMuted,
                ),
                const SizedBox(width: KSpacing.md),
                Expanded(child: Text(label, style: KText.bodyMedium)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// HTTP status of a failed coach reply. Reads an `int statusCode` when the
/// service throws a typed error, else the `ai-meal-coach <status>:` prefix
/// the service throws today.
int? _aiCoachStatusOf(Object e) {
  try {
    final code = (e as dynamic).statusCode;
    if (code is int) return code;
  } catch (_) {}
  final m = RegExp(r'ai-meal-coach (\d{3})').firstMatch(e.toString());
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// Calm copy for a failed coach reply (429 rate limits, 413 too long or too
/// many photos, auth, network). Never raw exception text.
@visibleForTesting
String aiCoachFriendlyError(Object e) {
  final raw = e.toString().toLowerCase();
  final status = _aiCoachStatusOf(e);
  if (status == 429) {
    // The per-minute limit wins when the body names both windows.
    final daily = !raw.contains('minute') && raw.contains('day');
    return daily
        ? "You've reached today's limit with Kyno. It resets tomorrow."
        : "That's a lot of questions in a minute. Give it a moment, then send again.";
  }
  if (status == 413) {
    if (raw.contains('image') || raw.contains('photo')) {
      return "That's more photos than Kyno can take at once. Remove a few, or use smaller ones.";
    }
    return 'That message is too long for Kyno. Try a shorter one.';
  }
  if (raw.contains('not authenticated')) {
    return 'You\'re signed out. Sign in again to chat with Kyno.';
  }
  if (raw.contains('socket') ||
      raw.contains('clientexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('connection')) {
    return 'Couldn\'t reach Kyno. Check your connection and try again.';
  }
  return 'That didn\'t go through. Try again in a moment.';
}

/// Most messages sent to the AI as context with each question.
const maxHistoryMessages = 20;

/// The latest [max] entries of [thread], in their original order.
@visibleForTesting
List<T> recentHistory<T>(List<T> thread, {int max = maxHistoryMessages}) =>
    thread.length <= max ? thread : thread.sublist(thread.length - max);

/// The screen's toasts: the shared KToast, a shorter stay for one-liners.
void _showToast(KToaster toaster, String message, {bool success = false, bool error = false}) {
  toaster.show(
    message,
    kind: success
        ? KToastKind.success
        : error
            ? KToastKind.error
            : KToastKind.info,
    duration: const Duration(seconds: 3),
  );
}

// ─── Chat bubble ──────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final _ChatMessage? message;
  final _Role role;
  final List<Uint8List>? imagesBytes;
  final ValueChanged<String>? onLog;

  /// The user's question this reply answers, sent along with a report.
  final String? prompt;

  const _ChatBubble({
    this.message,
    required this.role,
    this.imagesBytes,
    this.onLog,
    this.prompt,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = role == _Role.user;
    final text = message?.text ?? '';

    if (isUser) {
      final images = imagesBytes;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      return Padding(
        padding: const EdgeInsets.only(left: 48, top: 4, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (images != null && images.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: text.isEmpty ? 0 : 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    for (final bytes in images)
                      ClipRRect(
                        borderRadius: KRadius.md,
                        child: Image.memory(
                          bytes,
                          width: images.length == 1 ? 180 : 120,
                          height: images.length == 1 ? 180 : 120,
                          cacheWidth: ((images.length == 1 ? 180 : 120) * dpr).round(),
                          fit: BoxFit.cover,
                          semanticLabel: 'Photo you sent',
                        ),
                      ),
                  ],
                ),
              ),
            if (text.isNotEmpty || images == null || images.isEmpty)
              GestureDetector(
                // Long-press copies the message text to clipboard
                onLongPress: () => _copyToClipboard(context, text),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg, vertical: KSpacing.md),
                  decoration: BoxDecoration(
                    borderRadius: _kUserBubbleRadius,
                    color: KColor.ink,
                  ),
                  child: Text(
                    text,
                    style: KText.bodyMedium.copyWith(color: KColor.onInk, fontSize: 15, height: 1.45),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Kyno writes on the page: a byline, then the answer as prose. The
    // options button below a reply takes up most of the gap after it.
    return Padding(
      padding: EdgeInsets.only(right: KSpacing.xs, top: 8, bottom: text.isEmpty ? KSpacing.xl : KSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KynoByline(),
          const SizedBox(height: KSpacing.sm),
          GestureDetector(
            // Long-press opens Copy / Report this reply
            onLongPress: () => _showReplyActions(context, text: text, prompt: prompt),
            child: _MarkdownText(text),
          ),
          if (message?.fuel != null && onLog != null)
            _FuelPlanCard(plan: message!.fuel!, onLog: onLog!),
          // The same actions, findable without knowing about long-press.
          if (text.isNotEmpty)
            Transform.translate(
              // Line the dots up with the text, not the 48 dp target's edge.
              offset: const Offset(-15, 0),
              child: IconButton(
                tooltip: 'Reply options',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                ),
                onPressed: () => _showReplyActions(context, text: text, prompt: prompt),
                icon: Icon(Icons.more_horiz_rounded, size: 18, color: KColor.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Kyno tail: typing dots → live streaming bubble ──────────────────────────

class _KynoTail extends StatelessWidget {
  final bool streaming;
  final ValueListenable<String> textListenable;
  final bool lookingAtPhoto;
  const _KynoTail({
    required this.streaming,
    required this.textListenable,
    this.lookingAtPhoto = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: KSpacing.xs, top: 8, bottom: KSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KynoByline(thinking: !streaming),
          const SizedBox(height: KSpacing.sm),
          GestureDetector(
              // Long-press copies the message text to clipboard
              onLongPress: () => _copyToClipboard(context, textListenable.value),
              child: SizedBox(
                width: double.infinity,
                child: AnimatedSize(
                  duration: KMotion.of(context, KMotion.quick),
                  curve: KMotion.emphasizedCurve,
                  alignment: AlignmentDirectional.topStart,
                  child: AnimatedSwitcher(
                    duration: KMotion.of(context, KMotion.quick),
                    switchInCurve: KMotion.decelerate,
                    switchOutCurve: KMotion.accelerate,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: AlignmentDirectional.topStart,
                      children: [...previous, ?current],
                    ),
                    child: streaming
                        ? ValueListenableBuilder<String>(
                            key: const ValueKey('streaming'),
                            valueListenable: textListenable,
                            builder: (context, val, _) => _StreamingMarkdown(text: val),
                          )
                        : Padding(
                            key: const ValueKey('typing'),
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Semantics(
                              label: 'Kyno is thinking',
                              liveRegion: true,
                              excludeSemantics: true,
                              child: Row(
                                children: [
                                  // Three dots breathing in turn: opacity
                                  // only, no bounce.
                                  KTypingDots(color: KColor.textSecondary),
                                  const SizedBox(width: KSpacing.md),
                                  Flexible(
                                    child: RepaintBoundary(
                                      child: KLoadingLabel(
                                        messages: lookingAtPhoto
                                            ? const ['Looking at your photo…', 'Crunching your macros…', 'Checking your targets…']
                                            : const ['Reading your meals…', 'Checking your targets…', 'Crunching your macros…'],
                                        textAlign: TextAlign.start,
                                        style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 15),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ),
              ),
          ),
        ],
      ),
    );
  }
}

// ─── Markdown renderer ────────────────────────────────────────────────────────
// Geist throughout, comfortable list rhythm, quiet monochrome bullets, inline
// code on a neutral fg-tinted pill with tabular figures. Every colour is read
// from the active palette, so it reads on Carbon and on Paper alike.

MarkdownStyleSheet get _kMarkdownSheet => () {
  final p = KText.body.copyWith(fontSize: 15, height: 1.58);
  final codeFill = Color.alphaBlend(
    KColor.fg.withValues(alpha: KColor.isDark ? 0.09 : 0.06),
    KColor.card,
  );
  return MarkdownStyleSheet(
    p: p,
    pPadding: EdgeInsets.zero,
    a: p.copyWith(
      color: KColor.textPrimary,
      decoration: TextDecoration.underline,
      decorationColor: KColor.textMuted,
    ),
    strong: p.copyWith(fontWeight: FontWeight.w700, color: KColor.textPrimary),
    em: p.copyWith(fontStyle: FontStyle.italic),
    del: p.copyWith(decoration: TextDecoration.lineThrough, color: KColor.textMuted),
    code: KText.numSmall.copyWith(
      color: KColor.textPrimary,
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      height: 1.5,
      backgroundColor: codeFill,
    ),
    codeblockPadding: const EdgeInsets.all(KSpacing.md),
    codeblockDecoration: BoxDecoration(
      color: codeFill,
      borderRadius: KRadius.sm,
      border: Border.all(color: _hairline()),
    ),
    h1: KText.h1.copyWith(fontSize: 20),
    h1Padding: const EdgeInsets.only(top: 6, bottom: 2),
    h2: KText.h2.copyWith(fontSize: 17.5),
    h2Padding: const EdgeInsets.only(top: 6, bottom: 2),
    h3: KText.h2.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600),
    h3Padding: const EdgeInsets.only(top: 4),
    h4: KText.h3,
    h5: KText.h3.copyWith(fontSize: 14),
    h6: KText.caption.copyWith(color: KColor.textSecondary, fontWeight: FontWeight.w600),
    blockSpacing: 10,
    listIndent: 22,
    listBullet: p.copyWith(color: KColor.textMuted, fontWeight: FontWeight.w700),
    listBulletPadding: const EdgeInsets.only(right: 6),
    blockquote: p.copyWith(color: KColor.textSecondary, fontStyle: FontStyle.italic),
    blockquotePadding: const EdgeInsets.fromLTRB(KSpacing.md, KSpacing.sm, KSpacing.sm, KSpacing.sm),
    blockquoteDecoration: BoxDecoration(
      color: KColor.fg.withValues(alpha: KColor.isDark ? 0.04 : 0.035),
      border: Border(
        left: BorderSide(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.3 : 0.25), width: 2),
      ),
    ),
    tableHead: KText.caption.copyWith(color: KColor.textPrimary, fontWeight: FontWeight.w700),
    tableBody: KText.caption.copyWith(fontWeight: FontWeight.w400),
    tableBorder: TableBorder.all(color: _hairline(), width: 1),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: KSpacing.sm),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: _hairline())),
    ),
  );
}();

class _MarkdownText extends StatelessWidget {
  final String text;
  const _MarkdownText(this.text);

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: noEmDash(text),
      styleSheet: _kMarkdownSheet,
    );
  }
}


// ─── Quick chip ───────────────────────────────────────────────────────────────

class _QuickChip extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // A ruled row: the question in full, an arrow that says "ask this".
    return Pressable(
      onTap: () { kHapticSelect(); onTap(); },
      borderRadius: KRadius.sm,
      scale: 0.98,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: _hairline())),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: KText.bodyMedium.copyWith(fontSize: 15.5, height: 1.35),
              ),
            ),
            const SizedBox(width: KSpacing.md),
            KIcon(Icons.arrow_forward_rounded, size: KIcons.sm, color: KColor.textMuted),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet option ─────────────────────────────────────────────────────────────

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SheetOption({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: KColor.cardHigh,
          borderRadius: KRadius.sm,
          border: Border.all(color: _hairline()),
        ),
        child: Icon(icon, color: KColor.textPrimary, size: 20),
      ),
      title: Text(label, style: KText.bodyMedium),
      onTap: onTap,
    );
  }
}

// ─── Icon button ──────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final String       semanticLabel;
  final VoidCallback onTap;
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      borderRadius: KRadius.pill,
      scale: 0.90,
      semanticLabel: semanticLabel,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: KColor.cardHigh,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 21),
      ),
    );
  }
}

// ─── Send button ──────────────────────────────────────────────────────────────
// Squash on press (Pressable), then a pop + one commit haptic on a real send.

class _SendBtn extends StatefulWidget {
  final bool         loading;
  final ValueListenable<TextEditingValue> text;
  final bool         hasImages;
  final bool Function() canSend;
  final VoidCallback onTap;
  const _SendBtn({
    required this.loading,
    required this.text,
    required this.hasImages,
    required this.canSend,
    required this.onTap,
  });

  @override
  State<_SendBtn> createState() => _SendBtnState();
}

class _SendBtnState extends State<_SendBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: KMotion.standard);
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.16).chain(CurveTween(curve: KMotion.decelerate)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.16, end: 1.0).chain(CurveTween(curve: KMotion.spring)),
      weight: 65,
    ),
  ]).animate(_pop);

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.canSend()) {
      KHaptics.commit();
      final d = KMotion.of(context, KMotion.standard);
      if (d != Duration.zero) {
        _pop
          ..duration = d
          ..forward(from: 0);
      }
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: widget.loading ? null : _handleTap,
      borderRadius: KRadius.pill,
      scale: 0.86,
      semanticLabel: widget.loading ? 'Kyno is replying' : 'Send message',
      child: ScaleTransition(
        scale: _scale,
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.text,
          builder: (context, value, _) {
            final ready = !widget.loading &&
                (value.text.trim().isNotEmpty || widget.hasImages);
            // Disabled to enabled as one morph: fill, arrow colour and a
            // small settle of the arrow move on the same eased value.
            // Keystrokes that keep the same state don't restart it.
            final idleArrow = KColor.textMuted.withValues(alpha: widget.loading ? 0.5 : 1);
            return TweenAnimationBuilder<double>(
              tween: Tween(end: ready ? 1.0 : 0.0),
              duration: KMotion.of(context, const Duration(milliseconds: 220)),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(KColor.cardHigh, KColor.ink, t),
                ),
                child: SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: Transform.scale(
                      scale: 0.88 + 0.12 * t,
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        color: Color.lerp(idleArrow, KColor.onInk, t),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Streaming markdown: MarkdownText + blinking cursor ───────────────────────
// The markdown only rebuilds when the text changes or the cursor flips (not
// every animation frame). Blink is gated; a static cursor shows otherwise.

class _StreamingMarkdown extends StatefulWidget {
  final String text;
  const _StreamingMarkdown({required this.text});

  @override
  State<_StreamingMarkdown> createState() => _StreamingMarkdownState();
}

class _StreamingMarkdownState extends State<_StreamingMarkdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorCtrl = AnimationController(
    vsync: this, duration: KMotion.emphasized,
  )..addListener(_onTick);
  bool _showBar = true;

  void _onTick() {
    final next = _cursorCtrl.value > 0.5;
    if (next != _showBar) setState(() => _showBar = next);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final allowed = KMotion.ambientAllowed(context);
    if (allowed && !_cursorCtrl.isAnimating) _cursorCtrl.repeat(reverse: true);
    if (!allowed && _cursorCtrl.isAnimating) {
      _cursorCtrl.stop();
      _showBar = true;
    }
  }

  @override
  void dispose() { _cursorCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return _MarkdownText(widget.text + (_showBar ? ' ▍' : '  '));
  }
}

// ─── ChatGPT plan status ──────────────────────────────────────────────────────
// Quiet, monochrome: a small chip while the user's ChatGPT plan answers, and a
// calm one-line notice (Manage usage as the action) when the server fell back
// to the standard model. Colour isn't the signal: icon + words carry it.

String _planNoticeText(String reason) => switch (reason) {
      'usage_limit' =>
        'Your ChatGPT limit\'s tapped out, so Kyno\'s using the standard model for now.',
      'not_eligible' =>
        'Your ChatGPT plan can\'t be used here, so Kyno\'s using the standard model.',
      'plan_unavailable' =>
        'ChatGPT\'s busy right now, so Kyno\'s using the standard model for now.',
      'expired' || 'token_expired' || 'refresh_failed' =>
        'Your ChatGPT sign-in expired, so Kyno\'s using the standard model for now.',
      _ => 'Couldn\'t reach your ChatGPT plan, so Kyno\'s using the standard model for now.',
    };

IconData _planNoticeIcon(String reason) => switch (reason) {
      'usage_limit' => Icons.hourglass_bottom_rounded,
      'not_eligible' => Icons.block_rounded,
      'expired' || 'token_expired' || 'refresh_failed' => Icons.lock_clock_rounded,
      _ => Icons.info_outline_rounded,
    };

class _ManageUsageLink extends StatelessWidget {
  const _ManageUsageLink({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        KHaptics.select();
        onTap();
      },
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: KSpacing.sm),
        foregroundColor: KColor.textPrimary,
      ),
      child: Semantics(
        link: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Manage usage',
              style: KText.caption.copyWith(
                color: KColor.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.north_east_rounded, size: 13, color: KColor.textPrimary),
          ],
        ),
      ),
    );
  }
}

class _PlanChip extends StatelessWidget {
  const _PlanChip({required this.onManageUsage});
  final VoidCallback onManageUsage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: KSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: KColor.fg.withValues(alpha: KColor.isDark ? 0.06 : 0.045),
            borderRadius: KRadius.pill,
            border: Border.all(color: _hairline()),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_rounded, size: 13, color: KColor.textSecondary),
              const SizedBox(width: 5),
              Text(
                'Using ChatGPT plan',
                style: KText.caption.copyWith(
                  color: KColor.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        _ManageUsageLink(onTap: onManageUsage),
      ],
    );
  }
}

class _PlanNotice extends StatelessWidget {
  const _PlanNotice({required this.reason, required this.onManageUsage});
  final String reason;
  final VoidCallback onManageUsage;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(KSpacing.md, KSpacing.xs, KSpacing.xs, KSpacing.xs),
        decoration: BoxDecoration(
          color: KColor.card,
          borderRadius: KRadius.md,
          border: Border.all(color: _hairline()),
          boxShadow: KShadow.card,
        ),
        child: Row(
          children: [
            Icon(_planNoticeIcon(reason), size: 16, color: KColor.textSecondary),
            const SizedBox(width: KSpacing.sm),
            Expanded(
              child: Text(
                _planNoticeText(reason),
                style: KText.caption.copyWith(color: KColor.textPrimary, height: 1.35),
              ),
            ),
            const SizedBox(width: KSpacing.xs),
            _ManageUsageLink(onTap: onManageUsage),
          ],
        ),
      ),
    );
  }
}

// ─── Today band ───────────────────────────────────────────────────────────────
// What Kyno is reading from, set as a ruled band: the day type, calories and
// protein left. Colour only on the numbers it describes.

class _TodayBand extends StatelessWidget {
  const _TodayBand({required this.brief});
  final KynoBrief brief;

  @override
  Widget build(BuildContext context) {
    final today = brief.json['today'] as Map<String, dynamic>?;
    if (today == null) return const SizedBox.shrink();
    final remaining = today['remaining'] as Map<String, dynamic>;
    final target = today['target'] as Map<String, dynamic>;
    final kcalLeft = (remaining['kcal'] as num).round();
    final proLeft = (remaining['protein_g'] as num).round();
    final dayType = today['day_type'] as String? ?? '';
    final isRest = dayType.toLowerCase().startsWith('rest');

    Widget stat(String value, String label, Color dot) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: KText.numMedium.copyWith(fontSize: 24, height: 1.1, color: KHeroInk.primary)),
              const SizedBox(height: 4),
              Row(
                children: [
                  KDot(color: dot, size: 7),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KText.caption.copyWith(color: KHeroInk.muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

    // Kyno's lead card: flat surface, calories in the accent, protein in ink.
    return KHeroSurface(
      tone: KTone.kyno,
      radius: KRadius.lg,
      padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.md, KSpacing.lg, KSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isRest ? Icons.bedtime_outlined : Icons.fitness_center_rounded, size: 14, color: KColor.textSecondary),
              const SizedBox(width: 6),
              Text(
                isRest ? 'Today, rest day' : 'Today, $dayType',
                style: KText.caption.copyWith(color: KHeroInk.secondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          Row(
            children: [
              stat(
                kcalLeft >= 0 ? thousands(kcalLeft) : '+${thousands(-kcalLeft)}',
                kcalLeft >= 0 ? 'kcal left of ${thousands((target['kcal'] as num).round())}' : 'kcal over',
                KRingColors.calories.first,
              ),
              const SizedBox(width: KSpacing.md),
              stat('$proLeft g', 'protein left', KRingColors.protein.first),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Check-in card ────────────────────────────────────────────────────────────

class _CheckInCard extends StatelessWidget {
  const _CheckInCard({required this.insight, required this.onAsk, required this.onDismiss});
  final KynoCoachingInsight insight;
  final VoidCallback onAsk;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (insight.severity) {
      KynoInsightSeverity.needsAttention => (KColor.ember, Icons.error_outline_rounded),
      KynoInsightSeverity.coaching => (KColor.textSecondary, Icons.lightbulb_outline_rounded),
      KynoInsightSeverity.progress => (KColor.ink, Icons.trending_up_rounded),
      KynoInsightSeverity.resolved => (KColor.ink, Icons.check_circle_outline_rounded),
    };
    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: KColor.isDark ? 0.07 : 0.05), KColor.card),
        borderRadius: KRadius.lg,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.xs, KSpacing.xs, KSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: KIcons.sm),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Kyno noticed',
                  style: KText.caption.copyWith(color: color, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: () {
                  KHaptics.select();
                  onDismiss();
                },
                icon: Icon(Icons.close_rounded, size: 18, color: KColor.textMuted),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: KSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(insight.title, style: KText.h3.copyWith(fontSize: 17, height: 1.25)),
                const SizedBox(height: 6),
                Text(
                  insight.evidence,
                  style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: KSpacing.sm),
                KTextAction('Ask Kyno why', onTap: onAsk),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Food plan card ───────────────────────────────────────────────────────────
// Under a "what should I eat" answer: ready-made combos and single foods, each
// one tap from the meal screen (which estimates before anything is saved).

class _FuelPlanCard extends StatelessWidget {
  const _FuelPlanCard({required this.plan, required this.onLog});
  final FuelPlan plan;
  final ValueChanged<String> onLog;

  @override
  Widget build(BuildContext context) {
    Widget row({
      required String title,
      required String meta,
      required String logText,
      bool fromLog = false,
    }) {
      return Pressable(
        onTap: () => onLog(logText),
        borderRadius: KRadius.md,
        scale: 0.98,
        semanticLabel: 'Log $title',
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: _hairline()))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: KText.bodyMedium.copyWith(fontSize: 14.5, height: 1.3)),
                    const SizedBox(height: 2),
                    Text(
                      fromLog ? '$meta · from your log' : meta,
                      style: KText.caption.copyWith(color: KColor.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: KColor.ink,
                  borderRadius: KRadius.pill,
                ),
                child: Text('Log', style: KText.caption.copyWith(color: KColor.onInk, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }

    String macro(num kcal, num p) => '${thousands(kcal.round())} kcal · ${p.round()} g protein';

    final picks = [...plan.yours.take(2), ...plan.newIdeas.take(2)];
    return Container(
      margin: const EdgeInsets.only(top: KSpacing.md),
      padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.md, KSpacing.lg, KSpacing.xs),
      decoration: BoxDecoration(
        color: Color.alphaBlend(KColor.ink.withValues(alpha: KColor.isDark ? 0.05 : 0.04), KColor.card),
        borderRadius: KRadius.lg,
        border: Border.all(color: KColor.ink.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_outlined, size: 14, color: KColor.ink),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Fits what you have left',
                  style: KText.caption.copyWith(color: KColor.ink, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(plan.headline, style: KText.body.copyWith(fontSize: 14, color: KColor.textSecondary, height: 1.45)),
          const SizedBox(height: KSpacing.sm),
          for (final c in plan.combos.take(2))
            row(
              title: c.items.map((f) => f.logText).join(' + '),
              meta: macro(c.kcal, c.protein),
              logText: c.items.map((f) => f.logText).join(', '),
              fromLog: c.items.every((f) => f.fromHistory),
            ),
          for (final p in picks)
            row(
              title: p.food.fromHistory ? p.food.name : '${p.food.name}, ${p.food.serving}',
              meta: macro(p.food.kcal, p.food.protein),
              logText: p.food.logText,
              fromLog: p.food.fromHistory,
            ),
        ],
      ),
    );
  }
}
