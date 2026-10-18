/// One short form cue per lift, in the voice of the guy who spots you.
///
/// Matched on the start of a word in the exercise name, most specific first.
/// Lifts with no line here (or an empty line, for cardio machines whose names
/// would otherwise match a lift) get no cue at all: a generic tip is worse
/// than silence.
const List<(List<String>, String)> _cues = [
  (['rowing', 'treadmill', 'cycling', 'elliptical'], ''),
  (['incline bench', 'incline press', 'incline chest press', 'incline dumbbell press', 'incline barbell press', 'incline smith'], 'Bench at 30 degrees, not 45. Bar to the upper chest.'),
  (['close grip bench', 'close-grip bench'], 'Hands shoulder width. Elbows tucked, touch low chest.'),
  (['bench press', 'floor press'], 'Shoulder blades pinned. Touch low chest, drive the floor away.'),
  (['chest press'], 'Handles in line with mid chest. Shoulders stay back in the pad.'),
  (['pec deck', 'fly', 'flye', 'flyes', 'butterfly', 'crossover'], 'Soft elbows, hug a big tree. Own the stretch.'),
  (['push up', 'push-up', 'pushup'], 'Body in one line. Chest touches first, not the hips.'),
  (['dip'], 'Lean forward for chest, stay tall for triceps. Shoulders down.'),
  (['pullover'], 'Arms nearly straight. Let the lats stretch, then pull from the elbows.'),
  (['front squat'], 'Elbows high. Stay tall out of the hole.'),
  (['goblet'], 'Elbows inside the knees at the bottom. Chest up.'),
  (['hack squat'], 'Sit deep and keep the lower back on the pad.'),
  (['bulgarian', 'split squat'], 'Front shin near vertical. Drop the back knee straight down.'),
  (['squat'], 'Big breath, brace hard. Knees follow the toes.'),
  (['leg press'], "Lower back stays on the pad. Don't lock the knees."),
  (['lunge'], 'Long enough step that the front heel stays down. Torso tall.'),
  (['romanian', 'rdl', 'stiff leg', 'stiff-leg'], 'Hips back to the wall. Bar stays on the legs.'),
  (['good morning'], 'Soft knees, hips back, flat back all the way.'),
  (['deadlift'], 'Pull the slack out first. Push the floor away.'),
  (['hip thrust', 'glute bridge'], "Chin tucked, ribs down. Squeeze at the top, don't arch."),
  (['leg extension'], 'Pause at the top. Lower on a slow two count.'),
  (['leg curl', 'hamstring curl', 'nordic'], 'Hips pinned to the pad. Heels to the glutes.'),
  (['calf'], 'Hold the stretch at the bottom. Then up onto the big toe.'),
  (['adduction', 'adductor'], 'Control the open. Squeeze and pause when the pads meet.'),
  (['abduction', 'abductor'], 'Lean slightly forward. Push the knees out and hold.'),
  (['pull up', 'pull-up', 'pullup', 'chin up', 'chin-up', 'chinup'], 'Start from a dead hang. Chest to the bar.'),
  (['pulldown', 'pull down', 'pull-down'], 'Lead with the elbows. Bar to the top of the chest, no swinging.'),
  (['face pull'], 'Pull to the eyebrows. Elbows high, thumbs back.'),
  (['upright row'], 'Elbows lead. Stop at chest height.'),
  (['row'], 'Pull to the hip, not the chest. Pause a second at the top.'),
  (['shrug'], "Straight up to the ears and hold. Don't roll."),
  (['rear delt', 'reverse fly', 'reverse pec'], 'Arms long, think wide not back. No swing.'),
  (['lateral raise', 'side raise'], 'Lead with the elbows. Stop at shoulder height, lower slow.'),
  (['front raise'], "Thumbs up, stop at eye level. Don't lean back."),
  (['overhead press', 'shoulder press', 'military press', 'ohp', 'arnold'], 'Squeeze the glutes. Head through at the top.'),
  (['hammer curl'], 'Thumbs up, elbows pinned. No swing.'),
  (['preacher'], "Full stretch at the bottom. Don't bounce off the pad."),
  (['wrist curl'], 'Forearms on the bench. Let the bar roll to the fingers.'),
  (['curl'], "Elbows pinned to your sides. If you have to swing it, it's too heavy."),
  (['skull', 'lying tricep', 'lying triceps'], 'Elbows point at the ceiling. Lower slow to the forehead.'),
  (['pushdown', 'push down', 'pressdown'], 'Elbows glued to the ribs. Lock out and squeeze.'),
  (['overhead extension', 'overhead tricep', 'overhead triceps', 'french press'], 'Elbows in. Full stretch behind the head.'),
  (['kickback'], 'Upper arm parallel to the floor. Only the forearm moves.'),
  (['farmer'], 'Shoulders back, short quick steps. Crush the handles.'),
  (['plank'], 'Squeeze glutes and quads. Plank, not hammock.'),
  (['leg raise', 'knee raise'], 'Curl the pelvis up. No swinging off the bar.'),
  (['crunch', 'sit up', 'sit-up'], 'Ribs to hips. Breathe out hard at the top.'),
];

final List<(RegExp, String)> _compiled = [
  for (final (keys, cue) in _cues)
    (RegExp(keys.map((k) => r'\b' + RegExp.escape(k)).join('|')), cue),
];

/// The cue for [exerciseName], or null when there is nothing specific to say.
String? formCueFor(String exerciseName) {
  final n = exerciseName.toLowerCase();
  if (n.trim().isEmpty) return null;
  for (final (pattern, cue) in _compiled) {
    if (pattern.hasMatch(n)) return cue.isEmpty ? null : cue;
  }
  return null;
}

/// Every cue line, for copy tests.
Iterable<String> get allFormCues =>
    _cues.map((c) => c.$2).where((c) => c.isNotEmpty);
