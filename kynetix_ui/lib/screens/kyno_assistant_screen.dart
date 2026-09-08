import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../services/kyno_assistant_service.dart';
import '../services/kyno_context_service.dart';

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
        text: '$greeting\nI am Kyno, your personal fitness intelligence layer. I know your real training history, today\'s sets, and logged meals so you never have to explain your background.',
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
    HapticFeedback.lightImpact();

    final userMsg = KynoChatMessage(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      isUser: true,
      text: query,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isLoading = true;
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
      setState(() {
        _messages.add(
          KynoChatMessage(
            id: 'err_${DateTime.now().millisecondsSinceEpoch}',
            isUser: false,
            text: 'I ran into an issue retrieving your context: $e',
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
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = KynoContextService.instance.getSnapshot();
    final chips = KynoAssistantService.instance.getContextualPromptSuggestions();

    return Scaffold(
      backgroundColor: KColor.bg,
      appBar: AppBar(
        backgroundColor: KColor.bg,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: KColor.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: KColor.green,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KYNO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  'Your personal fitness assistant',
                  style: TextStyle(
                    color: KColor.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Live Daily Context Pill / Snapshot Summary
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _buildTodayContextCard(snapshot),
            ),

            // Dynamic Prompt Suggestions Horizontal Scroller
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final chipText = chips[i];
                  return ActionChip(
                    label: Text(
                      chipText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: const Color(0xFF1E1E2C),
                    side: BorderSide(
                      color: KColor.blue.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onPressed: () => _handleSubmitted(chipText),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),

            // Conversation Message List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (ctx, i) => _buildMessageBubble(_messages[i]),
              ),
            ),

            if (_isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: KColor.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Synthesizing from Kyno context...',
                      style: TextStyle(
                        color: KColor.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

            // Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: KColor.surface,
                border: Border(
                  top: BorderSide(
                    color: KColor.border.withValues(alpha: 0.8),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF12121A),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF2E2E3E),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        controller: _controller,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Ask Kyno anything...',
                          hintStyle: TextStyle(
                            color: KColor.textMuted,
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onSubmitted: _handleSubmitted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _handleSubmitted(_controller.text),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: KColor.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayContextCard(KynoContextSnapshot snapshot) {
    final tr = snapshot.training;
    final nu = snapshot.nutrition;

    final workoutLabel = tr.hasWorkoutToday
        ? '🔥 ${tr.todaySplitDayName ?? "Session"}'
        : '💤 Rest / Recovery';

    final exercisesCount = tr.hasWorkoutToday
        ? '💪 ${tr.exercisesTrainedToday.length} exercises • ${tr.setsLoggedToday} sets'
        : '⚡ ${tr.totalCompletedSessions} lifetime workouts';

    final proText = '🥩 ${nu.consumedProtein.toStringAsFixed(0)} / ${nu.targetProtein.toStringAsFixed(0)}g protein';
    final calText = '🔥 ${nu.consumedCalories.toStringAsFixed(0)} / ${nu.targetCalories.toStringAsFixed(0)} kcal';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF191926),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: KColor.border.withValues(alpha: 0.8),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TODAY AT A GLANCE',
                style: TextStyle(
                  color: KColor.textMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: KColor.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'SYNCED',
                  style: TextStyle(
                    color: KColor.green,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workoutLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      exercisesCount,
                      style: const TextStyle(
                        color: KColor.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      calText,
                      style: const TextStyle(
                        color: KColor.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(KynoChatMessage msg) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: KColor.greenDark.withValues(alpha: 0.6),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            msg.text,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 30),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(14),
          ),
          border: Border.all(
            color: const Color(0xFF2E2E3E),
            width: 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.text.isNotEmpty)
              Text(
                msg.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            if (msg.structuredInsights != null && msg.structuredInsights!.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...msg.structuredInsights!.map(_buildInsightTile),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInsightTile(KynoInsightItem insight) {
    final (badgeText, badgeColor, icon) = switch (insight.type) {
      KynoInformationType.fact => (
          'FACT',
          KColor.blue,
          Icons.verified_rounded
        ),
      KynoInformationType.calculation => (
          'CALCULATION',
          const Color(0xFF38BDF8),
          Icons.calculate_rounded
        ),
      KynoInformationType.inference => (
          'INFERENCE',
          KColor.amber,
          Icons.lightbulb_outline_rounded
        ),
      KynoInformationType.recommendation => (
          'RECOMMENDATION',
          KColor.green,
          Icons.auto_awesome_rounded
        ),
    };

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: badgeColor),
              const SizedBox(width: 5),
              Text(
                badgeText,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  insight.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            insight.detail,
            style: const TextStyle(
              color: KColor.textSecondary,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
