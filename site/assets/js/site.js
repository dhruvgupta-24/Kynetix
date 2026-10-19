/* Kynetix site: the Shear cut, the dock, Kyno, the cursor. No dependencies. */
(function () {
  'use strict';
  var root = document.documentElement;
  var doc = document;
  var mqReduce = window.matchMedia('(prefers-reduced-motion: reduce)');
  var mqFine = window.matchMedia('(hover: hover) and (pointer: fine)');
  var motion = !mqReduce.matches && 'IntersectionObserver' in window;
  if (motion) root.classList.add('motion');
  var $ = function (s, c) { return (c || doc).querySelector(s); };
  var $$ = function (s, c) { return Array.prototype.slice.call((c || doc).querySelectorAll(s)); };
  var clamp = function (v, a, b) { return Math.min(b, Math.max(a, v)); };
  var now = function () { return (window.performance && performance.now()) || Date.now(); };

  /* ── Shear headlines ─────────────────────────────────── */
  var shears = $$('.shear');
  shears.forEach(function (el) {
    if (el.querySelector('.sh-b')) return;
    var text = el.textContent.replace(/\s+/g, ' ').trim();
    el.textContent = '';
    var b = doc.createElement('span'); b.className = 'sh-b'; b.textContent = text;
    var t = doc.createElement('span'); t.className = 'sh-t'; t.textContent = text; t.setAttribute('aria-hidden', 'true');
    var blade = doc.createElement('span'); blade.className = 'blade'; blade.setAttribute('aria-hidden', 'true');
    el.appendChild(b); el.appendChild(t); el.appendChild(blade);
  });

  /* ── Reveals: once, never re-hidden ──────────────────── */
  var onReveal = [];
  var revealables = shears.concat($$('[data-reveal]'));
  if (motion) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        e.target.classList.add('is-in'); io.unobserve(e.target);
        onReveal.forEach(function (fn) { fn(e.target); });
      });
    }, { rootMargin: '0px 0px -12% 0px', threshold: 0.12 });
    revealables.forEach(function (el) { io.observe(el); });
  } else {
    revealables.forEach(function (el) { el.classList.add('is-in'); });
  }

  /* ── Navigation: island on desktop, dock on phones ───── */
  var top = $('.top');
  var island = $('.island');
  var dock = $('.dock');
  var navs = [$('.links'), dock].filter(Boolean);
  var secIds = ['food', 'training', 'widgets', 'kyno', 'share'];
  var secEls = secIds.map(function (id) { return doc.getElementById(id); });
  var onHome = secEls.every(Boolean);
  var shareEnd = onHome ? doc.getElementById('share') : null;

  function placeInd(nav) {
    var ind = $('.ind', nav);
    if (!ind) return;
    var on = $('.on', nav);
    if (!on || !nav.offsetParent && getComputedStyle(nav).position !== 'fixed') { ind.classList.remove('show'); return; }
    var fresh = !ind.classList.contains('show');
    if (fresh) ind.classList.add('instant');
    ind.style.setProperty('--x', on.offsetLeft + 'px');
    ind.style.setProperty('--w', on.offsetWidth + 'px');
    ind.classList.add('show');
    if (fresh) { void ind.offsetWidth; ind.classList.remove('instant'); }
  }
  function placeAll() { navs.forEach(placeInd); }

  var activeSec = null;
  function setActive(id) {
    if (id === activeSec) return;
    activeSec = id;
    navs.forEach(function (nav) {
      $$('[data-sec]', nav).forEach(function (a) {
        var on = a.getAttribute('data-sec') === id;
        a.classList.toggle('on', on);
        if (on) a.setAttribute('aria-current', 'location'); else a.removeAttribute('aria-current');
      });
    });
    placeAll();
  }
  if ('ResizeObserver' in window) {
    var ro = new ResizeObserver(function () { placeAll(); });
    navs.forEach(function (nav) { $$('a, button', nav).forEach(function (el) { ro.observe(el); }); });
  }
  window.addEventListener('resize', placeAll);
  if (doc.fonts && doc.fonts.ready) doc.fonts.ready.then(placeAll);

  /* ── Scroll loop ─────────────────────────────────────── */
  var lastY = window.scrollY;
  var hero = $('.hero');
  var wmTop = $('.hero .wm-scroll');
  var heroPhones = $$('.hero-phones .phone');
  var fan = $('.cards');
  var ticking = false;
  var compact = false;

  function onScroll() {
    ticking = false;
    var y = window.scrollY;
    var vh = window.innerHeight;
    var dy = y - lastY;
    var focusInside = island && island.contains(doc.activeElement) && doc.activeElement !== doc.body;
    if (y < 160 || focusInside) compact = false;
    else if (dy > 4) compact = true;
    else if (dy < -4) compact = false;
    if (top) top.classList.toggle('compact', compact);
    if (dock) dock.classList.toggle('compact', compact);
    lastY = y;
    var max = Math.max(1, doc.documentElement.scrollHeight - vh);
    if (island) island.style.setProperty('--prog', clamp(y / max, 0, 1).toFixed(4));

    if (onHome) {
      var probe = vh * 0.4;
      var id = null;
      for (var i = 0; i < secEls.length; i++) if (secEls[i].getBoundingClientRect().top <= probe) id = secIds[i];
      if (shareEnd && shareEnd.getBoundingClientRect().bottom < probe) id = null;
      setActive(id);
    }
    if (!motion) return;
    if (hero && wmTop && y < vh * 1.5) {
      var p = clamp(y / (vh * 0.9), 0, 1);
      wmTop.setAttribute('transform', 'translate(' + (p * 420).toFixed(1) + ' 0)');
      for (var j = 0; j < heroPhones.length; j++) {
        heroPhones[j].style.setProperty('--py', (y * (j === 1 ? -0.16 : -0.08)).toFixed(1) + 'px');
      }
    }
    if (fan && window.innerWidth >= 980) {
      var r = fan.getBoundingClientRect();
      /* Far away the fan keeps its resting spread (CSS default), so the cards never sit stacked out of sight. */
      if (r.top > vh * 1.6 || r.bottom < -vh) { fan.style.removeProperty('--p'); } else
      fan.style.setProperty('--p', clamp((vh - r.top) / (vh * 0.75), 0, 1).toFixed(3));
    }
  }
  window.addEventListener('scroll', function () {
    if (!ticking) { ticking = true; requestAnimationFrame(onScroll); }
  }, { passive: true });
  onScroll();
  placeAll();

  /* ── Full-screen menu ────────────────────────────────── */
  var menu = $('#menu');
  var menuBtn = $('.menu-btn');
  var cursorHome = null;
  /* Dialogs sit in the top layer, above the custom cursor: use the native one there. */
  var dialogOpen = false;
  function moveCursorInto() { dialogOpen = true; if (cursorHome && cursorHome.el) { cursorHome.el.classList.remove('live'); root.classList.remove('cursor-on'); } }
  function cursorBack() { dialogOpen = false; }
  function closeMenu(after) {
    if (!menu || !menu.open) { if (after) after(); return; }
    var done = function () {
      menu.classList.remove('closing'); menu.close();
      if (after) after();
    };
    if (motion) { menu.classList.add('closing'); setTimeout(done, 360); } else done();
  }
  if (menu && menuBtn && menu.showModal) {
    menuBtn.addEventListener('click', function () {
      menu.showModal(); $('.menu-x', menu).focus(); menuBtn.setAttribute('aria-expanded', 'true'); moveCursorInto(menu);
    });
    menu.addEventListener('close', function () {
      menuBtn.setAttribute('aria-expanded', 'false');
      cursorBack();
    });
    menu.addEventListener('cancel', function (e) { e.preventDefault(); closeMenu(); });
    $('.menu-x', menu).addEventListener('click', function () { closeMenu(); });
    $$('a', menu).forEach(function (a) {
      a.addEventListener('click', function (e) {
        var u = new URL(a.href, location.href);
        if (u.pathname === location.pathname && u.hash) {
          e.preventDefault();
          closeMenu(function () {
            var t = doc.getElementById(u.hash.slice(1));
            if (t) { t.scrollIntoView({ behavior: motion ? 'smooth' : 'auto' }); history.replaceState(null, '', u.hash); }
          });
        }
      });
    });
  } else if (menuBtn) {
    menuBtn.hidden = true;
  }

  /* ── Hero: pointer tilt on the phones ────────────────── */
  function tiltOn(area, targets, rx, ry) {
    if (!area || !motion || !mqFine.matches) return;
    area.addEventListener('pointermove', function (e) {
      var r = area.getBoundingClientRect();
      var x = (e.clientX - r.left) / r.width - 0.5;
      var y = (e.clientY - r.top) / r.height - 0.5;
      targets.forEach(function (t) {
        t.style.setProperty('--rx', (-y * rx).toFixed(2) + 'deg');
        t.style.setProperty('--ry', (x * ry).toFixed(2) + 'deg');
      });
    });
    area.addEventListener('pointerleave', function () {
      targets.forEach(function (t) { t.style.setProperty('--rx', '0deg'); t.style.setProperty('--ry', '0deg'); });
    });
  }
  tiltOn(hero, heroPhones, 6, 10);
  tiltOn($('.stick-inner'), $$('.stick .tilt'), 5, 9);

  /* ── Product story: the sticky phone swaps with a cut ── */
  var stick = $('.stick');
  if (stick && 'IntersectionObserver' in window) {
    var scrs = $$('.scr', stick);
    var dots = $$('.dots li', stick);
    var slash = $('.slash', stick);
    var current = 0;
    var show = function (n) {
      if (n === current || !scrs[n]) return;
      scrs.forEach(function (s) { s.classList.remove('was', 'cutting'); });
      scrs[current].classList.add('was');
      scrs[current].classList.remove('on');
      scrs[n].classList.add('on');
      dots.forEach(function (d, i) { d.classList.toggle('on', i === n); });
      if (motion) {
        void scrs[n].offsetWidth;
        scrs[n].classList.add('cutting');
        if (slash) { slash.classList.remove('go'); void slash.offsetWidth; slash.classList.add('go'); }
      }
      current = n;
    };
    var cio = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) show(+e.target.getAttribute('data-screen')); });
    }, { rootMargin: '-45% 0px -45% 0px' });
    $$('.chapter[data-screen]').forEach(function (c) { cio.observe(c); });
  }

  /* ── Describe-it demo ────────────────────────────────── */
  var typed = $('.typed');
  if (typed && motion) {
    var lines = (typed.getAttribute('data-lines') || '').split('|');
    if (lines.length > 1) {
      var li = 0, ci = 0, del = false, visible = false, timer = null;
      var tick = function () {
        if (!visible) { timer = null; return; }
        var s = lines[li];
        if (!del) {
          ci++;
          typed.firstChild.nodeValue = s.slice(0, ci);
          if (ci >= s.length) { del = true; timer = setTimeout(tick, 1900); return; }
          timer = setTimeout(tick, 42 + Math.random() * 60);
        } else {
          ci -= 2;
          if (ci <= 0) { ci = 0; del = false; li = (li + 1) % lines.length; typed.firstChild.nodeValue = ''; timer = setTimeout(tick, 380); return; }
          typed.firstChild.nodeValue = s.slice(0, ci);
          timer = setTimeout(tick, 18);
        }
      };
      typed.firstChild.nodeValue = '';
      new IntersectionObserver(function (entries) {
        visible = entries[0].isIntersecting;
        if (visible && !timer) tick();
      }).observe(typed);
    }
  }

  /* ── Kyno: answers open on hover, tap, click or focus ── */
  var asksList = $('.asks');
  if (asksList) {
    var asks = $$('.ask', asksList);
    var kPhones = $('.kyno-phones');
    var openAsk = null, lockUntil = 0, pending = null, intent = null, hovered = null, hoverOpenedAt = 0;
    asks.forEach(function (li) { $('.ask-a', li).inert = true; });

    var typeIn = function (li) {
      var bubble = $('.bubble', li);
      var p = $('p', bubble);
      var old = $('.typer', bubble);
      if (old) old.remove();
      if (li._typing) { clearTimeout(li._typing); li._typing = null; }
      bubble.classList.remove('typing');
      if (!motion) return;
      var text = p.textContent;
      var typer = doc.createElement('div');
      typer.className = 'typer'; typer.setAttribute('aria-hidden', 'true');
      typer.innerHTML = '<span class="dots3"><span></span><span></span><span></span></span>';
      bubble.appendChild(typer);
      bubble.classList.add('typing');
      var i = 0;
      var step = Math.max(2, Math.ceil(text.length / 55));
      var run = function () {
        i = Math.min(text.length, i + step);
        typer.textContent = text.slice(0, i);
        if (i < text.length) li._typing = setTimeout(run, 16);
        else { li._typing = null; typer.remove(); bubble.classList.remove('typing'); }
      };
      li._typing = setTimeout(run, 420);
    };
    var setOpen = function (li) {
      if (li === openAsk) return;
      if (openAsk) {
        openAsk.classList.remove('open');
        $('.ask-q', openAsk).setAttribute('aria-expanded', 'false');
        $('.ask-a', openAsk).inert = true;
      }
      openAsk = li;
      if (li) {
        li.classList.add('open');
        $('.ask-q', li).setAttribute('aria-expanded', 'true');
        $('.ask-a', li).inert = false;
        typeIn(li);
      }
      asksList.classList.toggle('has-open', !!li);
      if (kPhones) kPhones.classList.toggle('swap', !!li && li.getAttribute('data-shot') === 'answer');
      lockUntil = now() + 480;
    };
    var tryOpen = function () {
      intent = null;
      if (!pending || pending !== hovered) return;
      var wait = lockUntil - now();
      if (wait > 0) { intent = setTimeout(tryOpen, wait + 20); return; }
      setOpen(pending); hoverOpenedAt = now(); pending = null;
    };
    asks.forEach(function (li) {
      var btn = $('.ask-q', li);
      btn.addEventListener('click', function () {
        if (openAsk === li && now() - hoverOpenedAt < 700) return; /* hover just opened it: keep it */
        setOpen(openAsk === li ? null : li);
        hoverOpenedAt = 0;
      });
      btn.addEventListener('focus', function () {
        var fv = true;
        try { fv = btn.matches(':focus-visible'); } catch (e) {}
        if (fv) setOpen(li);
      });
    });
    asksList.addEventListener('pointermove', function (e) {
      if (e.pointerType !== 'mouse' || !mqFine.matches) return;
      var li = e.target.closest('.ask');
      hovered = li;
      if (!li || li === openAsk) { pending = null; return; }
      if (li !== pending) { pending = li; clearTimeout(intent); intent = setTimeout(tryOpen, 140); }
    });
    asksList.addEventListener('pointerleave', function () { hovered = null; pending = null; clearTimeout(intent); });
    /* The first answer is already showing when the list arrives. */
    var opened = false;
    var openFirst = function () { if (!opened && !openAsk) { opened = true; setOpen(asks[0]); } };
    if (motion) onReveal.push(function (el) { if (el === asksList) setTimeout(openFirst, 500); });
    else openFirst();
  }

  /* ── Widgets: the home screen assembles as you scroll (wide screens,
     fine pointer, motion allowed). Everywhere else it is a still grid. ── */
  var wsec = doc.getElementById('widgets');
  if (wsec) {
    var mqPin = window.matchMedia('(min-width: 1100px) and (min-height: 680px) and (hover: hover) and (pointer: fine)');
    var wTrack = $('.wg-track', wsec);
    var wGrid = $('.wg', wsec);
    var wView = $('.wg-view', wsec);
    var wTiles = $$('.wg-tile[data-step]', wsec);
    var wSlots = $$('.wg-slot', wsec);
    var wSteps = $$('.wg-steps li', wsec);
    var wBtns = $$('.wg-steps button', wsec);
    var wProg = $('.wg-prog', wsec);
    var wPinned = false, wLanded = null;
    var STEP0 = 0.08, STEP = 0.19;
    var wLand = function (n) {
      if (n === wLanded) return;
      wLanded = n;
      wTiles.forEach(function (t) { t.classList.toggle('in', +t.getAttribute('data-step') <= n); });
      wSlots.forEach(function (s) {
        var k = +s.getAttribute('data-step');
        s.classList.toggle('in', k <= n);
        s.classList.toggle('next', k === n + 1);
      });
      wSteps.forEach(function (li, i) {
        li.classList.toggle('on', wPinned && i === n);
        li.classList.toggle('done', wPinned && i < n);
      });
      wGrid.classList.toggle('cut-in', n >= 0);
    };
    var wUpdate = function () {
      if (!wPinned) return;
      var r = wTrack.getBoundingClientRect();
      var total = Math.max(1, r.height - window.innerHeight);
      var p = clamp(-r.top / total, 0, 1);
      if (wProg) wProg.style.setProperty('--p', p.toFixed(4));
      wLand(p < STEP0 ? -1 : Math.min(3, Math.floor((p - STEP0) / STEP)));
    };
    var wApply = function () {
      var want = motion && mqPin.matches;
      wPinned = want;
      wsec.classList.toggle('wg-pin', want);
      wBtns.forEach(function (b) { b.disabled = !want; });
      wLanded = null;
      if (want) wUpdate(); else wLand(3);
    };
    wBtns.forEach(function (b) {
      b.addEventListener('click', function () {
        if (!wPinned) return;
        var i = +b.getAttribute('data-step');
        var top = wTrack.getBoundingClientRect().top + window.scrollY;
        var total = wTrack.offsetHeight - window.innerHeight;
        window.scrollTo({ top: top + total * (STEP0 + STEP * i + STEP * 0.5), behavior: 'smooth' });
      });
    });
    var wTick = false;
    window.addEventListener('scroll', function () {
      if (!wPinned || wTick) return;
      wTick = true;
      requestAnimationFrame(function () { wTick = false; wUpdate(); });
    }, { passive: true });
    window.addEventListener('resize', wUpdate);
    if (mqPin.addEventListener) mqPin.addEventListener('change', wApply);
    wApply();

    /* Pointer tilt, at most 5 degrees, with a sheen that slides the other way. */
    if (motion && wView) {
      wView.addEventListener('pointermove', function (e) {
        if (!wPinned || e.pointerType !== 'mouse') return;
        var r = wGrid.getBoundingClientRect();
        var x = clamp((e.clientX - r.left) / r.width - 0.5, -0.5, 0.5);
        var y = clamp((e.clientY - r.top) / r.height - 0.5, -0.5, 0.5);
        wGrid.style.setProperty('--rx', (-y * 8).toFixed(2) + 'deg');
        wGrid.style.setProperty('--ry', (x * 10).toFixed(2) + 'deg');
        wGrid.style.setProperty('--gx', (50 - x * 90).toFixed(1) + '%');
      });
      wView.addEventListener('pointerleave', function () {
        wGrid.style.setProperty('--rx', '0deg'); wGrid.style.setProperty('--ry', '0deg'); wGrid.style.setProperty('--gx', '50%');
      });
    }
  }

  /* ── Share cards: graphite / paper finish ────────────── */
  var finish = $('.finish');
  if (finish) {
    finish.hidden = false;
    var finBtns = $$('button', finish);
    finBtns.forEach(function (fb) {
      fb.addEventListener('click', function () {
        var f = fb.getAttribute('data-finish');
        finBtns.forEach(function (x) { x.setAttribute('aria-pressed', String(x === fb)); });
        $$('.card[data-base]').forEach(function (c) {
          var base = (f === 'paper' && c.getAttribute('data-paper')) || c.getAttribute('data-base');
          var img = $('img', c);
          img.srcset = base + '-360.webp 360w, ' + base + '-720.webp 720w';
          img.src = base + '-360.webp';
          c.setAttribute('data-full', base + '-720.webp');
        });
      });
    });
  }

  /* ── Share cards: lightbox ───────────────────────────── */
  var lb = $('#lightbox');
  if (lb && lb.showModal) {
    var lbImg = $('img', lb), lbCap = $('.lb-cap', lb);
    $$('.card[data-full]').forEach(function (c) {
      c.addEventListener('click', function () {
        var img = $('img', c);
        lbImg.src = c.getAttribute('data-full');
        lbImg.alt = img.alt;
        lbImg.classList.toggle('sticker', c.classList.contains('sticker'));
        var fig = c.closest('figure');
        var cap = fig && fig.querySelector('figcaption');
        lbCap.textContent = cap ? cap.querySelector('b').textContent + '. ' + cap.querySelector('span').textContent : '';
        lb.showModal(); moveCursorInto(lb);
      });
    });
    $('.lb-x', lb).addEventListener('click', function () { lb.close(); });
    lb.addEventListener('click', function (e) { if (e.target === lb) lb.close(); });
    lb.addEventListener('close', cursorBack);
  } else {
    $$('.card[data-full]').forEach(function (c) { c.addEventListener('click', function () { window.open(c.getAttribute('data-full'), '_blank'); }); });
  }

  /* ── Custom cursor: one transform per frame for dot and ring together ── */
  if (motion && mqFine.matches) {
    var cur = doc.createElement('div');
    cur.className = 'cur'; cur.setAttribute('aria-hidden', 'true');
    cur.innerHTML = '<div class="cur-ring"></div><div class="cur-bar"></div><div class="cur-beam"></div><div class="cur-fill"><span class="cur-lb"></span></div><div class="cur-dot"></div>';
    doc.body.appendChild(cur);
    cursorHome = { el: cur };
    var lbl = $('.cur-lb', cur);
    var px = -100, py = -100, raf = null, state = '', snapEl = null;
    var paint = function () {
      raf = null;
      cur.style.transform = 'translate3d(' + px + 'px,' + py + 'px,0)';
      if (snapEl) {
        var r = snapEl.getBoundingClientRect();
        cur.style.setProperty('--sx', ((r.left + r.width / 2 - px) * 0.3).toFixed(1) + 'px');
        cur.style.setProperty('--sy', ((r.top + r.height / 2 - py) * 0.3).toFixed(1) + 'px');
      }
    };
    var textSel = 'p, li, h1, h2, h3, dd, dt, td, th, figcaption, code, small, blockquote, input, textarea';
    var btnSel = 'button, [data-magnetic], .btn, .menu-x, .lb-x';
    var setState = function (s, el) {
      snapEl = s === 'btn' ? el : null;
      if (s === state) return;
      state = s;
      cur.classList.toggle('is-link', s === 'link');
      cur.classList.toggle('is-btn', s === 'btn');
      cur.classList.toggle('is-label', s === 'label');
      cur.classList.toggle('is-text', s === 'text');
    };
    var classify = function (t) {
      if (!(t instanceof Element)) return setState('');
      var lab = t.closest('[data-cursor]');
      if (lab) { lbl.textContent = lab.getAttribute('data-cursor'); return setState('label'); }
      var btn = t.closest(btnSel);
      if (btn && !btn.closest('.links, .dock, .asks')) return setState('btn', btn);
      if (t.closest('a, button, summary, label, [role="button"]')) return setState('link');
      if (t.closest(textSel)) return setState('text');
      setState('');
    };
    doc.addEventListener('pointermove', function (e) {
      if (e.pointerType !== 'mouse' || dialogOpen) { cur.classList.remove('live'); root.classList.remove('cursor-on'); return; }
      px = e.clientX; py = e.clientY;
      if (!cur.classList.contains('live')) { cur.classList.add('live'); root.classList.add('cursor-on'); classify(e.target); }
      if (!raf) raf = requestAnimationFrame(paint);
    }, { passive: true });
    doc.addEventListener('pointerover', function (e) { if (e.pointerType === 'mouse') classify(e.target); });
    window.addEventListener('scroll', function () {
      if (!cur.classList.contains('live')) return;
      classify(doc.elementFromPoint(px, py));
      if (!raf) raf = requestAnimationFrame(paint);
    }, { passive: true });
    doc.addEventListener('pointerdown', function () { cur.classList.add('down'); });
    doc.addEventListener('pointerup', function () { cur.classList.remove('down'); });
    doc.addEventListener('mouseout', function (e) { if (!e.relatedTarget) { cur.classList.remove('live'); root.classList.remove('cursor-on'); } });
    window.addEventListener('blur', function () { cur.classList.remove('live'); root.classList.remove('cursor-on'); });
  }

  /* ── Magnetic badges and links ───────────────────────── */
  if (motion && mqFine.matches) {
    $$('[data-magnetic], .btn').forEach(function (el) {
      el.addEventListener('pointermove', function (e) {
        var r = el.getBoundingClientRect();
        var x = clamp((e.clientX - (r.left + r.width / 2)) * 0.18, -8, 8);
        var y = clamp((e.clientY - (r.top + r.height / 2)) * 0.3, -6, 6);
        el.style.setProperty('--mx', x.toFixed(1) + 'px');
        el.style.setProperty('--my', y.toFixed(1) + 'px');
      });
      el.addEventListener('pointerleave', function () { el.style.setProperty('--mx', '0px'); el.style.setProperty('--my', '0px'); });
    });
  }

  /* ── Legal pages: an "On this page" list that follows you ── */
  var toc = $('.toc');
  var tocLinks = $$('.toc a[href^="#"]');
  if (toc && tocLinks.length) {
    var det = $('details', toc);
    var nowEl = $('.t-now', toc);
    var list = $('ol', toc);
    var heads = tocLinks.map(function (a) { return doc.getElementById(decodeURIComponent(a.hash.slice(1))); });
    var mqWide = window.matchMedia('(min-width: 1000px)');
    var forced = -1, activeIdx = -1;
    var syncOpen = function () { if (det) det.open = mqWide.matches; };
    syncOpen();
    if (mqWide.addEventListener) mqWide.addEventListener('change', syncOpen);

    var mark = function (idx) {
      if (idx === activeIdx) return;
      activeIdx = idx;
      tocLinks.forEach(function (a, i) {
        a.classList.toggle('on', i === idx);
        if (i === idx) a.setAttribute('aria-current', 'location'); else a.removeAttribute('aria-current');
      });
      if (nowEl) nowEl.textContent = idx >= 0 ? tocLinks[idx].textContent : '';
      var a = tocLinks[idx];
      if (a && list && list.scrollHeight > list.clientHeight) {
        var lt = a.offsetTop - list.offsetTop, lh = a.offsetHeight;
        if (lt < list.scrollTop + 8) list.scrollTop = lt - 8;
        else if (lt + lh > list.scrollTop + list.clientHeight - 8) list.scrollTop = lt + lh - list.clientHeight + 8;
      }
    };
    var compute = function () {
      if (forced >= 0) { mark(forced); return; }
      var line = (parseFloat(getComputedStyle(root).scrollPaddingTop) || 0) + (heads[0] ? parseFloat(getComputedStyle(heads[0]).scrollMarginTop) || 0 : 0) + 24;
      var idx = 0;
      for (var i = 0; i < heads.length; i++) {
        if (heads[i] && heads[i].getBoundingClientRect().top <= line) idx = i;
      }
      var se = doc.scrollingElement || doc.documentElement;
      if (window.innerHeight + window.scrollY >= se.scrollHeight - 4) idx = heads.length - 1;
      mark(idx);
    };
    /* A clicked item stays lit while the page glides there (and if the last
       sections are too short to reach the top), until the reader moves on. */
    var settledY = null, settleT = null;
    var tocTick = false;
    window.addEventListener('scroll', function () {
      if (forced >= 0) {
        if (settledY === null) { clearTimeout(settleT); settleT = setTimeout(function () { settledY = window.scrollY; }, 180); }
        else if (Math.abs(window.scrollY - settledY) > 40) { forced = -1; settledY = null; }
      }
      if (!tocTick) { tocTick = true; requestAnimationFrame(function () { tocTick = false; compute(); }); }
    }, { passive: true });
    window.addEventListener('resize', compute);
    var release = function () { forced = -1; settledY = null; };
    ['wheel', 'touchstart', 'keydown'].forEach(function (ev) { window.addEventListener(ev, function () { if (settledY !== null) release(); }, { passive: true }); });
    tocLinks.forEach(function (a, i) {
      a.addEventListener('click', function () {
        forced = i; settledY = null; mark(i);
        clearTimeout(settleT); settleT = setTimeout(function () { if (settledY === null) settledY = window.scrollY; }, 1200);
        if (!mqWide.matches && det) det.open = false;
      });
    });
    doc.addEventListener('click', function (e) {
      if (det && det.open && !mqWide.matches && !toc.contains(e.target)) det.open = false;
    });
    compute();
  }

  /* ── Page transition: two halves meet at the cut ─────── */
  var wipe = null;
  var makeWipe = function (cls) {
    var w = doc.createElement('div');
    w.className = 'wipe ' + cls; w.setAttribute('aria-hidden', 'true');
    w.innerHTML = '<i></i><i></i><b></b>';
    doc.body.appendChild(w);
    return w;
  };
  if (root.classList.contains('wiping')) {
    wipe = makeWipe('cover');
    root.classList.remove('wiping');
    requestAnimationFrame(function () { requestAnimationFrame(function () {
      wipe.classList.remove('cover'); wipe.classList.add('out');
      setTimeout(function () { if (wipe) { wipe.remove(); wipe = null; } }, 800);
    }); });
  }
  if (motion) {
    doc.addEventListener('click', function (e) {
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      var a = e.target.closest && e.target.closest('a[href]');
      if (!a || a.target || a.hasAttribute('download')) return;
      var u;
      try { u = new URL(a.href, location.href); } catch (err) { return; }
      if (u.origin !== location.origin) return;
      if (u.pathname === location.pathname) return;
      e.preventDefault();
      try { sessionStorage.setItem('kx-wipe', '1'); } catch (err) {}
      var w = makeWipe('');
      void w.offsetWidth;
      w.classList.add('in');
      setTimeout(function () { location.href = u.href; }, 440);
    });
    window.addEventListener('pageshow', function (e) {
      if (e.persisted) $$('.wipe').forEach(function (w) { w.remove(); });
    });
  }

  /* If reduced motion is switched on mid-visit, settle everything. */
  if (mqReduce.addEventListener) mqReduce.addEventListener('change', function (e) {
    if (e.matches) {
      root.classList.remove('motion', 'cursor-on');
      revealables.forEach(function (el) { el.classList.add('is-in'); });
      var c = $('.cur'); if (c) c.remove();
    }
  });
})();
