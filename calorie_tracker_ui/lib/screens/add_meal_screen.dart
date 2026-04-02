import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/nutrition_result.dart';
import '../models/day_log.dart';
import '../services/nutrition_pipeline.dart';

class AddMealScreen extends StatefulWidget {
  final MealSection section;
  final DateTime    date;
  final MealEntry?  initialEntry;
  /// Pre-filled text from a suggestion tap — also triggers auto-calculate.
  final String?     initialText;

  const AddMealScreen({
    super.key,
    required this.section,
    required this.date,
    this.initialEntry,
    this.initialText,
  });

  @override
  State<AddMealScreen> createState() => _AddMealScreenState();
}

class _AddMealScreenState extends State<AddMealScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode  = FocusNode();

  NutritionResult? _result;
  bool _loading = false;
  String? _error;

  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulse;

  static const _examples = [
    '2 roti and dal',
    'paneer with rice',
    'thoda sabzi and 3 chapati',
    'dal chawal',
    'oats with milk',
    '4 egg whites with 400ml milk',
    '1 scoop whey',
    'chicken sandwich',
    '2 tbsp peanut butter bread',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialEntry != null) {
      _controller.text = widget.initialEntry!.finalSavedInput;
      _result = widget.initialEntry!.result;
    } else if (widget.initialText != null) {
      _controller.text = widget.initialText!;
    }
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    // Auto-calculate when opened with suggestion text.
    if (widget.initialText != null && widget.initialEntry == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _calculate());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _calculate() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    _focusNode.unfocus();
    HapticFeedback.lightImpact();
    setState(() { _loading = true; _result = null; _error = null; });
    try {
      final result = await NutritionPipeline.instance.estimateMeal(text);
      if (mounted) setState(() { _result = result; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _confirm() {
    if (_result == null || _result!.calories.max == 0) return;
    HapticFeedback.mediumImpact();
    final parsedFoods = _result!.items.map((i) => i.name).toList(growable: false);
    final entry = MealEntry(
      rawInput: widget.initialEntry?.rawInput ?? _controller.text.trim(),
      result:   _result!,
      addedAt:  widget.initialEntry?.addedAt ?? DateTime.now(),
      section: widget.section,
      dayOfWeek: widget.date.weekday,
      parsedFoods: parsedFoods,
      edited: widget.initialEntry != null,
      editCount: (widget.initialEntry?.editCount ?? 0) + (widget.initialEntry != null ? 1 : 0),
      finalSavedInput: _controller.text.trim(),
    );
    if (widget.initialEntry != null) {
      logFor(widget.date).replace(widget.initialEntry!.section, widget.initialEntry!, entry);
    } else {
      logFor(widget.date).add(widget.section, entry);
    }
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131F),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        title: Text(
          widget.initialEntry == null
              ? 'Add to ${widget.section.displayName}'
              : 'Edit ${widget.section.displayName}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Input field ──────────────────────────────
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) {
                        final borderColor = _loading
                            ? Color.lerp(
                                const Color(0xFF2E2E3E),
                                const Color(0xFF52B788),
                                _pulse.value,
                              )!
                            : const Color(0xFF2E2E3E);
                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E2C),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: child,
                        );
                      },
                      child: TextField(
                        controller:      _controller,
                        focusNode:       _focusNode,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15),
                        minLines: 2,
                        maxLines: 5,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _calculate(),
                        decoration: InputDecoration(
                          hintText:
                              '${widget.section.emoji}  Describe your meal…',
                          hintStyle: const TextStyle(
                              color: Color(0xFF4B5563), fontSize: 14),
                          border:        InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled:        false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Quick examples ───────────────────────────
                    const _SectionLabel('Quick examples'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing:    8,
                      runSpacing: 8,
                      children: _examples
                          .map((e) => _ExampleChip(
                                label: e,
                                onTap: () {
                                  _controller.text = e;
                                  _calculate();
                                },
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 20),

                    // ── Calculate button ─────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _calculate,
                        child: _loading
                            ? const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white),
                              )
                            : const Text('Calculate'),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 14, color: Color(0xFFFFB347)),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Could not estimate meal. Using local data.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFFFB347)),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── Result card ──────────────────────────────────────
            if (_result != null)
              SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                              begin: const Offset(0, 0.06),
                              end: Offset.zero)
                          .animate(anim),
                      child: child,
                    ),
                  ),
                  child: Padding(
                    key: ValueKey(_result.hashCode),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: _ResultPreview(
                      result:    _result!,
                      source:    _result!.source,
                      isEditing: widget.initialEntry != null,
                      onConfirm: _confirm,
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

// ─── Result preview ───────────────────────────────────────────────────────────

class _ResultPreview extends StatelessWidget {
  final NutritionResult result;
  final String           source;
  final bool             isEditing;
  final VoidCallback     onConfirm;

  const _ResultPreview({
    required this.result,
    required this.source,
    required this.isEditing,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final hasFood = result.calories.max > 0;
    final userWarnings = result.userFacingWarnings;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasFood
              ? const Color(0xFF52B788).withValues(alpha: 0.35)
              : const Color(0xFF2E2E3E),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasFood)
            const _EmptyResultTile()
          else ...[
            // ── Source pill (clean, no debug text) ────────────
            _SourcePill(source: source),
            const SizedBox(height: 14),

            _PrimaryEstimateRow(result: result),
            const SizedBox(height: 14),

            // ── Per-item breakdown ───────────────────────────
            if (result.items.isNotEmpty) ...[
              const _SectionLabel('Breakdown'),
              const SizedBox(height: 10),
              ...result.items.map((item) => _ItemRow(item: item)),
              const Divider(color: Color(0xFF2E2E3E), height: 20),
            ],

            // ── Total macro chips ─────────────────────────────
            if (result.shouldShowRange) ...[
              const _SectionLabel('Likely range'),
              const SizedBox(height: 8),
              Row(
                children: [
                  _MacroChip(
                    icon:  Icons.local_fire_department_rounded,
                    color: const Color(0xFFFF6B35),
                    label: _rangeLabel(
                        result.calories.min, result.calories.max, 'kcal'),
                  ),
                  const SizedBox(width: 10),
                  _MacroChip(
                    icon:  Icons.fitness_center_rounded,
                    color: const Color(0xFF52B788),
                    label: _rangeLabel(
                        result.protein.min, result.protein.max, 'g protein'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            _ConfidenceBar(confidence: result.confidence),
            if ((result.coachSummary ?? '').isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                result.coachSummary!,
                style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 12.5, height: 1.45),
              ),
            ],
            if (userWarnings.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...userWarnings.map((w) => _WarningRow(text: w)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onConfirm,
                icon: Icon(
                  isEditing ? Icons.save_rounded : Icons.add_rounded,
                  size: 18,
                ),
                label: Text(isEditing ? 'Save Changes' : 'Add to Log'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Returns "235 kcal" when min == max, else "230–240 kcal".
String _rangeLabel(double min, double max, String unit) {
  final minI = min.toInt();
  final maxI = max.toInt();
  return minI == maxI ? '$minI $unit' : '$minI–$maxI $unit';
}

// ─── Source pill — minimal, clean ────────────────────────────────────────────

class _SourcePill extends StatelessWidget {
  final String source;
  const _SourcePill({required this.source});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (source) {
      'memory_exact' => (Icons.bookmark_rounded, const Color(0xFF60A5FA)),
      'cache' || 'memory_recurring' => (Icons.history_rounded, const Color(0xFF52B788)),
      'ai' || 'gemini' => (Icons.auto_awesome_rounded, const Color(0xFFA78BFA)),
      _ => (Icons.restaurant_menu_rounded, const Color(0xFF6B7280)),
    };

    final label = switch (source) {
      'memory_exact' => 'Using saved food memory',
      'cache' || 'memory_recurring' => 'Based on your usual foods',
      'ai' || 'gemini' => 'AI-assisted estimate',
      _ => 'Estimated from common foods',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _PrimaryEstimateRow extends StatelessWidget {
  final NutritionResult result;
  const _PrimaryEstimateRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final cal = result.primaryCaloriesEstimate.toInt();
    final pro = result.primaryProteinEstimate.toInt();
    final calHasRange = result.calories.min.toInt() != result.calories.max.toInt();
    final proHasRange = result.protein.min.toInt() != result.protein.max.toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Primary estimate'),
        const SizedBox(height: 8),
        Text(
          '$cal kcal • $pro g protein',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (result.shouldShowRange && (calHasRange || proHasRange))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${result.estimateLabel} • likely ${_rangeLabel(result.calories.min, result.calories.max, 'kcal')} • ${_rangeLabel(result.protein.min, result.protein.max, 'g protein')}',
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Item breakdown row ───────────────────────────────────────────────────────

class _ItemRow extends StatelessWidget {
  final NutritionItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 5, color: Color(0xFF4B5563)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(item.name,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF9CA3AF))),
          ),
          Text(
            _rangeLabel(item.calories.min, item.calories.max, 'kcal'),
            style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFFF6B35),
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Text(
            _rangeLabel(item.protein.min, item.protein.max, 'g'),
            style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF52B788),
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─── Shared mini-widgets ──────────────────────────────────────────────────────

class _EmptyResultTile extends StatelessWidget {
  const _EmptyResultTile();
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.warning_amber_rounded,
            color: Color(0xFFFFB347), size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'No food recognised — try rephrasing.',
            style: TextStyle(color: Color(0xFFFFB347), fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _MacroChip extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   label;
  const _MacroChip(
      {required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              )),
        ],
      ),
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  final double confidence;
  const _ConfidenceBar({required this.confidence});

  Color _color() {
    if (confidence >= 0.75) return const Color(0xFF52B788);
    if (confidence >= 0.55) return const Color(0xFFFFB347);
    return const Color(0xFFFF6B6B);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Accuracy',
                style: TextStyle(
                    fontSize: 11,
                    color: _color(),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4)),
            Text('${(confidence * 100).toInt()}%',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70)),
          ],
        ),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: confidence),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, v, child) => ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 5,
              backgroundColor: const Color(0xFF2E2E3E),
              valueColor: AlwaysStoppedAnimation(_color()),
            ),
          ),
        ),
      ],
    );
  }
}

class _WarningRow extends StatelessWidget {
  final String text;
  const _WarningRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline_rounded,
                size: 13, color: Color(0xFFFFB347)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFFFB347),
                    height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280),
          letterSpacing: 1.1,
        ));
  }
}

class _ExampleChip extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  const _ExampleChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2E2E3E)),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF9CA3AF))),
      ),
    );
  }
}
