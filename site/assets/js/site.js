/* Kynetix site: the Shear cut, scroll story, small demos. No dependencies. */
(function () {
  'use strict';
  var root = document.documentElement;
  var mq = window.matchMedia('(prefers-reduced-motion: reduce)');
  var motion = !mq.matches && 'IntersectionObserver' in window;
  if (motion) root.classList.add('motion');

  /* Build every .shear headline: real text below the cut, an aria-hidden
     copy above it, and the ember blade. */
  var shears = Array.prototype.slice.call(document.querySelectorAll('.shear'));
  shears.forEach(function (el) {
    if (el.querySelector('.sh-b')) return;
    var text = el.textContent.replace(/\s+/g, ' ').trim();
    el.textContent = '';
    var b = document.createElement('span'); b.className = 'sh-b'; b.textContent = text;
    var t = document.createElement('span'); t.className = 'sh-t'; t.textContent = text; t.setAttribute('aria-hidden', 'true');
    var blade = document.createElement('span'); blade.className = 'blade'; blade.setAttribute('aria-hidden', 'true');
    el.appendChild(b); el.appendChild(t); el.appendChild(blade);
  });

  /* Cut each headline once, when it is well into view. */
  if (motion) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('is-in'); io.unobserve(e.target); }
      });
    }, { rootMargin: '0px 0px -18% 0px', threshold: 0.2 });
    shears.forEach(function (el) { io.observe(el); });
    document.querySelectorAll('[data-in]').forEach(function (el) { io.observe(el); });
  } else {
    shears.forEach(function (el) { el.classList.add('is-in'); });
    document.querySelectorAll('[data-in]').forEach(function (el) { el.classList.add('is-in'); });
  }

  /* Header: solid once the page moves, tucks away while reading down. */
  var top = document.querySelector('.top');
  var lastY = window.scrollY;
  var hero = document.querySelector('.hero');
  var wmTop = document.querySelector('.hero .wm-scroll');
  var phones = document.querySelectorAll('.hero-phones .phone');
  var fan = document.querySelector('.cards');
  var ticking = false;

  function onScroll() {
    ticking = false;
    var y = window.scrollY;
    if (top) {
      top.classList.toggle('solid', y > 24);
      if (y > 480 && y - lastY > 4) top.classList.add('tucked');
      else if (lastY - y > 4 || y < 480) top.classList.remove('tucked');
    }
    lastY = y;
    if (!motion) return;
    var vh = window.innerHeight;
    if (hero && wmTop) {
      /* Scrolling away cuts the wordmark further: the top half keeps sliding. */
      var p = Math.min(1, Math.max(0, y / (vh * 0.9)));
      wmTop.setAttribute('transform', 'translate(' + (p * 420).toFixed(1) + ' 0)');
      for (var i = 0; i < phones.length; i++) {
        var rate = i === 1 ? -0.16 : -0.08;
        phones[i].style.setProperty('--py', (y * rate).toFixed(1) + 'px');
      }
    }
    if (fan && window.innerWidth >= 980) {
      var r = fan.getBoundingClientRect();
      var q = (vh - r.top) / (vh * 0.75);
      fan.style.setProperty('--p', Math.min(1, Math.max(0, q)).toFixed(3));
    }
  }
  window.addEventListener('scroll', function () {
    if (!ticking) { ticking = true; requestAnimationFrame(onScroll); }
  }, { passive: true });
  onScroll();

  /* Product story: the sticky phone swaps screens with a cut. */
  var stick = document.querySelector('.stick');
  if (stick && 'IntersectionObserver' in window) {
    var scrs = stick.querySelectorAll('.scr');
    var slash = stick.querySelector('.slash');
    var current = 0;
    var show = function (n) {
      if (n === current || !scrs[n]) return;
      scrs.forEach(function (s) { s.classList.remove('was', 'cutting'); });
      scrs[current].classList.add('was');
      scrs[current].classList.remove('on');
      scrs[n].classList.add('on');
      if (motion) {
        void scrs[n].offsetWidth;
        scrs[n].classList.add('cutting');
        if (slash) { slash.classList.remove('go'); void slash.offsetWidth; slash.classList.add('go'); }
      }
      current = n;
      document.querySelectorAll('.nav a[data-ch]').forEach(function (a) { a.classList.remove('on'); });
    };
    var cio = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) show(+e.target.getAttribute('data-screen'));
      });
    }, { rootMargin: '-45% 0px -45% 0px' });
    document.querySelectorAll('.chapter[data-screen]').forEach(function (c) { cio.observe(c); });
  }

  /* Describe-it demo: types meals the way people actually write them. */
  var typed = document.querySelector('.typed');
  if (typed) {
    var lines = (typed.getAttribute('data-lines') || '').split('|');
    if (motion && lines.length > 1) {
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

  /* Legal pages: highlight the section being read. */
  var tocLinks = document.querySelectorAll('.toc a[href^="#"]');
  if (tocLinks.length && 'IntersectionObserver' in window) {
    var map = {};
    tocLinks.forEach(function (a) { map[a.getAttribute('href').slice(1)] = a; });
    var tio = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting && map[e.target.id]) {
          tocLinks.forEach(function (a) { a.classList.remove('on'); });
          map[e.target.id].classList.add('on');
        }
      });
    }, { rootMargin: '-15% 0px -75% 0px' });
    document.querySelectorAll('.prose h2[id]').forEach(function (h) { tio.observe(h); });
    var det = document.querySelector('.toc details');
    if (det && window.matchMedia('(min-width: 1000px)').matches) det.open = true;
  }

  /* If the person turns on reduced motion mid-visit, settle everything. */
  if (mq.addEventListener) mq.addEventListener('change', function (e) {
    if (e.matches) {
      root.classList.remove('motion');
      shears.forEach(function (el) { el.classList.add('is-in'); });
    }
  });
})();
