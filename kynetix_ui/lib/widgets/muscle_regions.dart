import 'package:flutter/foundation.dart';

import 'muscle_body_map.dart' show BodyView;

/// Where a muscle-group label lives on the anatomical body map.
///
/// [regions] are path ids in `assets/data/body_paths.json` (for example
/// `upper-back`, `gluteal`, `quadriceps`); [view] is the side of the body on
/// which those regions are best seen, so a one-sided thumbnail shows the
/// muscle the user actually trained.
@immutable
class MuscleTarget {
  const MuscleTarget(this.view, this.regions);

  final BodyView view;
  final Set<String> regions;

  @override
  bool operator ==(Object other) =>
      other is MuscleTarget &&
      other.view == view &&
      setEquals(other.regions, regions);

  @override
  int get hashCode => Object.hash(view, Object.hashAllUnordered(regions));

  @override
  String toString() => 'MuscleTarget($view, $regions)';
}

/// Every region id painted by the body map, per view.
const Set<String> kFrontRegions = {
  'chest', 'abs', 'obliques', 'serratus', 'deltoids', 'biceps', 'triceps',
  'forearm', 'trapezius', 'quadriceps', 'adductors', 'hip-flexors', 'calves',
  'tibialis',
};
const Set<String> kBackRegions = {
  'trapezius', 'deltoids', 'upper-back', 'lower-back', 'triceps', 'forearm',
  'gluteal', 'adductors', 'hamstring', 'calves',
};

const _f = BodyView.front;
const _b = BodyView.back;

// Ordered: the first rule whose pattern matches wins, so specific names
// ("rear delts", "lower back", "abductors", "forearms") sit above the broad
// words that would also match them ("delt", "back", "ab", "arm").
final List<(RegExp, MuscleTarget)> _rules = [
  (RegExp(r'\b(rear|posterior) delt'), const MuscleTarget(_b, {'deltoids'})),
  (RegExp(r'shoulder|delt'), const MuscleTarget(_f, {'deltoids'})),
  (RegExp(r'abductor|outer thigh'), const MuscleTarget(_b, {'gluteal'})),
  (RegExp(r'adductor|inner thigh'), const MuscleTarget(_f, {'adductors'})),
  (RegExp(r'lower back|erector|spinal'), const MuscleTarget(_b, {'lower-back'})),
  (RegExp(r'upper back|mid back|middle back|rhomboid|\blats?\b|latissimus'),
      const MuscleTarget(_b, {'upper-back'})),
  (RegExp(r'trap'), const MuscleTarget(_b, {'trapezius'})),
  (RegExp(r'forearm|wrist|grip|lower arm'), const MuscleTarget(_f, {'forearm'})),
  (RegExp(r'tricep'), const MuscleTarget(_b, {'triceps'})),
  (RegExp(r'bicep|brachialis'), const MuscleTarget(_f, {'biceps'})),
  (RegExp(r'chest|\bpecs?\b|pectoral'), const MuscleTarget(_f, {'chest'})),
  (RegExp(r'serratus'), const MuscleTarget(_f, {'serratus'})),
  (RegExp(r'oblique'), const MuscleTarget(_f, {'obliques'})),
  (RegExp(r'\bcore\b|\bwaist\b'), const MuscleTarget(_f, {'abs', 'obliques'})),
  (RegExp(r'\babs?\b|abdominal'), const MuscleTarget(_f, {'abs'})),
  (RegExp(r'hip flexor|psoas'), const MuscleTarget(_f, {'hip-flexors'})),
  (RegExp(r'glute'), const MuscleTarget(_b, {'gluteal'})),
  (RegExp(r'hamstring'), const MuscleTarget(_b, {'hamstring'})),
  (RegExp(r'quad'), const MuscleTarget(_f, {'quadriceps'})),
  (RegExp(r'calf|calves|soleus|gastrocnemius|lower leg'),
      const MuscleTarget(_b, {'calves'})),
  (RegExp(r'tibialis|\bshins?\b'), const MuscleTarget(_f, {'tibialis'})),
  // Broad library categories / body parts.
  (RegExp(r'upper arm'), const MuscleTarget(_f, {'biceps', 'triceps'})),
  (RegExp(r'\barms?\b'), const MuscleTarget(_f, {'biceps', 'triceps', 'forearm'})),
  (RegExp(r'upper leg|thigh|\blegs?\b'),
      const MuscleTarget(_f, {'quadriceps', 'adductors'})),
  (RegExp(r'\bback\b'), const MuscleTarget(_b, {'upper-back'})),
];

/// Maps a muscle-group label ("Chest", "Rear Delts", "Lower Back", "Glutes",
/// "Arms", or a raw region id like "upper-back") to the body-map regions it
/// names. Returns null for labels with no muscle on the map ("Cardio",
/// "Strength", "Neck", "Other", "Full body"): callers show text only, since
/// wrong imagery is worse than none.
MuscleTarget? muscleTargetFor(String group) {
  final g = group.toLowerCase().replaceAll(RegExp(r'[-_/]'), ' ').trim();
  if (g.isEmpty) return null;
  for (final (pattern, target) in _rules) {
    if (pattern.hasMatch(g)) return target;
  }
  return null;
}

/// The region ids for [group] on either view, or an empty set.
Set<String> muscleRegionsFor(String group) =>
    muscleTargetFor(group)?.regions ?? const {};
