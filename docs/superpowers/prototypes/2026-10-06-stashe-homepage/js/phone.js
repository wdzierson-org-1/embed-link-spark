/* "Saving takes one tap": three share-sheet saves on a CSS iPhone (after React Bits Pro
   "Device": a light parallax tilt on hover), then the library with the new saves arriving.
   A touch indicator plays the person; every step is Share → Stashe → saved. */
(() => {
  const S = window.Stashe;
  const stage = document.querySelector('.phone-stage');
  if (!stage) return;
  const device = stage.querySelector('.device');
  const screen = device.querySelector('.screen');
  const scr = (name) => screen.querySelector(`[data-scr="${name}"]`);
  const photos = scr('photos'), cam = scr('camera'), viewer = scr('viewer'), safari = scr('safari'), lib = scr('library');
  const sbar = screen.querySelector('.sbar');
  const sheet = screen.querySelector('[data-sheet]');
  const shThumb = sheet.querySelector('[data-sh-thumb]'), shTitle = sheet.querySelector('[data-sh-title]'), shSub = sheet.querySelector('[data-sh-sub]');
  const stasheApp = sheet.querySelector('[data-stashe-app]');
  const save = screen.querySelector('[data-save]');
  const saveThumb = save.querySelector('[data-save-thumb]'), saveTitle = save.querySelector('[data-save-title]'), saveSub = save.querySelector('[data-save-sub]'), mark = save.querySelector('[data-saved-mark]');
  const finger = screen.querySelector('.finger');
  const flash = screen.querySelector('.flash');
  const sel = photos.querySelector('.sel'), count = photos.querySelector('.ph-count');
  const picks = [...photos.querySelectorAll('[data-pick]')].sort((a, b) => a.dataset.pick - b.dataset.pick);
  const shutter = cam.querySelector('.shutter'), camThumb = cam.querySelector('[data-cam-thumb]');
  const art = safari.querySelector('.art');
  const lcards = [...lib.querySelectorAll('.lcard')];
  lcards.forEach((c) => { const lt = c.querySelector('.lt'); lt.dataset.title = lt.textContent; });
  const steps = [...document.querySelectorAll('.steps button')];
  const stepList = document.querySelector('.steps');
  const toggle = document.querySelector('[data-phone-toggle]');
  const LAND = '../../../src/assets/landing/';
  const BOOK_BG = 'linear-gradient(160deg,#8a6a4c,#5b4330 60%,#3d2c20)';
  const MINI_BOOK = '<span class="mini-book"></span>';

  /* Centre of an element in screen coordinates (layout space, so the tilt doesn't skew it). */
  function centre(el) {
    let x = el.offsetWidth / 2, y = el.offsetHeight / 2, n = el;
    while (n && n !== screen) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent; }
    return [x, y];
  }
  function fingerTo(x, y, instant) {
    if (instant) {
      finger.style.transition = 'none';
      finger.style.transform = `translate(${x}px, ${y}px)`;
      finger.getBoundingClientRect();
      finger.style.transition = '';
    } else {
      finger.style.transform = `translate(${x}px, ${y}px)`;
    }
  }
  async function tap(el, t, travel = 620) {
    const [x, y] = centre(el);
    const fresh = !finger.classList.contains('on');
    if (fresh) { fingerTo(x, y + 60, true); finger.classList.add('on'); await S.wait(30, t); }
    fingerTo(x, y);
    await S.wait(travel, t);
    finger.classList.add('down');
    await S.wait(150, t);
    finger.classList.remove('down');
  }
  const lift = () => finger.classList.remove('on', 'down');

  function show(name) {
    screen.querySelectorAll('.scr').forEach((s) => s.classList.toggle('is-on', s.dataset.scr === name));
    sbar.classList.toggle('on-dark', name === 'camera');
  }
  function reset() {
    sheet.classList.remove('is-on');
    save.classList.remove('is-on');
    picks.forEach((p) => p.classList.remove('on'));
    sel.classList.remove('on'); sel.textContent = 'Select'; count.textContent = 'Photos';
    cam.classList.remove('focus', 'snap');
    camThumb.innerHTML = ''; camThumb.style.background = '';
    art.style.transition = 'none'; art.style.transform = '';
    lift();
  }
  function setThumb(el, { html = '', bg = '' }) { el.innerHTML = html; el.style.background = bg; }
  function openSheet(o) {
    setThumb(shThumb, o);
    shTitle.textContent = o.title; shSub.textContent = o.sub;
    sheet.classList.add('is-on');
  }
  function shareOf(scrEl) { return scrEl.querySelector('[data-share]'); }

  async function saveFlow(t, o) {
    setThumb(saveThumb, o);
    saveTitle.textContent = o.busyTitle;
    saveSub.textContent = `| ${o.busySub}…`;
    mark.textContent = 'saving'; mark.classList.remove('is-done');
    save.classList.add('is-on');
    const frames = ['|', '/', '-', '\\'];
    for (let i = 0; i < 11; i++) { await S.wait(115, t); saveSub.textContent = `${frames[i % 4]} ${o.busySub}…`; }
    mark.textContent = 'saved'; mark.classList.add('is-done');
    saveTitle.textContent = o.doneTitle;
    saveSub.textContent = o.doneSub;
    await S.wait(1800, t);
    save.classList.remove('is-on');
    await S.wait(520, t);
  }

  async function shots(t) {
    reset(); show('photos');
    await S.wait(700, t);
    await tap(sel, t);
    sel.classList.add('on'); sel.textContent = 'Cancel'; count.textContent = 'Select Items';
    for (let i = 0; i < picks.length; i++) {
      await tap(picks[i], t, 430);
      picks[i].classList.add('on');
      count.textContent = `${i + 1} Photo${i ? 's' : ''} Selected`;
    }
    await S.wait(260, t);
    await tap(shareOf(photos), t);
    openSheet({ html: picks[0].querySelector('.ss').outerHTML, title: '4 Photos Selected', sub: 'Options ›' });
    await S.wait(900, t);
    await tap(stasheApp, t, 540);
    sheet.classList.remove('is-on'); lift();
    await saveFlow(t, { html: picks[1].querySelector('.ss').outerHTML, busyTitle: '4 screenshots', busySub: 'saving', doneTitle: '4 screenshots saved', doneSub: 'reading the text in each one' });
    picks.forEach((p) => p.classList.remove('on')); sel.classList.remove('on'); sel.textContent = 'Select'; count.textContent = 'Photos';
  }

  async function book(t) {
    reset(); show('camera');
    await S.wait(800, t);
    cam.classList.add('focus');
    await S.wait(650, t);
    await tap(shutter, t);
    cam.classList.add('snap');
    flash.classList.remove('go'); flash.getBoundingClientRect(); flash.classList.add('go');
    await S.wait(170, t);
    cam.classList.remove('snap', 'focus');
    setThumb(camThumb, { html: MINI_BOOK, bg: BOOK_BG });
    await S.wait(700, t);
    await tap(camThumb, t, 520);
    show('viewer');
    await S.wait(850, t);
    await tap(shareOf(viewer), t);
    openSheet({ html: MINI_BOOK, bg: BOOK_BG, title: '1 Photo Selected', sub: 'Options ›' });
    await S.wait(900, t);
    await tap(stasheApp, t, 540);
    sheet.classList.remove('is-on'); lift();
    await saveFlow(t, { html: MINI_BOOK, bg: BOOK_BG, busyTitle: 'Photo', busySub: 'reading the cover', doneTitle: 'Walden, Henry David Thoreau', doneSub: 'a book, found from its cover' });
  }

  async function article(t) {
    reset(); show('safari');
    await S.wait(900, t);
    art.style.transition = 'transform 1.4s cubic-bezier(.22,1,.36,1)';
    art.style.transform = 'translateY(-46px)';
    await S.wait(1100, t);
    await tap(shareOf(safari), t);
    const img = `url(${LAND}cover-article.jpg) center/cover`;
    openSheet({ bg: img, title: 'Why you remember so little of what you read', sub: 'medium.com' });
    await S.wait(900, t);
    await tap(stasheApp, t, 540);
    sheet.classList.remove('is-on'); lift();
    await saveFlow(t, { bg: img, busyTitle: 'Why you remember so little of what you read', busySub: 'saving the full text', doneTitle: 'Why you remember so little of what you read', doneSub: 'saved with the full text, 9 min read' });
  }

  async function library(t) {
    reset(); show('library');
    lcards.forEach((c, i) => {
      c.classList.remove('fresh'); c.getBoundingClientRect();
      c.style.animationDelay = `${i * 90}ms`; c.classList.add('fresh');
      const lt = c.querySelector('.lt');
      if (c.dataset.l.startsWith('s')) lt.innerHTML = '<span class="px">| reading…</span>';
    });
    const shotsCards = lcards.filter((c) => c.dataset.l.startsWith('s'));
    for (let i = 0; i < shotsCards.length; i++) {
      await S.wait(i ? 420 : 900, t);
      const lt = shotsCards[i].querySelector('.lt');
      lt.textContent = lt.dataset.title;
    }
    await S.wait(2200, t);
  }

  const SCENES = { shots, book, article, library };
  const ORDER = ['shots', 'book', 'article', 'library'];
  const DUR = { shots: 10.2, book: 10.6, article: 11.6 };

  function markStep(name) {
    const stepName = name === 'library' ? 'article' : name;
    if (name === 'library') return; // the article step's bar already spans the library
    steps.forEach((b) => {
      const on = b.dataset.scene === stepName;
      if (on) {
        b.removeAttribute('aria-current'); b.getBoundingClientRect();
        b.style.setProperty('--dur', `${DUR[stepName]}s`);
        b.setAttribute('aria-current', 'step');
      } else b.removeAttribute('aria-current');
    });
  }

  let tok = null, paused = false, inView = false;
  async function run(start) {
    if (tok) tok.cancelled = true;
    const t = (tok = S.token());
    t.paused = paused; t.hidden = !inView;
    let i = ORDER.indexOf(start);
    try {
      for (;;) {
        markStep(ORDER[i]);
        await SCENES[ORDER[i]](t);
        i = (i + 1) % ORDER.length;
      }
    } catch (err) { if (err !== S.CANCEL) throw err; }
  }
  function syncPause() {
    const stopped = paused || !inView || document.hidden;
    if (tok) { tok.paused = paused; tok.hidden = !inView || document.hidden; }
    stepList.classList.toggle('paused', stopped);
  }

  /* Still frames: the moment each scene is about. */
  function still(name) {
    reset();
    steps.forEach((b) => {
      if (b.dataset.scene === (name === 'library' ? 'article' : name)) b.setAttribute('aria-current', 'step');
      else b.removeAttribute('aria-current');
    });
    stepList.classList.add('is-still');
    if (name === 'shots') {
      show('photos');
      picks.forEach((p) => p.classList.add('on'));
      sel.classList.add('on'); sel.textContent = 'Cancel'; count.textContent = '4 Photos Selected';
      openSheet({ html: picks[0].querySelector('.ss').outerHTML, title: '4 Photos Selected', sub: 'Options ›' });
      const [x, y] = centre(stasheApp); fingerTo(x, y, true); finger.classList.add('on');
    } else if (name === 'book') {
      show('viewer');
      setThumb(saveThumb, { html: MINI_BOOK, bg: BOOK_BG });
      saveTitle.textContent = 'Walden, Henry David Thoreau'; saveSub.textContent = 'a book, found from its cover';
      mark.textContent = 'saved'; mark.classList.add('is-done'); save.classList.add('is-on');
    } else if (name === 'article') {
      show('safari');
      setThumb(saveThumb, { bg: `url(${LAND}cover-article.jpg) center/cover` });
      saveTitle.textContent = 'Why you remember so little of what you read'; saveSub.textContent = 'saved with the full text, 9 min read';
      mark.textContent = 'saved'; mark.classList.add('is-done'); save.classList.add('is-on');
    } else {
      show('library');
    }
  }

  steps.forEach((b) => b.addEventListener('click', () => {
    if (S.reduced()) { still(b.dataset.scene); return; }
    run(b.dataset.scene);
  }));
  toggle.addEventListener('click', () => {
    paused = !paused;
    toggle.setAttribute('aria-pressed', String(paused));
    toggle.textContent = paused ? 'play' : 'pause';
    syncPause();
  });

  /* Tilt: the device leans a few degrees toward the pointer. */
  if (!S.reduced()) {
    stage.addEventListener('pointermove', (e) => {
      const r = stage.getBoundingClientRect();
      const nx = (e.clientX - r.left) / r.width - 0.5, ny = (e.clientY - r.top) / r.height - 0.5;
      device.style.setProperty('--ry', `${(nx * 9).toFixed(2)}deg`);
      device.style.setProperty('--rx', `${(-ny * 6).toFixed(2)}deg`);
    });
    stage.addEventListener('pointerleave', () => { device.style.setProperty('--ry', '0deg'); device.style.setProperty('--rx', '0deg'); });
  }

  const first = ORDER.includes(S.param('scene')) ? S.param('scene') : 'shots';
  if (S.reduced()) { toggle.hidden = true; still(first); return; }
  S.watch(stage, (seen) => {
    inView = seen;
    syncPause();
    if (seen && !tok) run(first);
  }, 0.3);
  document.addEventListener('visibilitychange', syncPause);
})();
