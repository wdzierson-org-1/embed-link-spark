/* The Chrome extension, drawn and running. A Medium article in a browser: the pointer clicks the
   pinned Stash it button and the save lands (a green check on the icon, a "saved" tag); then it
   selects a sentence, right-clicks, chooses Stash it, and the selection lands the same way.
   Built into every [data-browser] element, so the homepage panel and extension.html share one
   source. Reduced motion and #still show one frame: the selection, the menu and the badge. */
(() => {
  const S = window.Stash;
  const hosts = [...document.querySelectorAll('[data-browser]')];
  if (!hosts.length) return;

  const SYMBOL = '<svg viewBox="0 0 724 764" aria-hidden="true"><use href="#st4sh-symbol"/></svg>';
  const markup = `
<div class="browser">
  <div class="br-bar">
    <span class="dots"><i></i><i></i><i></i></span>
    <span class="br-url">medium.com/@garrethow/how-to-remember-more</span>
    <span class="br-ext" data-br-ext>${SYMBOL}<i class="br-spin"></i><i class="br-badge"></i></span>
    <svg class="br-puzzle" viewBox="0 0 24 24" aria-hidden="true"><path d="M20.5 11H19V7a2 2 0 0 0-2-2h-4V3.5a2.5 2.5 0 0 0-5 0V5H4a2 2 0 0 0-2 2v3.8h1.5a2.7 2.7 0 0 1 0 5.4H2V20a2 2 0 0 0 2 2h3.8v-1.5a2.7 2.7 0 0 1 5.4 0V22H17a2 2 0 0 0 2-2v-4h1.5a2.5 2.5 0 0 0 0-5z"/></svg>
  </div>
  <div class="br-page">
    <p class="br-pub">Medium</p>
    <h3>How to remember more of what you read</h3>
    <p class="br-by">Garret How, 2 min read</p>
    <div class="br-img"></div>
    <p class="br-text">You finished the book three weeks ago, and you liked it. <mark data-br-sel>Asked what it said, you can offer a sentence, maybe two.</mark> That isn’t a failing of memory so much as a failure of practice.</p>
    <div class="br-menu" data-br-menu>
      <span>Copy</span>
      <span data-br-stash>${SYMBOL}Stash it</span>
      <span>Search Google for “Asked what it said…”</span>
      <hr>
      <span>Print…</span>
      <span>Inspect</span>
    </div>
  </div>
  <p class="br-toast" data-br-toast><b>✓ saved</b><span></span></p>
  <svg class="br-cursor" viewBox="0 0 16 24" aria-hidden="true"><path d="M1.5 1.5v18.6l4.9-4.7 3.2 7.2 2.9-1.3-3.1-7.1h6.8z"/></svg>
</div>`;

  function film(host) {
    host.innerHTML = markup;
    const b = host.querySelector('.browser');
    const ext = b.querySelector('[data-br-ext]');
    const sel = b.querySelector('[data-br-sel]');
    const menu = b.querySelector('[data-br-menu]');
    const stashIt = b.querySelector('[data-br-stash]');
    const toast = b.querySelector('[data-br-toast]');
    const cursor = b.querySelector('.br-cursor');
    if (host.dataset.browser === 'fit') S.fit(host, b, 22); // drawn at full size, scaled to its panel

    // Points are in the browser's own coordinates, whatever scale it's drawn at.
    const local = (x, y) => {
      const r = b.getBoundingClientRect();
      const k = r.width / b.offsetWidth || 1;
      return [(x - r.left) / k, (y - r.top) / k];
    };
    const centreOf = (el) => { const r = el.getBoundingClientRect(); return local(r.left + r.width / 2, r.top + r.height / 2); };
    const point = (xy, ms = 700) => {
      cursor.style.transition = `transform ${ms}ms cubic-bezier(.22,1,.36,1), scale .12s`;
      cursor.style.transform = `translate(${xy[0].toFixed(1)}px, ${xy[1].toFixed(1)}px)`;
    };
    const press = async (t) => { cursor.classList.add('is-press'); await S.wait(150, t); cursor.classList.remove('is-press'); };
    const say = (what) => { toast.querySelector('span').textContent = what; toast.classList.add('is-on'); };

    function reset() {
      b.classList.remove('is-busy', 'is-saved', 'has-sel', 'has-menu');
      stashIt.classList.remove('is-hi');
      toast.classList.remove('is-on');
      const r = b.getBoundingClientRect();
      point(local(r.left + r.width * 0.62, r.top + r.height * 0.9), 0);
    }

    function still() {
      reset();
      b.classList.add('has-sel', 'has-menu', 'is-saved');
      stashIt.classList.add('is-hi');
      const [x, y] = centreOf(stashIt);
      point([x + 38, y - 2], 0); // on the row, clear of its label
    }

    async function play(t) {
      reset();
      await S.wait(800, t);
      // 1. The page you're on: one click on the toolbar button.
      const [ex, ey] = centreOf(ext);
      point([ex - 2, ey - 1], 800);
      await S.wait(950, t);
      await press(t);
      b.classList.add('is-busy');
      await S.wait(850, t);
      b.classList.remove('is-busy');
      b.classList.add('is-saved');
      say('link: medium.com');
      await S.wait(2100, t);
      toast.classList.remove('is-on');
      b.classList.remove('is-saved');
      // 2. A selection: drag across a sentence, right-click, Stash it.
      const lines = sel.getClientRects();
      const first = lines[0], last = lines[lines.length - 1];
      point(local(first.left + 1, first.top + first.height * 0.55), 750);
      await S.wait(850, t);
      b.classList.add('has-sel');
      point(local(last.right - 1, last.top + last.height * 0.55), 650);
      await S.wait(800, t);
      await press(t);
      b.classList.add('has-menu');
      await S.wait(550, t);
      const [sx, sy] = centreOf(stashIt);
      point([sx + 38, sy - 2], 450);
      await S.wait(380, t);
      stashIt.classList.add('is-hi');
      await S.wait(350, t);
      await press(t);
      b.classList.remove('has-menu');
      b.classList.add('is-busy');
      await S.wait(750, t);
      b.classList.remove('is-busy');
      b.classList.add('is-saved');
      say('note: “Asked what it said…”');
      await S.wait(2400, t);
    }

    if (S.reduced()) { requestAnimationFrame(still); return; }
    let tok = null, inView = false;
    const run = async () => {
      const t = (tok = S.token());
      t.hidden = !inView || document.hidden;
      try { for (;;) await play(t); } catch (err) { if (err !== S.CANCEL) throw err; }
    };
    S.watch(host, (seen) => { inView = seen; if (tok) tok.hidden = !seen || document.hidden; if (seen && !tok) run(); }, 0.25);
    document.addEventListener('visibilitychange', () => { if (tok) tok.hidden = document.hidden || !inView; });
  }

  document.fonts.ready.then(() => hosts.forEach(film));
})();
