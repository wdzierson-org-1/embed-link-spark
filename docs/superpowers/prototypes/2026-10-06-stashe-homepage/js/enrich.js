/* "We gather all of the background": paste → card → enrichment, as a looping explainer.
   The words in the statement are the controls; each one plays its own example. Sample
   content: the repo and paper are real, the people and places are illustrative. */
(() => {
  const S = window.Stashe;
  const stage = document.querySelector('[data-stage]');
  if (!stage) return;
  const words = [...document.querySelectorAll('.word')];
  const composer = stage.querySelector('.composer');
  const urlEl = composer.querySelector('.composer-url');
  const card = stage.querySelector('.scard');
  const kindEl = card.querySelector('.scard-kind');
  const titleEl = card.querySelector('.scard-title');
  const descEl = card.querySelector('.scard-desc');
  const m1 = card.querySelector('.scard-m1'), m2 = card.querySelector('.scard-m2');
  const svg = stage.querySelector('.leaders');
  const nodesEl = stage.querySelector('.nodes');
  const toggle = document.querySelector('[data-enrich-toggle]');
  const pix = new S.PixelImage(card.querySelector('canvas'), { block: 28 });
  const narrow = matchMedia('(max-width: 900px)');

  const LAND = '../../../src/assets/landing/';
  const IMG = '2026-10-06-stashe-homepage/img/';
  const EX = {
    link: {
      url: 'https://github.com/charmbracelet/gum', img: IMG + 'repo.png', focus: [0.5, 0.5],
      kind: 'repo', busy: 'reading the readme', title: 'charmbracelet/gum', desc: 'A tool for glamorous shell scripts.', m1: 'github.com', m2: 'Go',
      nodes: [
        ['what it is', 'A kit of prompts, pickers, spinners and inputs for plain shell scripts.'],
        ['from the readme', 'Install with <code>brew install gum</code>, then try <code>gum choose</code>.'],
        ['made by', 'Charm, the team behind Bubble Tea and Glow.'],
        ['details', 'Written in Go. MIT license.'],
        ['find it by', '<em>“that pretty terminal prompt thing”</em>'],
      ],
    },
    shot: {
      url: 'Screenshot 2026-10-02 at 11.42 PM.png', img: IMG + 'shot-colette.jpg', focus: [0.5, 0.36],
      kind: 'screenshot', busy: 'reading the screenshot', title: 'Chez Colette, West Village', desc: 'The corner table by the window, most nights from 5:30. Walk-ins welcome.', m1: 'photos', m2: 'Oct 2',
      nodes: [
        ['text in image', '“The corner table by the window is yours most nights from 5:30. Walk-ins welcome — 12 Perry St.”'],
        ['place', 'Chez Colette, 12 Perry St, New York'],
        ['from', 'A post by @chez.colette'],
        ['where you were', 'Brooklyn, 11:42 pm'],
        ['find it by', '<em>“that french place with the window table”</em>'],
      ],
    },
    article: {
      url: 'https://medium.com/@notesonreading/why-you-remember-so-little', img: LAND + 'cover-article.jpg', focus: [0.5, 0.5],
      kind: 'article', busy: 'reading the article', title: 'Why you remember so little of what you read', desc: 'Reading without recall fades within days. A line of notes per chapter changes that.', m1: 'medium.com', m2: '9 min read',
      nodes: [
        ['full text', 'All 2,180 words, kept in case the page changes or disappears.'],
        ['summary', 'We forget what we never try to recall. A line of notes after each chapter makes it stick.'],
        ['author', 'Ada Whitlock, in Notes on Reading'],
        ['reading time', '9 minutes'],
        ['find it by', '<em>“that article about forgetting books”</em>'],
      ],
    },
    paper: {
      url: 'https://arxiv.org/pdf/2307.03172', img: IMG + 'paper.png', focus: [0.5, 0.14],
      kind: 'pdf', busy: 'reading the pdf', title: 'Lost in the Middle: How Language Models Use Long Contexts', desc: 'Liu et al. Language models use the start and end of a long input best.', m1: 'arxiv.org', m2: 'PDF',
      nodes: [
        ['authors', 'Nelson F. Liu, Kevin Lin, John Hewitt, Ashwin Paranjape, Michele Bevilacqua, Fabio Petroni, Percy Liang'],
        ['finding', 'Accuracy is highest when the answer sits at the start or end of the context, and drops in the middle.'],
        ['published', 'arXiv, July 2023'],
        ['every page', 'Read in full, so you can ask about any section.'],
        ['find it by', '<em>“the paper on long context windows”</em>'],
      ],
    },
    tiktok: {
      url: 'https://www.tiktok.com/@sundaysupper/video/7391836274', img: LAND + 'cover-recipe.jpg', focus: [0.62, 0.5],
      kind: 'video', busy: 'watching the video', title: 'Tomato & mozzarella penne', desc: 'A 20-minute weeknight pasta: blistered tomatoes, torn mozzarella, basil.', m1: 'tiktok.com', m2: '0:58',
      nodes: [
        ['transcript', '“Get your water going and salt it like the sea. While the penne cooks, blister the tomatoes…”'],
        ['ingredients', 'Penne, cherry tomatoes, fresh mozzarella, basil, olive oil'],
        ['on-screen text', '20-MINUTE DINNER, 5 INGREDIENTS'],
        ['creator', '@sundaysupper, 58 seconds'],
        ['find it by', '<em>“that tomato pasta tiktok”</em>'],
      ],
    },
  };
  const ORDER = ['link', 'shot', 'article', 'paper', 'tiktok'];

  let tok = null, paused = false, inView = false, current = S.param('ex') && EX[S.param('ex')] ? S.param('ex') : 'tiktok';

  function setWord(key, p) {
    words.forEach((w) => {
      const on = w.dataset.ex === key;
      w.setAttribute('aria-pressed', String(on));
      w.style.setProperty('--p', on ? `${p}%` : '0%');
    });
  }

  function clearNodes() {
    nodesEl.textContent = '';
    svg.textContent = '';
  }

  /* Geometry: four windows beside the card (two each side), "find it by" under it. */
  function layout(nodeEls) {
    if (narrow.matches) return;
    const sw = stage.clientWidth;
    const cx = sw / 2;
    const cardL = card.offsetLeft, cardT = card.offsetTop, cardW = card.offsetWidth, cardH = card.offsetHeight;
    const gap = Math.min(96, Math.max(40, (sw - cardW - 2 * 252) / 2 - 40));
    const slots = [
      { side: 'R', row: 0 }, { side: 'L', row: 0 }, { side: 'R', row: 1 }, { side: 'L', row: 1 },
    ];
    const paths = [];
    nodeEls.forEach((el, i) => {
      const find = el.classList.contains('is-find');
      const w = el.offsetWidth, h = el.offsetHeight;
      if (find) {
        const left = cx - w / 2, top = cardT + cardH + 56;
        el.style.left = `${left}px`; el.style.top = `${top}px`; el.style.setProperty('--origin', 'center top');
        paths.push({ d: `M${cx} ${cardT + cardH} V${top}`, a: [cx, cardT + cardH], b: [cx, top] });
        return;
      }
      const slot = slots[i] || slots[slots.length - 1];
      const top = cardT + 8 + slot.row * 158;
      const left = slot.side === 'R' ? cardL + cardW + gap : cardL - gap - w;
      el.style.left = `${left}px`; el.style.top = `${top}px`;
      el.style.setProperty('--origin', slot.side === 'R' ? 'left center' : 'right center');
      const ay = cardT + 54 + slot.row * 112;          // where the line leaves the card
      const ny = top + 10.5;                           // centre of the node's title bar
      const ax = slot.side === 'R' ? cardL + cardW : cardL;
      const nx = slot.side === 'R' ? left : left + w;
      const mx = (ax + nx) / 2;
      paths.push({ d: `M${ax} ${ay} H${mx} V${ny} H${nx}`, a: [ax, ay], b: [nx, ny] });
    });
    return paths;
  }

  function drawLeader(p, animate) {
    const ns = 'http://www.w3.org/2000/svg';
    const path = document.createElementNS(ns, 'path');
    path.setAttribute('d', p.d);
    svg.appendChild(path);
    const dot = document.createElementNS(ns, 'circle');
    dot.setAttribute('cx', p.a[0]); dot.setAttribute('cy', p.a[1]); dot.setAttribute('r', 2.5);
    svg.appendChild(dot);
    if (!animate) return;
    const len = path.getTotalLength();
    path.style.strokeDasharray = `${len}`;
    path.style.strokeDashoffset = `${len}`;
    path.getBoundingClientRect();
    path.style.transition = 'stroke-dashoffset .38s cubic-bezier(.22,1,.36,1)';
    path.style.strokeDashoffset = '0';
  }

  function makeNode([label, html]) {
    const el = document.createElement('div');
    const find = label === 'find it by';
    el.className = 'node win' + (find ? ' is-find' : '');
    el.innerHTML = `<div class="win-bar"><span>${label}</span><span>${find ? 'search' : '↳'}</span></div><div class="node-body">${html}</div>`;
    return el;
  }

  function fillCard(ex, loading) {
    kindEl.textContent = ex.kind;
    m1.textContent = ex.m1;
    m2.textContent = loading ? '' : ex.m2;
    if (loading) {
      titleEl.innerHTML = `<span class="busy">| ${ex.busy}…</span>`;
      descEl.innerHTML = '<span class="skel">····························</span><span class="skel">····················</span>';
    } else {
      titleEl.textContent = ex.title;
      descEl.textContent = ex.desc;
    }
  }

  function spin(t) {
    const frames = ['|', '/', '-', '\\'];
    let i = 0;
    const iv = setInterval(() => {
      if (t.cancelled) return clearInterval(iv);
      if (t.paused || t.hidden) return;
      const b = titleEl.querySelector('.busy');
      if (!b) return clearInterval(iv);
      b.textContent = b.textContent.replace(/^./, frames[++i % 4]);
    }, 120);
    return () => clearInterval(iv);
  }

  /* Final frame of an example, drawn at once (reduced motion, `still`, or narrow screens catching up). */
  async function showFinal(key) {
    const ex = EX[key];
    setWord(key, 100);
    clearNodes();
    urlEl.textContent = ''; composer.classList.remove('has-url', 'show-kbd', 'press');
    fillCard(ex, false);
    card.classList.add('is-in');
    await pix.set(ex.img, ex.focus).catch(() => {});
    pix.render(1);
    const els = ex.nodes.map(makeNode);
    els.forEach((el) => { nodesEl.appendChild(el); el.classList.add('is-in'); });
    const paths = layout(els) || [];
    paths.forEach((p) => drawLeader(p, false));
  }

  async function play(key, t) {
    const ex = EX[key];
    current = key;
    setWord(key, 0);
    clearNodes();
    card.classList.remove('is-in');
    composer.classList.remove('has-url', 'show-kbd', 'press');
    urlEl.textContent = '';
    await S.wait(500, t);

    composer.classList.add('show-kbd');
    await S.wait(420, t);
    urlEl.textContent = ex.url;
    composer.classList.add('has-url');
    await S.wait(700, t);
    composer.classList.remove('show-kbd');
    composer.classList.add('press');
    await S.wait(170, t);
    composer.classList.remove('press');

    fillCard(ex, true);
    await pix.set(ex.img, ex.focus).catch(() => {});
    pix.render(28);
    card.classList.add('is-in');
    const stopSpin = spin(t);
    await S.wait(260, t);
    composer.classList.remove('has-url');
    await S.wait(640, t);
    for (const b of [22, 16, 11, 7, 4, 2, 1]) { pix.render(b); await S.wait(85, t); }
    stopSpin();
    fillCard(ex, false);
    await S.wait(360, t);

    const els = ex.nodes.map(makeNode);
    els.forEach((el) => nodesEl.appendChild(el));
    const paths = layout(els) || [];
    for (let i = 0; i < els.length; i++) {
      if (paths[i]) drawLeader(paths[i], true);
      await S.wait(paths[i] ? 300 : 120, t);
      els[i].classList.add('is-in');
      await S.wait(i === els.length - 2 ? 520 : 360, t);
    }

    // Hold, with the active word filling up as the clock until the next example.
    const hold = 4400, stepMs = 80;
    for (let e = 0; e < hold; e += stepMs) {
      setWord(key, Math.round((e / hold) * 100));
      await S.wait(stepMs, t);
    }
    setWord(key, 100);
  }

  async function run(startKey) {
    if (tok) tok.cancelled = true;
    const t = (tok = S.token());
    t.paused = paused; t.hidden = !inView;
    let i = ORDER.indexOf(startKey);
    try {
      for (;;) {
        await play(ORDER[i], t);
        i = (i + 1) % ORDER.length;
      }
    } catch (err) {
      if (err !== S.CANCEL) throw err;
    }
  }

  words.forEach((w) => w.addEventListener('click', () => {
    if (S.reduced()) { current = w.dataset.ex; showFinal(current); return; }
    run(w.dataset.ex);
  }));

  toggle.addEventListener('click', () => {
    paused = !paused;
    toggle.setAttribute('aria-pressed', String(paused));
    toggle.textContent = paused ? 'play' : 'pause';
    if (tok) tok.paused = paused;
  });

  window.addEventListener('resize', () => {
    clearTimeout(run._r);
    run._r = setTimeout(() => {
      const els = [...nodesEl.children];
      if (!els.length) return;
      svg.textContent = '';
      (layout(els) || []).forEach((p) => drawLeader(p, false));
    }, 150);
  });

  if (S.reduced()) {
    toggle.hidden = true;
    showFinal(current);
    return;
  }
  S.watch(stage, (seen) => {
    inView = seen;
    if (tok) tok.hidden = !seen;
    if (seen && !tok) run(current);
  }, 0.25);
  document.addEventListener('visibilitychange', () => { if (tok) tok.hidden = document.hidden || !inView; });
})();
