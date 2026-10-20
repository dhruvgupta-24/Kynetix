/* Kynetix home: things to touch. The app tour, the shear you can drag, a plate
   to build, a set to log, Kyno as a chat, and a deck of share cards to flick.
   Phone first, no dependencies, everything works without motion. */
(function () {
  'use strict';
  var doc = document;
  var root = doc.documentElement;
  var $ = function (s, c) { return (c || doc).querySelector(s); };
  var $$ = function (s, c) { return Array.prototype.slice.call((c || doc).querySelectorAll(s)); };
  var clamp = function (v, a, b) { return Math.min(b, Math.max(a, v)); };
  var now = function () { return performance.now(); };
  var mqReduce = window.matchMedia('(prefers-reduced-motion: reduce)');
  var motion = !mqReduce.matches;
  var mqPhone = window.matchMedia('(max-width: 979.98px)');
  var mqChat = window.matchMedia('(max-width: 979.98px), (hover: none)');
  var fmt = function (n, dec) { return n.toLocaleString('en-IN', { maximumFractionDigits: dec || 0, minimumFractionDigits: 0 }); };

  /* A short tap on the glass. Android only; silent everywhere else. */
  var buzz = function (p) {
    if (!motion || !navigator.vibrate || !navigator.userActivation || !navigator.userActivation.hasBeenActive) return;
    try { navigator.vibrate(p); } catch (e) {}
  };

  /* ── Rolling digits: each digit is a 0 to 9 strip that slides ── */
  var odos = {};
  $$('.odo').forEach(function (el) { odos[el.getAttribute('data-odo')] = el; el._v = 0; });
  var roll = function (key, v, dec) {
    var el = odos[key];
    if (!el) return;
    var s = fmt(v, dec);
    if (el._s === s) return;
    el._s = s;
    var w = el._w;
    if (!w) {
      el.textContent = '';
      el._sr = doc.createElement('span'); el._sr.className = 'sr-only';
      w = el._w = doc.createElement('span'); w.className = 'rd-w'; w.setAttribute('aria-hidden', 'true');
      el.appendChild(el._sr); el.appendChild(w);
    }
    el._sr.textContent = s;
    var chars = s.split('');
    /* Rebuild only when the shape changes (a digit added or a comma moved). */
    var shape = chars.map(function (c) { return /\d/.test(c) ? 'd' : c; }).join('');
    if (w._shape !== shape) {
      w.innerHTML = chars.map(function (c, i) {
        if (!/\d/.test(c)) return '<span>' + c + '</span>';
        return '<span class="rd"><span class="rd-0">0</span><span class="rd-s"><i>0</i><i>1</i><i>2</i><i>3</i><i>4</i><i>5</i><i>6</i><i>7</i><i>8</i><i>9</i></span></span>';
      }).join('');
      w._shape = shape;
      void w.offsetWidth;
    }
    var strips = $$('.rd-s', w);
    var d = 0;
    chars.forEach(function (c) {
      if (!/\d/.test(c)) return;
      strips[d].style.transform = 'translateY(' + (-c * 10) + '%)';
      d++;
    });
  };

  /* ── 1. Hero: the app tour, story style ──────────────── */
  var tour = $('.tour');
  if (tour) (function () {
    var slides = $$('.tsl', tour);
    var bars = $$('.tour-bars i', tour);
    var slash = $('.slash', tour);
    var capB = $('.tour-cap b', tour), capS = $('.tour-cap span', tour), cap = $('.tour-cap', tour);
    var screen = $('.screen', tour);
    var DUR = 4200, idx = 0, t0 = now(), held = false, heldAt = 0, visible = false, pageOn = !doc.hidden, raf = null, spent = 0;
    var go = function (n) {
      n = (n + slides.length) % slides.length;
      if (n === idx) return;
      slides.forEach(function (s) { s.classList.remove('was', 'cutting'); });
      slides[idx].classList.add('was'); slides[idx].classList.remove('on');
      slides[n].classList.add('on');
      if (motion) {
        void slides[n].offsetWidth; slides[n].classList.add('cutting');
        if (slash) { slash.classList.remove('go'); void slash.offsetWidth; slash.classList.add('go'); }
      }
      var parts = (slides[n].getAttribute('data-cap') || '|').split('|');
      capB.textContent = parts[0]; capS.textContent = parts[1];
      if (motion) { cap.classList.remove('swap'); void cap.offsetWidth; cap.classList.add('swap'); }
      idx = n; spent = 0; t0 = now();
      paintBars(0);
      /* Warm the next screen so the cut never shows a blank half. */
      $$('img', slides[(n + 1) % slides.length]).forEach(function (im) { im.loading = 'eager'; });
    };
    var paintBars = function (p) {
      bars.forEach(function (b, i) { b.style.setProperty('--p', i < idx ? 1 : i === idx ? p.toFixed(4) : 0); b.classList.toggle('now', i === idx); });
    };
    var running = function () { return motion && visible && pageOn && !held; };
    var loop = function () {
      raf = null;
      if (!running()) return;
      var p = (spent + now() - t0) / DUR;
      if (p >= 1) { go(idx + 1); p = 0; }
      paintBars(p);
      raf = requestAnimationFrame(loop);
    };
    var kick = function () { if (!raf && running()) { t0 = now(); raf = requestAnimationFrame(loop); } };
    var halt = function () { spent += now() - t0; if (raf) { cancelAnimationFrame(raf); raf = null; } };
    new IntersectionObserver(function (es) { var v = es[0].isIntersecting; if (v === visible) return; visible = v; if (v) kick(); else halt(); }, { threshold: 0.35 }).observe(tour);
    doc.addEventListener('visibilitychange', function () { pageOn = !doc.hidden; if (pageOn) kick(); else halt(); });

    /* Tap the sides to skip, hold to pause, swipe to flip through. */
    var sx = 0, sy = 0, swiped = false, holdT = null, longHold = false;
    screen.addEventListener('pointerdown', function (e) {
      sx = e.clientX; sy = e.clientY; swiped = false; longHold = false;
      clearTimeout(holdT);
      holdT = setTimeout(function () { longHold = true; held = true; heldAt = now(); halt(); tour.classList.add('held'); }, 220);
    });
    screen.addEventListener('pointermove', function (e) {
      if (Math.abs(e.clientX - sx) > 12 || Math.abs(e.clientY - sy) > 12) clearTimeout(holdT);
    });
    var release = function (e) {
      clearTimeout(holdT);
      var dx = e.clientX - sx, dy = e.clientY - sy;
      if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy) * 1.3) { swiped = true; go(idx + (dx < 0 ? 1 : -1)); buzz(6); }
      if (held) { held = false; tour.classList.remove('held'); t0 = now(); kick(); }
    };
    screen.addEventListener('pointerup', release);
    screen.addEventListener('pointercancel', function () { clearTimeout(holdT); if (held) { held = false; tour.classList.remove('held'); kick(); } });
    $$('.tour-hit', tour).forEach(function (b) {
      b.addEventListener('click', function () {
        if (swiped || longHold) { swiped = false; longHold = false; return; }
        go(idx + (b.classList.contains('next') ? 1 : -1)); buzz(6); kick();
      });
    });
    screen.addEventListener('contextmenu', function (e) { if (longHold) e.preventDefault(); });
    tour.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowRight') { go(idx + 1); e.preventDefault(); }
      if (e.key === 'ArrowLeft') { go(idx - 1); e.preventDefault(); }
    });
    paintBars(0);
    /* The download pill steps aside while the tour is on screen. */
    var pill = $('.dl-pill');
    if (pill) new IntersectionObserver(function (es) { pill.classList.toggle('aside', es[0].isIntersecting); }, { threshold: 0.2 }).observe(tour);
  })();

  /* ── 2. Hero: drag the shear, tilt the phone ─────────── */
  var wm = $('.hero .wm');
  var wmScroll = $('.hero .wm-scroll');
  if (wm && wmScroll && motion) (function () {
    var g = doc.createElementNS('http://www.w3.org/2000/svg', 'g');
    g.setAttribute('class', 'wm-drag');
    while (wmScroll.firstChild) g.appendChild(wmScroll.firstChild);
    wmScroll.appendChild(g);
    var x = 0, v = 0, target = 0, tilt = 0, dragging = false, startX = 0, startShift = 0, raf = null, last = 0, hitEdge = false;
    var unit = function () { return 3797.8 / Math.max(1, wm.getBoundingClientRect().width); };
    var paint = function () { g.setAttribute('transform', 'translate(' + (x + tilt).toFixed(1) + ' 0)'); };
    var step = function (t) {
      raf = null;
      var dt = Math.min(0.032, (t - (last || t)) / 1000 || 0.016); last = t;
      if (!dragging) {
        /* A spring with a little bounce, so the top half snaps back like it has weight. */
        var a = -260 * (x - target) - 16 * v;
        v += a * dt; x += v * dt;
        if (Math.abs(x - target) < 0.3 && Math.abs(v) < 2) { x = target; v = 0; paint(); last = 0; return; }
      }
      paint();
      raf = requestAnimationFrame(step);
    };
    var run = function () { if (!raf) raf = requestAnimationFrame(step); };
    wm.style.touchAction = 'pan-y';
    wm.setAttribute('data-cursor', 'Drag');
    wm.addEventListener('pointerdown', function (e) {
      dragging = true; startX = e.clientX; startShift = x; hitEdge = false;
      try { wm.setPointerCapture(e.pointerId); } catch (err) {}
      wm.classList.add('grab'); run();
    });
    wm.addEventListener('pointermove', function (e) {
      if (!dragging) return;
      var raw = startShift + (e.clientX - startX) * unit();
      /* Past the limits it gets stiff instead of stopping dead. */
      var lo = -260, hi = 720;
      var nx = raw > hi ? hi + (raw - hi) * 0.25 : raw < lo ? lo + (raw - lo) * 0.25 : raw;
      var edge = raw > hi || raw < lo;
      if (edge && !hitEdge) buzz(8);
      hitEdge = edge;
      v = (nx - x) * 60; x = nx;
    });
    var up = function () { if (!dragging) return; dragging = false; wm.classList.remove('grab'); buzz(5); run(); };
    wm.addEventListener('pointerup', up);
    wm.addEventListener('pointercancel', up);

    /* Tilt the phone in your hand and the cut leans with it (Android, no prompt). */
    var tiltEls = $$('.tour-tilt');
    var gyroOn = false, gb = 0, gg = 0, base = null;
    var onTilt = function (e) {
      if (e.gamma == null) return;
      if (!base) base = { b: e.beta, g: e.gamma };
      gg += ((e.gamma - base.g) - gg) * 0.12;
      gb += ((e.beta - base.b) - gb) * 0.12;
      tilt = clamp(gg, -25, 25) * 6;
      tiltEls.forEach(function (t) {
        t.style.setProperty('--ry', clamp(gg * 0.45, -9, 9).toFixed(2) + 'deg');
        t.style.setProperty('--rx', clamp(-gb * 0.3, -7, 7).toFixed(2) + 'deg');
        t.style.setProperty('--gx', (50 - clamp(gg, -25, 25) * 2).toFixed(1) + '%');
      });
      if (!dragging) run();
    };
    var hero = $('.hero');
    if ('DeviceOrientationEvent' in window && typeof DeviceOrientationEvent.requestPermission !== 'function' && window.matchMedia('(pointer: coarse)').matches) {
      new IntersectionObserver(function (es) {
        var want = es[0].isIntersecting;
        if (want === gyroOn) return;
        gyroOn = want;
        if (want) { base = null; window.addEventListener('deviceorientation', onTilt); } else window.removeEventListener('deviceorientation', onTilt);
      }).observe(hero);
    }
  })();

  /* ── 3. Food: build a plate with the app's own numbers ── */
  var plate = $('.plate');
  var recapState = { kcal: 0, p: 0, items: 0, vol: 0, sets: 0, prs: 0 };
  var recap = $('.recap');
  var paintRecap = function () {
    if (!recap) return;
    var bits = [];
    if (recapState.items) bits.push('Your demo plate came to ' + fmt(recapState.kcal) + ' kcal and ' + fmt(recapState.p, 1) + ' g of protein.');
    if (recapState.sets) bits.push('You logged ' + recapState.sets + (recapState.sets === 1 ? ' set' : ' sets') + ' and moved ' + fmt(recapState.vol, 1) + ' kg' + (recapState.prs ? ', with a new best in there.' : '.'));
    if (!bits.length) { recap.hidden = true; return; }
    bits.push('The app keeps all of it, and Kyno reads it.');
    recap.textContent = bits.join(' ');
    recap.hidden = false;
  };
  if (plate) (function () {
    var list = $('.plate-items', plate);
    var empty = $('.plate-empty', plate);
    var clear = $('.plate-clear', plate);
    var ringK = $('.rg-k', plate), ringP = $('.rg-p', plate), rings = $('.rings', plate);
    var items = {}; var order = [];
    var T = { kcal: 2459, p: 144 };
    var totals = function () {
      var t = { kcal: 0, p: 0, c: 0, f: 0, n: 0 };
      order.forEach(function (k) { var it = items[k]; t.kcal += it.kcal * it.q; t.p += it.p * it.q; t.c += it.c * it.q; t.f += it.f * it.q; t.n += it.q; });
      return t;
    };
    var paint = function () {
      var t = totals();
      roll('kcal', Math.round(t.kcal)); roll('kcal2', Math.round(t.kcal));
      roll('p', Math.round(t.p * 10) / 10, 1); roll('c', Math.round(t.c)); roll('f', Math.round(t.f));
      ringK.style.strokeDasharray = (clamp(t.kcal / T.kcal, 0, 1) * 100).toFixed(2) + ' 100';
      ringP.style.strokeDasharray = (clamp(t.p / T.p, 0, 1) * 100).toFixed(2) + ' 100';
      ringK.style.opacity = t.kcal > 0 ? 1 : 0; ringP.style.opacity = t.p > 0 ? 1 : 0;
      rings.classList.toggle('met', t.p >= T.p);
      rings.classList.toggle('over', t.kcal > T.kcal);
      rings.setAttribute('aria-label', 'This plate: ' + fmt(Math.round(t.kcal)) + ' of 2,459 kcal and ' + fmt(t.p, 1) + ' of 144 g protein');
      empty.hidden = t.n > 0; clear.hidden = t.n === 0;
      recapState.kcal = Math.round(t.kcal); recapState.p = Math.round(t.p * 10) / 10; recapState.items = t.n; paintRecap();
    };
    var row = function (k) {
      var it = items[k];
      if (!it.li) {
        it.li = doc.createElement('li');
        it.li.className = 'pi';
        it.li.innerHTML = '<span class="pi-q"></span><span class="pi-n"></span><span class="pi-k"></span><button type="button" class="pi-x"><span class="sr-only"></span></button>';
        $('.pi-n', it.li).textContent = it.name;
        $('.pi-x .sr-only', it.li).textContent = 'Remove one ' + it.name;
        $('.pi-x', it.li).addEventListener('click', function () { remove(k); });
        list.appendChild(it.li);
      }
      $('.pi-q', it.li).textContent = it.q + '×';
      $('.pi-k', it.li).textContent = fmt(it.kcal * it.q) + ' kcal';
      if (motion) { it.li.classList.remove('bump'); void it.li.offsetWidth; it.li.classList.add('bump'); }
    };
    var remove = function (k) {
      var it = items[k]; if (!it) return;
      it.q--;
      if (it.q <= 0) {
        var li = it.li; delete items[k]; order.splice(order.indexOf(k), 1);
        if (motion) { li.classList.add('out'); setTimeout(function () { li.remove(); }, 260); } else li.remove();
      } else row(k);
      buzz(5); paint();
    };
    /* The chip's label flies into the rings, then the numbers roll. */
    var fly = function (chip) {
      if (!motion || !chip.animate) return;
      var a = chip.getBoundingClientRect(), b = rings.getBoundingClientRect();
      var ghost = doc.createElement('span');
      ghost.className = 'p-ghost'; ghost.setAttribute('aria-hidden', 'true');
      ghost.textContent = '+' + chip.getAttribute('data-kcal');
      ghost.style.left = (a.left + a.width / 2) + 'px'; ghost.style.top = (a.top + a.height / 2) + 'px';
      doc.body.appendChild(ghost);
      var dx = b.left + b.width / 2 - (a.left + a.width / 2), dy = b.top + b.height / 2 - (a.top + a.height / 2);
      ghost.animate([
        { transform: 'translate(-50%, -50%) scale(1)', opacity: 1 },
        { transform: 'translate(calc(-50% + ' + dx * 0.5 + 'px), calc(-50% + ' + (dy * 0.5 - 40) + 'px)) scale(1.1)', opacity: 1, offset: 0.5 },
        { transform: 'translate(calc(-50% + ' + dx + 'px), calc(-50% + ' + dy + 'px)) scale(.4)', opacity: 0 }
      ], { duration: 560, easing: 'cubic-bezier(.3,.7,.4,1)' }).onfinish = function () { ghost.remove(); rings.classList.remove('gulp'); void rings.offsetWidth; rings.classList.add('gulp'); };
    };
    $$('.pchip', plate).forEach(function (chip) {
      chip.addEventListener('click', function () {
        var k = chip.getAttribute('data-food');
        if (order.length && totals().n >= 24) return;
        if (!items[k]) {
          items[k] = { name: chip.getAttribute('data-name'), kcal: +chip.getAttribute('data-kcal'), p: +chip.getAttribute('data-p'), c: +chip.getAttribute('data-c'), f: +chip.getAttribute('data-f'), q: 0 };
          order.push(k);
        }
        items[k].q++;
        row(k); fly(chip); buzz(8);
        setTimeout(paint, motion ? 380 : 0);
      });
    });
    clear.addEventListener('click', function () {
      order.slice().forEach(function (k) { items[k].li.remove(); delete items[k]; });
      order = []; buzz(10); paint();
      $('.pchip', plate).focus();
    });
    paint();
  })();

  /* ── 4. Training: log a set, beat your best ──────────── */
  var sl = $('.setlog');
  if (sl) (function () {
    var st = { w: 40, r: 10 };
    var lim = { w: [2.5, 300], r: [1, 30] };
    var bestE = 40 * (1 + 11 / 30);
    var outs = { w: $('[data-o="w"]', sl), r: $('[data-o="r"]', sl) };
    var setsEl = $('.sl-sets', sl), bestEl = $('.sl-best', sl), prEl = $('.sl-pr', sl);
    var rest = $('.sl-rest', sl), clock = $('.sl-clock', sl), rr = $('.rr', sl);
    var n = 0, vol = 0, restEnd = 0, restT = null;
    var set = function (k, d) {
      var nv = clamp(Math.round((st[k] + d) * 10) / 10, lim[k][0], lim[k][1]);
      if (nv === st[k]) { outs[k].classList.remove('nope'); void outs[k].offsetWidth; outs[k].classList.add('nope'); buzz([6, 30, 6]); return false; }
      st[k] = nv; outs[k].textContent = fmt(nv, 1);
      if (motion) { outs[k].classList.remove('up', 'down'); void outs[k].offsetWidth; outs[k].classList.add(d > 0 ? 'up' : 'down'); }
      buzz(4);
      return true;
    };
    /* Hold a stepper and it keeps going, a little faster each time. */
    $$('.stp-b', sl).forEach(function (b) {
      var k = b.getAttribute('data-k'), d = +b.getAttribute('data-d'), rep = null, wait = null, fired = false;
      var stop = function () { clearTimeout(wait); clearInterval(rep); wait = rep = null; };
      b.addEventListener('pointerdown', function () {
        fired = false; stop();
        wait = setTimeout(function () { fired = true; rep = setInterval(function () { if (!set(k, d)) stop(); }, 90); }, 420);
      });
      ['pointerup', 'pointerleave', 'pointercancel'].forEach(function (ev) { b.addEventListener(ev, stop); });
      b.addEventListener('click', function () { if (fired) { fired = false; return; } set(k, d); });
    });
    var tickRest = function () {
      var left = Math.max(0, restEnd - Date.now());
      var s = Math.ceil(left / 1000);
      clock.textContent = Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2);
      rr.style.strokeDasharray = (left / 900).toFixed(2) + ' 100';
      if (left <= 0) { clearInterval(restT); restT = null; rest.classList.add('done'); clock.textContent = 'Go'; buzz([12, 60, 12]); }
    };
    $('.sl-skip', sl).addEventListener('click', function () { clearInterval(restT); restT = null; rest.hidden = true; });
    $('.sl-log', sl).addEventListener('click', function () {
      n++;
      var e1 = st.w * (1 + st.r / 30);
      var pr = e1 > bestE + 0.01;
      vol += st.w * st.r;
      var li = doc.createElement('li');
      li.className = 'sl-set' + (pr ? ' pr' : '');
      li.innerHTML = '<span class="sn"></span><span class="sw"></span>' + (pr ? '<span class="sb">Best</span>' : '');
      $('.sn', li).textContent = 'Set ' + n;
      $('.sw', li).textContent = fmt(st.w, 1) + ' kg × ' + st.r;
      setsEl.insertBefore(li, setsEl.firstChild);
      while (setsEl.children.length > 5) setsEl.lastChild.remove();
      roll('vol', Math.round(vol * 10) / 10, 1);
      recapState.vol = Math.round(vol * 10) / 10; recapState.sets = n;
      if (pr) {
        bestE = e1; bestEl.textContent = fmt(st.w, 1) + ' kg × ' + st.r;
        recapState.prs++;
        prEl.innerHTML = '<b>New best.</b> <span>Gravity filed a complaint.</span>';
        sl.classList.remove('pr-hit'); void sl.offsetWidth; sl.classList.add('pr-hit');
        buzz([18, 50, 28]);
      } else {
        prEl.textContent = '';
        buzz(10);
      }
      paintRecap();
      restEnd = Date.now() + 90000; rest.hidden = false; rest.classList.remove('done');
      clearInterval(restT); restT = setInterval(tickRest, 250); tickRest();
    });
  })();

  /* ── 5. Kyno on phones: a chat you can tap through ───── */
  var asks = $('.asks');
  var kCopy = $('.kyno-copy');
  if (asks && kCopy) (function () {
    var qs = $$('.ask', asks).map(function (li) {
      return { q: $('.ask-q span', li).textContent, a: $('.bubble p', li).textContent, shot: li.getAttribute('data-shot') };
    });
    var kPhones = $('.kyno-phones');
    var chat = $('.kchat', kCopy);
    if (!chat) return;
    var log = $('.kc-log', chat), chips = $('.kc-chips', chat);
    var busy = false;
    var scrollDown = function () { log.scrollTo({ top: log.scrollHeight, behavior: motion ? 'smooth' : 'auto' }); };
    var bubble = function (cls, text) {
      var b = doc.createElement('div'); b.className = 'kb ' + cls; if (text) b.textContent = text;
      log.appendChild(b); scrollDown(); return b;
    };
    var ask = function (i, chip) {
      if (busy) return;
      busy = true;
      chip.classList.add('asked'); chip.setAttribute('aria-pressed', 'true');
      chips.appendChild(chip);
      bubble('kb-u', qs[i].q);
      buzz(6);
      if (kPhones) kPhones.classList.toggle('swap', qs[i].shot === 'answer');
      var dots = bubble('kb-k kb-dots', '');
      dots.innerHTML = '<span></span><span></span><span></span>';
      dots.setAttribute('aria-label', 'Kyno is typing');
      setTimeout(function () {
        dots.remove();
        var b = bubble('kb-k', '');
        var text = qs[i].a;
        if (!motion) { b.textContent = text; busy = false; return; }
        var j = 0, step = Math.max(2, Math.ceil(text.length / 70));
        b.setAttribute('aria-busy', 'true');
        (function run() {
          j = Math.min(text.length, j + step);
          b.textContent = text.slice(0, j);
          if (j % 24 < step) log.scrollTop = log.scrollHeight;
          if (j < text.length) setTimeout(run, 18);
          else { b.removeAttribute('aria-busy'); busy = false; scrollDown(); buzz(5); }
        })();
      }, motion ? 750 : 0);
    };
    $$('.kc-chip', chat).forEach(function (c) {
      var i = +c.getAttribute('data-q');
      c.addEventListener('click', function () { ask(i, c); });
    });
    var apply = function () { kCopy.classList.toggle('chat-on', mqChat.matches); };
    if (mqChat.addEventListener) mqChat.addEventListener('change', apply);
    apply();
  })();

  /* ── 6. Share cards on phones: a deck you flick ──────── */
  var cards = $('.cards');
  if (cards) (function () {
    var lis = $$(':scope > li', cards);
    var n = lis.length, top = 0, on = false;
    var wrap = cards.parentNode;
    var nav = $('.deck-nav', wrap);
    if (!nav) return;
    var dotsEl = $('.card-dots', nav);
    var dots = lis.map(function (li, i) {
      var name = (li.querySelector('figcaption b') || {}).textContent || ('Card ' + (i + 1));
      var item = doc.createElement('li');
      var b = doc.createElement('button');
      b.type = 'button'; b.setAttribute('aria-label', 'Show the ' + name + ' card');
      b.addEventListener('click', function () { goTo(i); });
      item.appendChild(b); dotsEl.appendChild(item);
      return b;
    });
    var dist = function (i) { return (i - top + n) % n; };
    var layout = function () {
      lis.forEach(function (li, i) {
        var d = dist(i);
        li.style.setProperty('--d', d);
        li.style.zIndex = String(n - d);
        li.classList.toggle('is-top', d === 0);
        li.classList.toggle('next', d === 1);
        li.classList.toggle('deep', d >= 4);
        li.inert = on && d !== 0;
      });
      dots.forEach(function (b, i) { if (i === top) b.setAttribute('aria-current', 'true'); else b.removeAttribute('aria-current'); });
    };
    /* The top card leaves to one side; the one under it steps up. */
    var throwTop = function (dir, done) {
      var li = lis[top];
      li.classList.add('flying');
      li.style.setProperty('--tx', (dir * 130) + 'vw');
      li.style.setProperty('--tr', (dir * 24) + 'deg');
      top = (top + 1) % n; layout();
      buzz(8);
      setTimeout(function () {
        li.classList.add('tuck');
        li.classList.remove('flying');
        li.style.removeProperty('--tx'); li.style.removeProperty('--tr'); li.style.removeProperty('--ty');
        void li.offsetWidth;
        li.classList.remove('tuck');
        if (done) done();
      }, motion ? 340 : 0);
    };
    var back = function () {
      var prev = (top - 1 + n) % n, li = lis[prev];
      li.classList.add('tuck');
      li.style.setProperty('--tx', '-130vw'); li.style.setProperty('--tr', '-24deg');
      top = prev; layout();
      void li.offsetWidth;
      li.classList.remove('tuck');
      li.style.removeProperty('--tx'); li.style.removeProperty('--tr');
      buzz(8);
    };
    var goTo = function (i) {
      if (i === top) return;
      var steps = (i - top + n) % n;
      if (steps > n / 2) { var b = n - steps; while (b--) back(); return; }
      (function next(k) { if (!k) return; throwTop(-1, function () { next(k - 1); }); })(steps);
    };
    $('.dk-next', nav).addEventListener('click', function () { throwTop(-1); });
    $('.dk-prev', nav).addEventListener('click', back);
    cards.addEventListener('keydown', function (e) {
      if (!on) return;
      if (e.key === 'ArrowRight') { throwTop(-1, function () { var c = $('.is-top .card', cards); if (c) c.focus(); }); e.preventDefault(); }
      if (e.key === 'ArrowLeft') { back(); var c = $('.is-top .card', cards); if (c) c.focus(); e.preventDefault(); }
    });

    /* Drag with the finger: the card follows, tilts, and the next one rises under it. */
    var drag = null, moved = false;
    cards.addEventListener('pointerdown', function (e) {
      if (!on) return;
      var li = e.target.closest('li.is-top'); if (!li) return;
      drag = { li: li, x: e.clientX, y: e.clientY, t: now(), lx: e.clientX, lt: now(), vx: 0, axis: null };
      moved = false;
    });
    cards.addEventListener('pointermove', function (e) {
      if (!drag) return;
      var dx = e.clientX - drag.x, dy = e.clientY - drag.y;
      if (!drag.axis) {
        if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
        drag.axis = Math.abs(dx) > Math.abs(dy) ? 'x' : 'y';
        if (drag.axis === 'y') { drag = null; return; }
        try { cards.setPointerCapture(e.pointerId); } catch (err) {}
        drag.li.classList.add('dragging'); cards.classList.add('dragging');
      }
      moved = true;
      var t = now();
      drag.vx = (e.clientX - drag.lx) / Math.max(1, t - drag.lt); drag.lx = e.clientX; drag.lt = t;
      drag.li.style.setProperty('--tx', dx + 'px');
      drag.li.style.setProperty('--ty', (dy * 0.25) + 'px');
      drag.li.style.setProperty('--tr', (dx / 16) + 'deg');
      cards.style.setProperty('--lift', clamp(Math.abs(dx) / 160, 0, 1).toFixed(3));
    });
    var end = function () {
      if (!drag) return;
      var li = drag.li, dx = parseFloat(li.style.getPropertyValue('--tx')) || 0, vx = drag.vx;
      drag = null;
      li.classList.remove('dragging'); cards.classList.remove('dragging'); cards.style.removeProperty('--lift');
      if (Math.abs(dx) > 90 || Math.abs(vx) > 0.55) throwTop(dx === 0 ? (vx < 0 ? -1 : 1) : Math.sign(dx));
      else { li.style.removeProperty('--tx'); li.style.removeProperty('--ty'); li.style.removeProperty('--tr'); }
    };
    cards.addEventListener('pointerup', end);
    cards.addEventListener('pointercancel', end);
    /* A drag is not a tap: don't open the card after one. */
    cards.addEventListener('click', function (e) { if (moved) { e.preventDefault(); e.stopImmediatePropagation(); moved = false; } }, true);

    var apply = function () {
      on = mqPhone.matches;
      cards.classList.toggle('deck', on);
      nav.hidden = !on;
      if (!on) lis.forEach(function (li) { li.inert = false; li.style.removeProperty('--d'); li.style.zIndex = ''; li.classList.remove('is-top', 'next', 'deep'); });
      else layout();
    };
    if (mqPhone.addEventListener) mqPhone.addEventListener('change', apply);
    apply();

    /* Switching finish flips every card over. */
    $$('.finish button').forEach(function (b) {
      b.addEventListener('click', function () {
        if (!motion) return;
        cards.classList.remove('flip'); void cards.offsetWidth; cards.classList.add('flip');
        buzz(6);
      });
    });
  })();

  /* ── 7. The address bar follows the page (Android Chrome) ── */
  var tc = $('meta[name="theme-color"]');
  var kSec = $('#kyno');
  if (tc && kSec) {
    new IntersectionObserver(function (es) { tc.setAttribute('content', es[0].isIntersecting ? '#141416' : '#0B0B0C'); }, { rootMargin: '-50% 0px -50% 0px' }).observe(kSec);
  }

  /* ── 8. A tick under the thumb on the dock ───────────── */
  var dock = $('.dock');
  if (dock) dock.addEventListener('click', function (e) { if (e.target.closest('a, button')) buzz(6); });
})();
