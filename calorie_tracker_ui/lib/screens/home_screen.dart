import 'package:flutter/material.dart';
import '../services/nutrition_pipeline.dart';
import '../models/nutrition_result.dart';

// ─── HomeScreen ───────────────────────────────────────────────────────────────
//
// Standalone meal estimation screen (entry point for quick-check flow).
// Uses the full AI pipeline (cache → OpenRouter → local fallback).
// Navigation: this screen is not used in the main onboarding→dashboard flow;
// it exists as a standalone estimation playground/utility.

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  NutritionResult? _result;
  bool _loading = false;

  static const _suggestions = [
    '2 roti and dal',
    'paneer with rice',
    'thoda sabzi and 3 chapati',
    'dal chawal',
    'roti sabzi paneer',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _calculate() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _loading) return;

    _focusNode.unfocus();
    setState(() { _loading = true; _result = null; });

    try {
      final result = await NutritionPipeline.instance.estimateMeal(input);
      if (mounted) setState(() { _result = result; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _useSuggestion(String suggestion) {
    _controller.text = suggestion;
    _calculate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── App bar ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D6A4F),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.restaurant_rounded,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Calorie Tracker',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'What did you eat?',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Describe your meal in plain language',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Input + button ───────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  children: [
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      minLines: 2,
                      maxLines: 4,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _calculate(),
                      decoration: const InputDecoration(
                        hintText: 'e.g. 2 roti dal thoda paneer',
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(left: 14, right: 10, top: 14),
                          child: Icon(Icons.edit_note_rounded,
                              color: Color(0xFF52B788), size: 22),
                        ),
                        prefixIconConstraints: BoxConstraints(minWidth: 0),
                        contentPadding: EdgeInsets.fromLTRB(0, 16, 16, 16),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _calculate,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Calculate'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Suggestions ─────────────────────────────────────
            if (_result == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Try these',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _suggestions
                            .map((s) => _SuggestionChip(
                                  label: s,
                                  onTap: () => _useSuggestion(s),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Result card ──────────────────────────────────────
            if (_result != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.06),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _HomeResultCard(
                      key: ValueKey(_result.hashCode),
                      result: _result!,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Inline result card for HomeScreen ───────────────────────────────────────

class _HomeResultCard extends StatelessWidget {
  final NutritionResult result;
  const _HomeResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final hasFood = result.calories.max > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasFood
              ? const Color(0xFF52B788).withValues(alpha: 0.35)
              : Colors.transparent,
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: hasFood ? _content() : _empty(),
    );
  }

  Widget _empty() {
    return const Row(
      children: [
        Icon(Icons.restaurant_menu_rounded, size: 24, color: Color(0xFF4B5563)),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'No food recognised — try rephrasing.',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _content() {
    final calMin = result.calories.min.toInt();
    final calMax = result.calories.max.toInt();
    final proMin = result.protein.min.toInt();
    final proMax = result.protein.max.toInt();
    final primaryCal = result.primaryCaloriesEstimate.toInt();
    final primaryPro = result.primaryProteinEstimate.toInt();
    final userWarnings = result.userFacingWarnings;

    final calLabel = calMin == calMax ? '$calMin kcal' : '$calMin–$calMax kcal';
    final proLabel = proMin == proMax ? '$proMin g' : '$proMin–$proMax g';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$primaryCal kcal • $primaryPro g protein',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          result.shouldShowRange
              ? '${result.estimateLabel} • likely $calLabel • $proLabel'
              : result.estimateLabel,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF9CA3AF),
          ),
        ),
        if ((result.coachSummary ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            result.coachSummary!,
            style: const TextStyle(fontSize: 13, color: Color(0xFFD1D5DB), height: 1.35),
          ),
        ],
        const SizedBox(height: 20),
        _NutrientRow(
          icon: Icons.local_fire_department_rounded,
          iconColor: const Color(0xFFFF6B35),
          label: 'Calories',
          value: calLabel,
        ),
        const SizedBox(height: 16),
        _NutrientRow(
          icon: Icons.fitness_center_rounded,
          iconColor: const Color(0xFF52B788),
          label: 'Protein',
          value: proLabel,
        ),
        const SizedBox(height: 20),
        _ConfidenceBar(confidence: result.confidence),
        if (userWarnings.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(color: Color(0xFF2E2E3E), height: 1),
          const SizedBox(height: 16),
          ...userWarnings.map((w) => _WarningTile(message: w)),
        ],
      ],
    );
  }
}

class _NutrientRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _NutrientRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                  letterSpacing: 0.6,
                )),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                )),
          ],
        ),
      ],
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  final double confidence;
  const _ConfidenceBar({required this.confidence});

  Color _barColor() {
    if (confidence >= 0.75) return const Color(0xFF52B788);
    if (confidence >= 0.55) return const Color(0xFFFFB347);
    return const Color(0xFFFF6B6B);
  }

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(confidence >= 0.75 ? 'High confidence' : confidence >= 0.55 ? 'Approximate' : 'Lower confidence',
                style: TextStyle(
                  fontSize: 12, color: _barColor(),
                  fontWeight: FontWeight.w600, letterSpacing: 0.4,
                )),
            Text('$pct%',
                style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70,
                )),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: confidence),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, value, child) => LinearProgressIndicator(
              value: value,
              minHeight: 7,
              backgroundColor: const Color(0xFF2E2E3E),
              valueColor: AlwaysStoppedAnimation(_barColor()),
            ),
          ),
        ),
      ],
    );
  }
}

class _WarningTile extends StatelessWidget {
  final String message;
  const _WarningTile({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline_rounded,
                size: 14, color: Color(0xFFFFB347)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13, color: Color(0xFFFFB347), height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Suggestion chip ──────────────────────────────────────────────────────────

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2E2E3E)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }
}
