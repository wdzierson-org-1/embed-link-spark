/* "Saving takes one tap": three share-sheet saves on a CSS iPhone (after React Bits Pro
   "Device": a light parallax tilt on hover), then the library with the new saves arriving.
   A touch indicator plays the person; every step is Share → Stash → saved.
   v0.4: the same phone, cloned, also plays in the "wherever you are" panel (a Medium article
   saved from Safari, then arriving in the library), so there's one phone to maintain. */
(() => {
  const S = window.Stash;
  const main = document.querySelector('.phone-stage');
  if (!main) return;
  const LAND = '../../../src/assets/landing/';
  // Real pictures: the book was photographed on a bookshop table (v0.6); the screenshots are screenshots.
  const BOOK_BG = 'url(2026-10-06-stashe-homepage/img/bookstore.jpg) center 80% / cover';
  const MINI_BOOK = '<span class="mini-book"></span>';
  const shotOf = (cell) => `url(${cell.querySelector('img').getAttribute('src')}) center / cover`;
  const ALL = ['shots', 'book', 'voice', 'tiktok', 'library'];
  // v0.6: the voice note — what's said, then what Stash finds in it (illustrative).
  const VOICE = {
    transcript: 'Remind me to book the cabin for the long weekend. Maya says the one on Lake George with the dock fills up by Friday, so do it before then.',
    title: 'Book the Lake George cabin before Friday',
    wins: [
      ['what it is', 'a reminder to book the lake george cabin before friday'],
      ['mentions', 'Lake George, Maya, Friday'],
    ],
    make: ['a to-do list', 'a reminder'],
  };
  const TT_THUMB = 'url(2026-10-06-stashe-homepage/img/shot-tiktok.jpg) center 35% / cover';

  // Clone before either film runs, while the phone is still in its first state.
  const mini = document.querySelector('[data-phone-mini]');
  if (mini) {
    const copy = main.querySelector('.device-wrap').cloneNode(true);
    copy.setAttribute('aria-label', 'An iPhone saving a Medium article to Stash from Safari’s share sheet, then the article arriving in Stash');
    mini.appendChild(copy);
  }
  film(main, {
    steps: [...document.querySelectorAll('.steps button')],
    stepList: document.querySelector('.steps'),
    toggle: document.querySelector('[data-phone-toggle]'),
    order: ALL,
    first: ALL.includes(S.param('scene')) ? S.param('scene') : 'shots',
    tilt: true,
  });
  if (mini) film(mini, { order: ['article', 'library'], first: 'article', fit: true });

  function film(stage, { steps = [], stepList = null, toggle = null, order, first, tilt = false, fit = false }) {
    const device = stage.querySelector('.device');
    const screen = device.querySelector('.screen');
    const scr = (name) => screen.querySelector(`[data-scr="${name}"]`);
    const photos = scr('photos'), cam = scr('camera'), viewer = scr('viewer'), safari = scr('safari'), lib = scr('library');
    const tt = scr('tiktok'), ttSheet = tt.querySelector('[data-tt-sheet]'), ttMore = tt.querySelector('[data-tt-more]');
    const vrec = scr('voice'), vnote = scr('vnote');
    const vBtn = vrec.querySelector('[data-vrec]'), vSave = vrec.querySelector('[data-vsave]'), vTime = vrec.querySelector('[data-vtime]'), vHint = vrec.querySelector('[data-vhint]');
    const vTitle = vnote.querySelector('[data-vn-title]'), vStatus = vnote.querySelector('[data-vn-status]'), vText = vnote.querySelector('[data-vn-transcript]'), vWins = vnote.querySelector('[data-vn-wins]');
    const sbar = screen.querySelector('.sbar');
    const sheet = screen.querySelector('[data-sheet]');
    const shThumb = sheet.querySelector('[data-sh-thumb]'), shTitle = sheet.querySelector('[data-sh-title]'), shSub = sheet.querySelector('[data-sh-sub]');
    const stashApp = sheet.querySelector('[data-stash-app]');
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
      sbar.classList.toggle('on-dark', name === 'camera' || name === 'tiktok');
    }
    function reset() {
      sheet.classList.remove('is-on');
      ttSheet.classList.remove('is-on');
      save.classList.remove('is-on');
      vrec.classList.remove('is-rec', 'is-done');
      vTime.textContent = '0:00';
      vHint.className = 'vrec-hint'; vHint.textContent = 'Tap to start recording';
      vTitle.textContent = 'Voice note'; vStatus.textContent = ''; vText.textContent = ''; vWins.textContent = '';
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
      openSheet({ bg: shotOf(picks[0]), title: '4 Photos Selected', sub: 'Options ›' });
      await S.wait(900, t);
      await tap(stashApp, t, 540);
      sheet.classList.remove('is-on'); lift();
      await saveFlow(t, { bg: shotOf(picks[3]), busyTitle: '4 screenshots', busySub: 'saving', doneTitle: '4 screenshots saved', doneSub: 'reading the text in each one' });
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
      await tap(stashApp, t, 540);
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
      openSheet({ bg: img, title: 'How to remember more of what you read', sub: 'medium.com' });
      await S.wait(900, t);
      await tap(stashApp, t, 540);
      sheet.classList.remove('is-on'); lift();
      await saveFlow(t, { bg: img, busyTitle: 'How to remember more of what you read', busySub: 'saving the full text', doneTitle: 'How to remember more of what you read', doneSub: 'saved with the full text, 2 min read' });
    }

    /* v0.6: a voice note. Recorded in Stash, then on its own screen: the transcript streams in as
       Stash hears it, the note gets its name, and what's in it prints as findings. */
    function voiceWin(label, value) {
      const w = document.createElement('div');
      w.className = 'win';
      w.innerHTML = '<div class="win-bar"><span></span><i></i></div><div class="vn-v"></div>';
      w.querySelector('.win-bar span').textContent = label;
      w.querySelector('.vn-v').textContent = value;
      return w;
    }
    function voiceMake() {
      const w = document.createElement('div');
      w.className = 'win is-make';
      w.innerHTML = '<div class="win-bar"><span>make into</span><span class="beta">beta</span></div><div class="vn-v"></div>';
      for (const label of VOICE.make) { const b = document.createElement('span'); b.className = 'mk'; b.textContent = label; b.style.display = 'grid'; b.style.placeItems = 'center'; w.querySelector('.vn-v').appendChild(b); }
      return w;
    }
    function voiceDone() {
      vTitle.textContent = VOICE.title;
      vStatus.textContent = '✓ transcribed, 29 words';
      vText.textContent = VOICE.transcript;
      vWins.textContent = '';
      for (const [l, v] of VOICE.wins) vWins.appendChild(voiceWin(l, v));
      vWins.appendChild(voiceMake());
    }
    async function voice(t) {
      reset(); show('voice');
      await S.wait(900, t);
      await tap(vBtn, t);
      vrec.classList.add('is-rec');
      vHint.className = 'vrec-hint px'; vHint.textContent = '| recording…'; vHint.dataset.spin = '';
      for (let sec = 1; sec <= 12; sec++) { await S.wait(270, t); vTime.textContent = `0:${String(sec).padStart(2, '0')}`; }
      await tap(vBtn, t, 300);
      vrec.classList.remove('is-rec'); vrec.classList.add('is-done');
      delete vHint.dataset.spin; vHint.textContent = '0:12 recorded';
      await S.wait(450, t);
      await tap(vSave, t, 520);
      lift();
      show('vnote');
      vStatus.textContent = '| transcribing…'; vStatus.dataset.spin = '';
      await S.wait(800, t);
      await S.streamInto(vText, VOICE.transcript, t, 11);
      delete vStatus.dataset.spin;
      vStatus.textContent = '✓ transcribed, 29 words';
      await S.wait(350, t);
      await S.decrypt(vTitle, VOICE.title, { duration: 700 });
      for (const [l, v] of VOICE.wins) {
        const w = vWins.appendChild(voiceWin(l, v));
        S.decrypt(w.querySelector('.vn-v'), v, { duration: 520 });
        await S.wait(650, t);
      }
      vWins.appendChild(voiceMake());
      await S.wait(2600, t);
    }

    // v0.5: a TikTok — TikTok's own share panel first, then More hands it to the iOS sheet.
    async function tiktok(t) {
      reset(); show('tiktok');
      await S.wait(1500, t);
      await tap(shareOf(tt), t);
      ttSheet.classList.add('is-on');
      await S.wait(950, t);
      await tap(ttMore, t, 520);
      ttSheet.classList.remove('is-on');
      await S.wait(280, t);
      openSheet({ bg: TT_THUMB, title: 'Tomato & mozzarella penne', sub: 'tiktok.com' });
      await S.wait(900, t);
      await tap(stashApp, t, 540);
      sheet.classList.remove('is-on'); lift();
      await saveFlow(t, { bg: TT_THUMB, busyTitle: 'TikTok video', busySub: 'watching the video', doneTitle: 'Tomato & mozzarella penne', doneSub: 'saved with the transcript, 0:58' });
    }

    async function library(t) {
      reset(); show('library');
      lcards.forEach((c, i) => {
        c.classList.remove('fresh'); c.getBoundingClientRect();
        c.style.animationDelay = `${i * 90}ms`; c.classList.add('fresh');
        const lt = c.querySelector('.lt');
        if (c.dataset.l.startsWith('s') || c.dataset.l === 'tiktok' || c.dataset.l === 'voice') lt.innerHTML = '<span class="px">| reading…</span>';
      });
      const shotsCards = lcards.filter((c) => c.dataset.l === 'tiktok' || c.dataset.l === 'voice' || c.dataset.l.startsWith('s'));
      for (let i = 0; i < shotsCards.length; i++) {
        await S.wait(i ? 420 : 900, t);
        const lt = shotsCards[i].querySelector('.lt');
        lt.textContent = lt.dataset.title;
      }
      await S.wait(2200, t);
    }

    const SCENES = { shots, book, article, voice, tiktok, library };
    const ORDER = order;
    const DUR = { shots: 10.2, book: 10.6, article: 8.2, voice: 15.4, tiktok: 13.8 };

    function markStep(name) {
      const stepName = name === 'library' ? 'tiktok' : name;
      if (name === 'library') return; // the TikTok step's bar already spans the library
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
      stepList?.classList.toggle('paused', stopped);
    }

    /* Still frames: the moment each scene is about. */
    function still(name) {
      reset();
      steps.forEach((b) => {
        if (b.dataset.scene === (name === 'library' ? 'tiktok' : name)) b.setAttribute('aria-current', 'step');
        else b.removeAttribute('aria-current');
      });
      stepList?.classList.add('is-still');
      if (name === 'shots') {
        show('photos');
        picks.forEach((p) => p.classList.add('on'));
        sel.classList.add('on'); sel.textContent = 'Cancel'; count.textContent = '4 Photos Selected';
        openSheet({ bg: shotOf(picks[0]), title: '4 Photos Selected', sub: 'Options ›' });
        const [x, y] = centre(stashApp); fingerTo(x, y, true); finger.classList.add('on');
      } else if (name === 'book') {
        show('viewer');
        setThumb(saveThumb, { html: MINI_BOOK, bg: BOOK_BG });
        saveTitle.textContent = 'Walden, Henry David Thoreau'; saveSub.textContent = 'a book, found from its cover';
        mark.textContent = 'saved'; mark.classList.add('is-done'); save.classList.add('is-on');
      } else if (name === 'article') {
        show('safari');
        setThumb(saveThumb, { bg: `url(${LAND}cover-article.jpg) center/cover` });
        saveTitle.textContent = 'How to remember more of what you read'; saveSub.textContent = 'saved with the full text, 2 min read';
        mark.textContent = 'saved'; mark.classList.add('is-done'); save.classList.add('is-on');
      } else if (name === 'voice') {
        show('vnote');
        voiceDone();
      } else if (name === 'tiktok') {
        show('tiktok');
        setThumb(saveThumb, { bg: TT_THUMB });
        saveTitle.textContent = 'Tomato & mozzarella penne'; saveSub.textContent = 'saved with the transcript, 0:58';
        mark.textContent = 'saved'; mark.classList.add('is-done'); save.classList.add('is-on');
      } else {
        show('library');
      }
    }

    steps.forEach((b) => b.addEventListener('click', () => {
      if (S.reduced()) { still(b.dataset.scene); return; }
      run(b.dataset.scene);
    }));
    toggle?.addEventListener('click', () => {
      paused = !paused;
      toggle.setAttribute('aria-pressed', String(paused));
      toggle.textContent = paused ? 'play' : 'pause';
      syncPause();
    });

    /* Tilt: the device leans a few degrees toward the pointer. */
    if (tilt && !S.reduced()) {
      stage.addEventListener('pointermove', (e) => {
        const r = stage.getBoundingClientRect();
        const nx = (e.clientX - r.left) / r.width - 0.5, ny = (e.clientY - r.top) / r.height - 0.5;
        device.style.setProperty('--ry', `${(nx * 9).toFixed(2)}deg`);
        device.style.setProperty('--rx', `${(-ny * 6).toFixed(2)}deg`);
      });
      stage.addEventListener('pointerleave', () => { device.style.setProperty('--ry', '0deg'); device.style.setProperty('--rx', '0deg'); });
    }

    // A copy in a panel is sized to the panel: the phone draws at 416×870 and scales by --ps.
    if (fit) {
      const wrap = stage.querySelector('.device-wrap');
      const size = () => {
        const ps = Math.min((stage.clientHeight - 40) / 870, (stage.clientWidth - 32) / 416);
        wrap.style.setProperty('--ps', Math.max(0.2, ps).toFixed(3));
      };
      new ResizeObserver(size).observe(stage);
      size();
    }

    if (S.reduced()) { if (toggle) toggle.hidden = true; still(first); return; }
    // Until it scrolls into view, show where the first scene begins (Safari, for the panel's copy).
    show({ shots: 'photos', book: 'camera', article: 'safari', voice: 'voice', tiktok: 'tiktok', library: 'library' }[first]);
    S.watch(stage, (seen) => {
      inView = seen;
      syncPause();
      if (seen && !tok) run(first);
    }, 0.3);
    document.addEventListener('visibilitychange', syncPause);
  }
})();
