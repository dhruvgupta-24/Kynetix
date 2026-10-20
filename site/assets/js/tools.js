/* Kynetix calculators. Same formulas as the app (nutrition_target_engine.dart,
   workout_session.dart). Labels live in the page; this only fills numbers. */
(function () {
  'use strict';
  var form = document.querySelector('form[data-tool]');
  if (!form) return;
  var tool = form.getAttribute('data-tool');
  var out = document.querySelector('[data-results]');
  var words = {};
  try { words = JSON.parse(document.getElementById('tool-words').textContent); } catch (e) {}
  var nf = new Intl.NumberFormat(document.documentElement.lang || 'en-IN', { maximumFractionDigits: 1 });
  var r1 = function (v) { return Math.round(v * 10) / 10; };
  var num = function (n) { var el = form.elements[n]; return el ? parseFloat(el.value) : NaN; };
  var val = function (n) { var el = form.elements[n]; return el ? el.value : ''; };
  var set = function (k, v) { var el = out.querySelector('[data-out="' + k + '"]'); if (el) el.textContent = v; };
  var clamp = function (v, a, b) { return Math.min(b, Math.max(a, v)); };

  function bmr(sex, w, h, a) { return sex === 'male' ? 10 * w + 6.25 * h - 5 * a + 5 : 10 * w + 6.25 * h - 5 * a - 161; }
  function mult(days) {
    if (days <= 0.5) return 1.20; if (days <= 1.5) return 1.25; if (days <= 2.5) return 1.29; if (days <= 3.5) return 1.33;
    if (days <= 4.5) return 1.37; if (days <= 5.5) return 1.41; if (days <= 6.5) return 1.45; return 1.50;
  }
  function goalDelta(goal, tdee) {
    var b = function (v, lo, hi) { return clamp(v, lo, hi); };
    if (goal === 'cut') return -b(tdee * 0.22, 350, 550);
    if (goal === 'leanbulk') return b(tdee * 0.08, 150, 250);
    if (goal === 'bulk') return b(tdee * 0.10, 200, 350);
    if (goal === 'recomp') return -b(tdee * 0.09, 120, 250);
    return 0;
  }
  function cycle(days) { if (days <= 1) return 140; if (days <= 3) return 180; if (days <= 5) return 200; return 220; }
  function refWeight(w, h) { var hm = h / 100; if (hm <= 0) return w; var cap = 27 * hm * hm; return w < cap ? w : cap; }
  var PROT = { cut: [2.10, 2.20, 2.00], recomp: [2.00, 2.10, 1.90], leanbulk: [1.80, 1.90, 1.70], bulk: [1.80, 1.90, 1.70], maintain: [1.80, 1.90, 1.70] };
  function steps(w, s) { if (!s || isNaN(s)) return 0; return Math.round(clamp((s - 7000) * w * 0.00075 * 0.55, -400, 400)); }

  function targets() {
    var sex = val('sex'), a = num('age'), h = num('height'), w = num('weight'), d = clamp(num('days') || 0, 0, 7), g = val('goal') || 'maintain';
    var B = bmr(sex, w, h, a);
    var tdee = r1(B * mult(d) + steps(w, num('steps')));
    var raw = tdee + goalDelta(g, tdee);
    var floor = r1(B + 200);
    var sp = cycle(d);
    return {
      bmr: B, tdee: tdee, avg: r1(Math.max(raw, floor)), floor: floor,
      train: r1(Math.max(raw + sp * (7 - d) / 7, floor)), rest: r1(Math.max(raw - sp * d / 7, floor)),
      ref: refWeight(w, h), goal: g, w: w
    };
  }

  function run() {
    if (!form.checkValidity()) { out.hidden = true; return; }
    var t;
    if (tool === 'calories') {
      t = targets();
      set('bmr', nf.format(Math.round(t.bmr))); set('tdee', nf.format(Math.round(t.tdee)));
      set('avg', nf.format(Math.round(t.avg))); set('train', nf.format(Math.round(t.train))); set('rest', nf.format(Math.round(t.rest)));
    } else if (tool === 'protein') {
      var w = num('weight'), h = num('height'), g = val('goal') || 'maintain', p = PROT[g] || PROT.maintain, ref = refWeight(w, h);
      set('ref', nf.format(r1(ref))); set('avg', nf.format(Math.round(ref * p[0]))); set('train', nf.format(Math.round(ref * p[1]))); set('rest', nf.format(Math.round(ref * p[2])));
      set('perkg', nf.format(p[0]));
    } else if (tool === 'macros') {
      t = targets();
      var pr = r1(t.ref * (PROT[t.goal] || PROT.maintain)[0]);
      var np = Math.max(0, t.avg - pr * 4);
      var fat = Math.max(np * 0.30 / 9, 0.6 * t.ref);
      var carbs = Math.max(0, (np - fat * 9) / 4);
      set('cal', nf.format(Math.round(t.avg))); set('protein', nf.format(Math.round(pr))); set('fat', nf.format(Math.round(fat)));
      set('carbs', nf.format(Math.round(carbs))); set('fiber', nf.format(Math.round(clamp(14 * t.avg / 1000, 20, 60))));
    } else if (tool === 'onerm') {
      var wt = num('weight'), reps = num('reps');
      var orm = wt * (1 + reps / 30);
      set('orm', nf.format(r1(orm)));
      out.querySelectorAll('[data-pct]').forEach(function (td) { td.textContent = nf.format(Math.round(orm * (+td.getAttribute('data-pct')) / 100 * 2) / 2); });
    } else if (tool === 'bmi') {
      var hh = num('height') / 100, bmi = num('weight') / (hh * hh);
      set('bmi', nf.format(r1(bmi)));
      var who = bmi < 18.5 ? 'under' : bmi < 25 ? 'normal' : bmi < 30 ? 'over' : 'obese';
      var asia = bmi < 18.5 ? 'under' : bmi < 23 ? 'normal' : bmi < 27.5 ? 'over' : 'obese';
      set('who', (words.bmi || {})[who] || who); set('asia', (words.bmi || {})[asia] || asia);
      set('range', nf.format(r1(18.5 * hh * hh)) + ' ' + (words.to || 'to') + ' ' + nf.format(r1(22.9 * hh * hh)));
    }
    out.hidden = false;
  }
  form.addEventListener('submit', function (ev) { ev.preventDefault(); run(); var h = out.querySelector('h2, h3'); if (h) { h.setAttribute('tabindex', '-1'); h.focus({ preventScroll: false }); } });
  form.addEventListener('input', function () { if (!out.hidden) run(); });
})();
