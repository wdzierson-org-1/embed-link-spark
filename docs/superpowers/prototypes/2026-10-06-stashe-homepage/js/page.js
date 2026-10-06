/* Shared helpers for the Stash homepage prototype: spot colour, deep links, timelines that
   can pause and cancel, in-view tracking, copy buttons. Everything hangs off window.Stash. */
(() => {
  const S = (window.Stash = {});
  const root = document.documentElement;
  const params = new URLSearchParams(location.hash.replace(/^#/, ''));
  const motionQuery = matchMedia('(prefers-reduced-motion: reduce)');

  S.param = (key) => params.get(key);
  S.still = params.has('still');
  S.reduced = () => S.still || motionQuery.matches;
  S.clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  S.css = (name) => getComputedStyle(root).getPropertyValue(name).trim();

  /* Spot colour (lime / violet). Canvases listen through S.onSpot. */
  const spotListeners = [];
  S.onSpot = (fn) => spotListeners.push(fn);
  S.setSpot = (spot) => {
    root.dataset.spot = spot;
    document.querySelectorAll('[data-spot-btn]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.spotBtn === spot)));
    spotListeners.forEach((fn) => fn(spot));
  };
  document.querySelectorAll('[data-spot-btn]').forEach((b) => b.addEventListener('click', () => S.setSpot(b.dataset.spotBtn)));
  if (S.param('spot') === 'violet') S.setSpot('violet');

  /* Timelines: a token per run; wait() resolves after `ms` of *unpaused* time and throws
     S.CANCEL once the run has been superseded. */
  S.CANCEL = Symbol('cancel');
  S.token = () => ({ cancelled: false, paused: false, hidden: false });
  S.wait = async (ms, tok) => {
    let left = ms;
    while (left > 0) {
      const step = Math.min(left, 40);
      await new Promise((r) => setTimeout(r, step));
      if (tok.cancelled) throw S.CANCEL;
      if (!tok.paused && !tok.hidden) left -= step;
    }
  };
  S.frame = () => new Promise((r) => requestAnimationFrame(() => r()));

  /* Images, loaded once each and shared: the pool's picture tiles, the try-it card, the memories. */
  const images = new Map();
  S.loadImage = (src) => {
    if (!images.has(src)) {
      images.set(src, new Promise((res, rej) => {
        const im = new Image();
        im.decoding = 'async';
        im.onload = () => res(im);
        im.onerror = () => rej(new Error(`image failed: ${src}`));
        im.src = src;
      }));
    }
    return images.get(src);
  };

  /* Decrypt: text arrives as scrambled glyphs that settle left to right (the machine voice
     handing over to a clean reading). Resolves when the text is final. */
  const SCRAMBLE = 'abcdefghijklmnopqrstuvwxyz0123456789#%&*+=<>/\\|{}[]';
  S.decrypt = (el, text, { duration } = {}) => {
    if (S.reduced()) { el.textContent = text; return Promise.resolve(); }
    const total = duration || Math.min(1100, 260 + text.length * 7);
    const reveal = Array.from(text, (_, i) => (i / Math.max(1, text.length)) * total * 0.7 + Math.random() * total * 0.3);
    const start = performance.now();
    el.classList.add('is-scrambling');
    return new Promise((resolve) => {
      const frame = (now) => {
        const t = now - start;
        let out = '';
        let done = true;
        for (let i = 0; i < text.length; i++) {
          const ch = text[i];
          if (ch === ' ' || t >= reveal[i]) out += ch;
          else { done = false; out += SCRAMBLE[(Math.random() * SCRAMBLE.length) | 0]; }
        }
        el.textContent = out;
        if (done) { el.classList.remove('is-scrambling'); resolve(); } else requestAnimationFrame(frame);
      };
      requestAnimationFrame(frame);
    });
  };

  /* Visibility: run callbacks with true/false as an element enters/leaves the viewport. */
  S.watch = (el, fn, threshold = 0.15) => {
    const io = new IntersectionObserver((entries) => entries.forEach((e) => fn(e.isIntersecting)), { threshold });
    io.observe(el);
    return io;
  };

  /* Fixed-size "screenshots" (the library window) scale to fit their column. The window's own
     layout size comes from CSS (wide on desktop, phone-sized on small screens). */
  document.querySelectorAll('[data-fit]').forEach((el) => {
    const shot = el.firstElementChild;
    const fit = () => {
      const k = Math.min(1, el.clientWidth / shot.offsetWidth);
      el.style.setProperty('--k', String(k));
      el.style.height = `${Math.ceil(shot.offsetHeight * k)}px`;
    };
    fit();
    window.addEventListener('resize', fit);
  });

  /* Little "| reading…" spinners in the machine voice. */
  if (!S.reduced()) {
    const frames = ['|', '/', '-', '\\'];
    let i = 0;
    setInterval(() => {
      i++;
      document.querySelectorAll('[data-spin]').forEach((el) => { el.textContent = el.textContent.replace(/^./, frames[i % 4]); });
    }, 130);
  }

  /* Copy buttons */
  document.querySelectorAll('[data-copy]').forEach((b) => {
    b.addEventListener('click', async () => {
      try { await navigator.clipboard.writeText(b.dataset.copy); b.textContent = 'copied'; }
      catch { b.textContent = 'press ⌘C'; }
      setTimeout(() => (b.textContent = 'copy'), 1600);
    });
  });

  /* Reveal-on-view for the static chat/terminal windows (lines appear in order, once). */
  document.querySelectorAll('.reveal-lines').forEach((el) => {
    if (S.reduced()) { el.classList.add('is-shown'); return; }
    const kids = [...el.children];
    kids.forEach((k, i) => (k.style.transitionDelay = `${i * 380}ms`));
    const io = S.watch(el, (seen) => { if (seen) { el.classList.add('is-shown'); io.disconnect(); } }, 0.4);
  });
  /* The <pre> terminal: wrap its lines so they can reveal one by one too. */
  document.querySelectorAll('pre.reveal-lines').forEach((pre) => {
    [...pre.children].forEach((k) => (k.style.display = 'inline'));
  });
})();
