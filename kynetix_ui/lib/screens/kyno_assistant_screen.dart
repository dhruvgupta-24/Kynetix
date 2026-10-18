import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/kyno_assistant_service.dart';
import '../services/kyno_context_service.dart';
import '../services/kyno_coaching_insight_service.dart';
import '../widgets/kyno_presence.dart';

// ─── Kyno tab ─────────────────────────────────────────────────────────────────
// Tab root inside AppShell: transparent so the kyno aurora shows through, and
// the composer floats above the glass dock (MediaQuery bottom padding already
// carries the dock height) and above the keyboard.
//
// Motion moments (all resolved through KMotion, so reduced motion = end state):
// • Row entrance  — each row (card / message / typing) slides in from its own
//   side exactly once; [_entered] remembers which rows have played so a
//   rebuild or scroll-remount never replays it.
// • Thinking      — Kyno's mark breathes in the header and on the byline
//   while a KLoadingLabel line rotates. Gated by KMotion.
// • Send          — squash on press, pop on commit, KHaptics.commit() once.
// • Chips         — stagger in once on first mount.

class KynoAssistantScreen extends StatefulWidget {
  const KynoAssistantScreen({super.key});

  @override
  State<KynoAssistantScreen> createState() => _KynoAssistantScreenState();
}

class _KynoAssistantScreenState extends State<KynoAssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<KynoChatMessage> _messages = [];
  bool _isLoading = false;

  // Rows that already played their entrance. Identity-based so equal-looking
  // messages never collide; const sentinels for the lead cards.
  final Set<Object> _entered = Set<Object>.identity();
  final Set<String> _enteredChips = {};
  Object _typingToken = Object();
  static const _ctxToken = 'kyno_ctx_card';
  static const _checkInToken = 'kyno_checkin_card';

  @override
  void initState() {
    super.initState();
    _initWelcomeMessage();
  }

  void _initWelcomeMessage() {
    final snapshot = KynoContextService.instance.getSnapshot();
    final greeting = _getGreeting(snapshot.profile.name);

    _messages.add(
      KynoChatMessage(
        id: 'welcome_msg',
        isUser: false,
        text: '$greeting\nI\'m Kyno. I\'ve read your workouts, today\'s sets and your meals, so just ask. No need to explain the backstory.',
        timestamp: DateTime.now(),
        structuredInsights: snapshot.structuredInsights,
      ),
    );
  }

  String _getGreeting(String name) {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning, $name.';
    } else if (hour < 17) {
      return 'Good afternoon, $name.';
    } else {
      return 'Good evening, $name.';
    }
  }

  Future<void> _handleSubmitted(String text) async {
    final query = text.trim();
    if (query.isEmpty || _isLoading) return;

    _controller.clear();
    KHaptics.commit();

    final userMsg = KynoChatMessage(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      isUser: true,
      text: query,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isLoading = true;
      _typingToken = Object();
    });
    _scrollToBottom();

    try {
      final reply = await KynoAssistantService.instance.processQuery(query);
      if (!mounted) return;
      setState(() {
        _messages.add(reply);
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      debugPrint('Kyno query failed: $e');
      // Keep the question so the user can retry without retyping it.
      if (_controller.text.isEmpty) {
        _controller.value = TextEditingValue(
          text: query,
          selection: TextSelection.collapsed(offset: query.length),
        );
      }
      setState(() {
        _messages.add(
          KynoChatMessage(
            id: 'err_${DateTime.now().millisecondsSinceEpoch}',
            isUser: false,
            text: 'Couldn\'t read your logs just now, so no answer yet. '
                'Your question\'s back in the box, so just tap send.',
            timestamp: DateTime.now(),
          ),
        );
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      final d = KMotion.of(context, KMotion.standard);
      if (d == Duration.zero) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(target, duration: d, curve: KMotion.emphasizedCurve);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final snapshot = KynoContextService.instance.getSnapshot();
    final chips = KynoAssistantService.instance.getContextualPromptSuggestions();

    // Inside AppShell the padding already includes the floating dock; when the
    // screen is mounted on its own the keyboard arrives as a view inset.
    final bottomInset =
        MediaQuery.paddingOf(context).bottom + MediaQuery.viewInsetsOf(context).bottom;

    const leadRows = 2; // today card + coaching check-in
    final itemCount = leadRows + _messages.length + (_isLoading ? 1 : 0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _KynoHeader(thinking: _isLoading),

            // Conversation (lead cards scroll away with the chat so the
            // composer always has room, even with the keyboard up).
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(
                    KSpacing.lg, KSpacing.xs, KSpacing.lg, KSpacing.md),
                itemCount: itemCount,
                itemBuilder: (ctx, i) => _buildRow(i, snapshot),
              ),
            ),

            // Dynamic prompt suggestions
            if (chips.isNotEmpty) _buildSuggestionStrip(chips),

            // Floating composer
            Padding(
              padding: EdgeInsets.fromLTRB(
                KSpacing.md,
                KSpacing.sm,
                KSpacing.md,
                bottomInset + KSpacing.md,
              ),
              child: _KynoComposer(
                controller: _controller,
                busy: _isLoading,
                onSubmitted: _handleSubmitted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(int i, KynoContextSnapshot snapshot) {
    if (i == 0) {
      return _entrance(_ctxToken, index: 0, child: Padding(
        padding: const EdgeInsets.only(bottom: KSpacing.md),
        child: _buildTodayContextCard(snapshot),
      ));
    }
    if (i == 1) {
      return _entrance(_checkInToken, index: 1, child: _buildCoachingCheckInCard());
    }
    final m = i - 2;
    if (m < _messages.length) {
      final msg = _messages[m];
      return _entrance(
        msg,
        // The welcome message is part of the first-mount stagger.
        index: m == 0 ? 2 : 0,
        fromUser: msg.isUser,
        child: _buildMessageBubble(msg),
      );
    }
    return _entrance(_typingToken, child: const _TypingRow());
  }

  Widget _entrance(
    Object token, {
    required Widget child,
    int index = 0,
    bool fromUser = false,
  }) {
    return _Entrance(
      key: ObjectKey(token),
      animate: _entered.add(token),
      index: index,
      fromUser: fromUser,
      child: child,
    );
  }

  Widget _buildSuggestionStrip(List<String> chips) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == chips.length - 1 ? 0 : KSpacing.sm),
              child: _Entrance(
                key: ValueKey('chip_${chips[i]}'),
                animate: _enteredChips.add(chips[i]),
                index: i,
                rise: 10,
                child: _SuggestionChip(
                  label: chips[i],
                  onTap: () => _handleSubmitted(chips[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Coaching check-in ──────────────────────────────────────────────────────

  Widget _buildCoachingCheckInCard() {
    final insights = KynoCoachingInsightService.instance.getActiveInsights();
    if (insights.isEmpty) return const SizedBox.shrink();

    final top = insights.first;

    // Colour carries meaning only (attention = amber, progress / resolved =
    // success); coaching notes stay monochrome. Each pairs with an icon + word.
    final (color, icon) = switch (top.severity) {
      KynoInsightSeverity.needsAttention => (KColor.warning, Icons.error_outline_rounded),
      KynoInsightSeverity.coaching => (KColor.textSecondary, Icons.lightbulb_outline_rounded),
      KynoInsightSeverity.progress => (KColor.success, Icons.trending_up_rounded),
      KynoInsightSeverity.resolved => (KColor.success, Icons.check_circle_outline_rounded),
    };

    // A note Kyno left for you: the one genuine object on this screen, so it
    // is the only thing here with a surface. A coloured spine marks severity;
    // the suggestion is set apart by type, not by another box.
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.xxl),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: KColor.card,
          borderRadius: KRadius.md,
          border: Border.all(color: _hairline()),
        ),
        child: ClipRRect(
          borderRadius: KRadius.md,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(child: Container(width: 3, color: color)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        KSpacing.lg, KSpacing.xs, KSpacing.xs, KSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, color: color, size: KIcons.sm),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                top.categoryLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: KText.caption.copyWith(
                                    color: color, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Semantics(
                              button: true,
                              label: 'Dismiss check-in',
                              excludeSemantics: true,
                              child: InkResponse(
                                onTap: () {
                                  KHaptics.select();
                                  setState(() {
                                    KynoCoachingInsightService.instance
                                        .dismissInsight(top.id);
                                  });
                                },
                                radius: 24,
                                child: SizedBox.square(
                                  dimension: 48,
                                  child: Icon(Icons.close_rounded,
                                      size: 18, color: KColor.textMuted),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: KSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(top.title,
                                  style: KText.h3.copyWith(fontSize: 17, height: 1.25)),
                              const SizedBox(height: 6),
                              Text(
                                top.evidence,
                                style: KText.body.copyWith(
                                  color: KColor.textSecondary,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: KSpacing.md),
                              Text.rich(
                                TextSpan(children: [
                                  TextSpan(
                                    text: 'Kyno suggests  ',
                                    style: KText.caption.copyWith(
                                      color: KColor.textMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TextSpan(text: top.recommendation),
                                ]),
                                style: KText.bodyMedium
                                    .copyWith(fontSize: 14, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Today at a glance ──────────────────────────────────────────────────────

  Widget _buildTodayContextCard(KynoContextSnapshot snapshot) {
    final tr = snapshot.training;
    final nu = snapshot.nutrition;

    final workoutLabel = tr.hasWorkoutToday
        ? (tr.todaySplitDayName ?? 'Session')
        : 'Rest day';

    final exercisesCount = tr.hasWorkoutToday
        ? '${plural(tr.exercisesTrainedToday.length, 'exercise')}, '
            '${plural(tr.setsLoggedToday, 'set')}'
        : '${plural(tr.totalCompletedSessions, 'workout')} logged so far';

    final proValue = '${whole(nu.consumedProtein)} of ${whole(nu.targetProtein)} g';
    final calText = '${whole(nu.consumedCalories)} of ${whole(nu.targetCalories)} kcal';

    // Not a card: a ruled band, like the head of a page in a training log.
    // What Kyno is reading from, set in type rather than boxed.
    return Container(
      padding: const EdgeInsets.only(top: KSpacing.md, bottom: KSpacing.lg),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: KColor.textPrimary, width: 1.5),
          bottom: BorderSide(color: _hairline()),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Today',
                    style: KText.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Text(
                'From your logs',
                style: KText.caption.copyWith(color: KColor.textMuted),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _GlanceStat(
                    accent: KColor.violet,
                    eyebrow: 'Training',
                    value: workoutLabel,
                    subtitle: exercisesCount,
                  ),
                ),
                VerticalDivider(width: KSpacing.xxl, thickness: 1, color: _hairline()),
                Expanded(
                  child: _GlanceStat(
                    accent: KColor.protein,
                    eyebrow: 'Protein',
                    value: proValue,
                    numeric: true,
                    subtitle: calText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Messages ───────────────────────────────────────────────────────────────

  Widget _buildMessageBubble(KynoChatMessage msg) {
    if (msg.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: KSpacing.xl, left: 56),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: _UserBubble(text: msg.text),
        ),
      );
    }

    // Kyno writes on the page, not in a bubble: a byline, the answer set as
    // prose, then its working shown as a ruled list underneath.
    final insights = msg.structuredInsights;
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.xxl, right: KSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KynoByline(),
          const SizedBox(height: KSpacing.sm),
          if (msg.text.isNotEmpty)
            Text(
              msg.text,
              style: KText.body.copyWith(fontSize: 16, height: 1.55),
            ),
          if (insights != null && insights.isNotEmpty) ...[
            const SizedBox(height: KSpacing.md),
            for (final insight in insights) _InsightEntry(insight: insight),
          ],
        ],
      ),
    );
  }
}

/// One piece of Kyno's working. Provenance is the point: what Kyno read from
/// your logs, what it calculated, what it is estimating and what it suggests.
/// Each is a ruled entry with a provenance line, not a nested box. Estimates
/// are amber (uncertain); a suggestion carries an ink spine, since it is the
/// one thing you might act on.
class _InsightEntry extends StatelessWidget {
  const _InsightEntry({required this.insight});
  final KynoInsightItem insight;

  @override
  Widget build(BuildContext context) {
    final (label, labelColor, icon) = switch (insight.type) {
      KynoInformationType.fact => (
          'From your logs',
          KColor.textMuted,
          Icons.check_rounded
        ),
      KynoInformationType.calculation => (
          'Calculated',
          KColor.textMuted,
          Icons.functions_rounded
        ),
      KynoInformationType.inference => (
          'Kyno\'s estimate',
          KColor.warning,
          Icons.blur_on_rounded
        ),
      KynoInformationType.recommendation => (
          'Suggestion',
          KColor.textPrimary,
          Icons.arrow_forward_rounded
        ),
      KynoInformationType.unknown => (
          'Not enough data',
          KColor.textMuted,
          Icons.remove_rounded
        ),
    };
    final isSuggestion = insight.type == KynoInformationType.recommendation;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: labelColor),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: KText.caption.copyWith(
                  color: labelColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(insight.title, style: KText.h3.copyWith(fontSize: 15, height: 1.3)),
        const SizedBox(height: 4),
        Text(
          insight.detail,
          style: KText.body.copyWith(
            color: isSuggestion ? KColor.textPrimary : KColor.textSecondary,
            fontSize: 14,
            height: 1.55,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: KSpacing.md + 2),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _hairline())),
      ),
      child: isSuggestion
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: KColor.ink,
                        borderRadius: KRadius.pill,
                      ),
                    ),
                  ),
                  const SizedBox(width: KSpacing.md),
                  Expanded(child: body),
                ],
              ),
            )
          : body,
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _KynoHeader extends StatelessWidget {
  const _KynoHeader({required this.thinking});
  final bool thinking;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, KSpacing.md),
      child: Row(
        children: [
          KynoBreathingMark(size: 34, alive: thinking),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Kyno', style: KText.h1),
                ),
                AnimatedSwitcher(
                  duration: KMotion.of(context, KMotion.quick),
                  switchInCurve: KMotion.decelerate,
                  switchOutCurve: KMotion.accelerate,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [...previous, ?current],
                  ),
                  child: Text(
                    thinking ? 'Reading your logs…' : 'Answers from your training and meals',
                    key: ValueKey(thinking),
                    style: KText.caption.copyWith(
                      color: thinking ? KColor.textPrimary : KColor.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Entrance ─────────────────────────────────────────────────────────────────
// Decides ONCE (at mount) whether to play; later rebuilds — streaming text,
// setState elsewhere — never change the tree shape or replay it.

class _Entrance extends StatefulWidget {
  const _Entrance({
    super.key,
    required this.animate,
    required this.child,
    this.index = 0,
    this.fromUser = false,
    this.rise = 14,
  });

  final bool animate;
  final Widget child;
  final int index;
  final bool fromUser;
  final double rise;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> {
  late final bool _animate = widget.animate;

  @override
  Widget build(BuildContext context) {
    if (!_animate) return widget.child;
    return KReveal(
      index: widget.index,
      rise: widget.rise,
      slideX: widget.fromUser ? 14 : -10,
      fromScale: 0.97,
      child: widget.child,
    );
  }
}

// ─── Surfaces ─────────────────────────────────────────────────────────────────

/// Hairline for in-list surfaces: white-on-black on Carbon, warm border on
/// Paper. A function, never a cached value, so it follows the active theme.
Color _hairline() =>
    KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border;

/// One half of the "Today" band: a meaning-coloured dot and eyebrow, a large
/// value and a quiet subtitle. Colour is always paired with a word.
class _GlanceStat extends StatelessWidget {
  const _GlanceStat({
    required this.accent,
    required this.eyebrow,
    required this.value,
    required this.subtitle,
    this.numeric = false,
  });
  final Color accent;
  final String eyebrow;
  final String value;
  final String subtitle;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KDot(color: accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                eyebrow,
                style: KText.caption.copyWith(color: KColor.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 2,
          style: numeric
              ? KText.numMedium.copyWith(fontSize: 20)
              : KText.h2.copyWith(fontSize: 19),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: KText.caption.copyWith(
            color: KColor.textMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// The user's own words: a solid ink bubble (warm white on Carbon, near-black
/// on Paper) with onInk text.
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg, vertical: KSpacing.md),
      decoration: BoxDecoration(
        color: KColor.ink,
        borderRadius: const BorderRadiusDirectional.only(
          topStart: Radius.circular(18),
          topEnd: Radius.circular(18),
          bottomStart: Radius.circular(18),
          bottomEnd: Radius.circular(4),
        ).resolve(Directionality.of(context)),
      ),
      child: Text(
        text,
        style: KText.bodyMedium.copyWith(color: KColor.onInk, fontSize: 15, height: 1.45),
      ),
    );
  }
}

// ─── Typing ───────────────────────────────────────────────────────────────────

class _TypingRow extends StatelessWidget {
  const _TypingRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.xxl, right: KSpacing.lg),
      child: Semantics(
        liveRegion: true,
        label: 'Kyno is thinking',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const KynoByline(thinking: true),
            const SizedBox(height: KSpacing.sm),
            KLoadingLabel(
              messages: const [
                'Checking your workouts…',
                'Reading your meals…',
                'Pulling your history…',
              ],
              textAlign: TextAlign.start,
              style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Suggestion chip ──────────────────────────────────────────────────────────

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      borderRadius: KRadius.pill,
      semanticLabel: 'Ask Kyno: $label',
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: KSpacing.lg),
        decoration: BoxDecoration(
          borderRadius: KRadius.pill,
          border: Border.all(
            color: KColor.fg.withValues(alpha: KColor.isDark ? 0.16 : 0.14),
          ),
        ),
        child: Text(
          label,
          style: KText.bodyMedium.copyWith(fontSize: 14),
        ),
      ),
    );
  }
}

// ─── Composer ─────────────────────────────────────────────────────────────────

class _KynoComposer extends StatelessWidget {
  const _KynoComposer({
    required this.controller,
    required this.busy,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: KRadius.pill,
        boxShadow: KShadow.card,
      ),
      child: KGlass(
        borderRadius: KRadius.pill,
        tint: KColor.surface.withValues(alpha: KColor.isDark ? 0.82 : 0.9),
        padding: const EdgeInsets.fromLTRB(KSpacing.xl, KSpacing.xs, KSpacing.xs, KSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                style: KText.body.copyWith(height: 1.35),
                cursorColor: KColor.ink,
                decoration: InputDecoration(
                  hintText: 'Ask about your training or meals',
                  hintStyle: KText.body.copyWith(color: KColor.textMuted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onSubmitted: onSubmitted,
              ),
            ),
            const SizedBox(width: KSpacing.sm),
            _SendButton(
              text: controller,
              busy: busy,
              onSend: () => onSubmitted(controller.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// Send: squashes on finger-down (Pressable), then pops on a committed send.
/// The commit haptic fires in the submit handler, once.
class _SendButton extends StatefulWidget {
  const _SendButton({required this.text, required this.busy, required this.onSend});
  final ValueListenable<TextEditingValue> text;
  final bool busy;
  final VoidCallback onSend;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> with SingleTickerProviderStateMixin {
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
    final willSend = widget.text.value.text.trim().isNotEmpty && !widget.busy;
    widget.onSend();
    if (!willSend) return;
    final d = KMotion.of(context, KMotion.standard);
    if (d == Duration.zero) return;
    _pop
      ..duration = d
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: _handleTap,
      scale: 0.86,
      borderRadius: KRadius.pill,
      semanticLabel: 'Send message',
      child: ScaleTransition(
        scale: _scale,
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.text,
          builder: (context, value, _) {
            final ready = value.text.trim().isNotEmpty && !widget.busy;
            return AnimatedContainer(
              duration: KMotion.of(context, KMotion.quick),
              curve: KMotion.emphasizedCurve,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ready ? KColor.ink : KColor.cardHigh,
              ),
              child: Icon(
                Icons.arrow_upward_rounded,
                color: ready ? KColor.onInk : KColor.textMuted,
                size: 20,
              ),
            );
          },
        ),
      ),
    );
  }
}
