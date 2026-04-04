// ─── Coach insight model ──────────────────────────────────────────────────────

enum CoachInsightType { protein, overGoal, underEaten, balance, info }

class CoachInsight {
  final CoachInsightType type;
  final String           message;
  final String?          actionHint;

  const CoachInsight({
    required this.type,
    required this.message,
    this.actionHint,
  });
}
