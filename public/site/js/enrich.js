/* "Try it": paste → card → enrichment. One renderer serves two sources:
   - examples: scripted event streams (the words in the statement pick which one);
   - live: whatever the visitor pastes, drops or types, enriched for real by homepage-enrich and
     disclosed field by field as the stream arrives.
   Sample content in the examples: the repo and paper are real; people and places are illustrative. */
(() => {
  const S = window.Stash;
  const stage = document.querySelector('[data-stage]');
  if (!stage) return;
  const words = [...document.querySelectorAll('.word')];
  const lines = stage.querySelector('.try-lines');
  const form = stage.querySelector('[data-composer]');
  const input = form.querySelector('[data-input]');
  const demo = form.querySelector('[data-demo]');
  const send = form.querySelector('[data-send]');
  const attach = form.querySelector('[data-attach]');
  const fileInput = form.querySelector('[data-file-input]');
  const chip = form.querySelector('[data-file]');
  const chipThumb = chip.querySelector('[data-file-thumb]');
  const chipName = chip.querySelector('[data-file-name]');
  const chipSize = chip.querySelector('[data-file-size]');
  const chipX = chip.querySelector('[data-file-x]');
  const card = stage.querySelector('.scard');
  const media = card.querySelector('.scard-media');
  const kindEl = card.querySelector('.scard-kind');
  const titleEl = card.querySelector('.scard-title');
  const descEl = card.querySelector('.scard-desc');
  const m1 = card.querySelector('.scard-m1');
  const m2 = card.querySelector('.scard-m2');
  const svg = stage.querySelector('.leaders');
  const nodesEl = stage.querySelector('.nodes');
  const toggle = document.querySelector('[data-enrich-toggle]');
  const pix = new S.PixelImage(card.querySelector('canvas'), { block: 28 });
  const narrow = matchMedia('(max-width: 900px)');
  const BASE_HEIGHT = 700;

  const LAND = '/site/landing/';
  const IMG = '/site/img/';

  /* ---------------- examples ---------------- */
  // v0.5: every example ends with a "make into" window (beta): what Stash can turn the save into.
  const EX = {
    link: {
      input: 'https://inesatelier.co/products/woven-tote', tag: 'link', busy: 'reading the page', img: IMG + 'bag.jpg', focus: [0.5, 0.55],
      meta: { title: 'The Woven Tote, Tan', desc: 'Hand-woven vegetable-tanned leather, unlined, with a brass buckle.', m1: 'inesatelier.co', m2: '$248' },
      fields: [
        ['fact', 'price', '$248, ships in 3–5 days'],
        ['what', 'what it is', 'product page for a hand-woven leather tote bag'],
        ['fact', 'materials', 'vegetable-tanned leather, brass hardware'],
        ['fact', 'colors', 'tan, black, oxblood'],
        ['summary', 'summary', 'An unlined, hand-woven leather tote in three colors that fits a 14-inch laptop.'],
        ['find', 'find it by', 'that woven bag / tan leather tote'],
        ['make', 'make into', ['a wishlist', 'a comparison', 'a to-do list']],
      ],
    },
    repo: {
      input: 'https://github.com/charmbracelet/gum', tag: 'repo', busy: 'reading the readme', img: IMG + 'og-gum.png', focus: [0.38, 0.45],
      meta: { title: 'charmbracelet/gum', desc: 'A tool for glamorous shell scripts.', m1: 'github.com', m2: 'Go' },
      fields: [
        ['fact', 'details', 'Go, MIT license, 24k stars'],
        ['what', 'what it is', 'a kit of prompts, pickers, spinners and inputs for shell scripts'],
        ['summary', 'summary', 'Lets plain shell scripts ask questions and offer choices, with no Go to write.'],
        ['fact', 'install', 'brew install gum'],
        ['find', 'find it by', 'that pretty terminal prompt thing / shell script pickers'],
        ['make', 'make into', ['a setup checklist', 'a cheat sheet']],
      ],
    },
    reel: {
      input: 'https://www.instagram.com/reel/DA3daysLisbon/', tag: 'reel', busy: 'watching the reel', img: IMG + 'shot-reel.jpg', focus: [0.5, 0.72],
      meta: { title: '3 days in Lisbon', desc: 'Where to stay, eat and watch the sunset: Graça, Alfama and Príncipe Real.', m1: 'instagram.com', m2: '0:41' },
      fields: [
        ['what', 'what it is', 'travel reel: three days in lisbon'],
        ['fact', 'places', 'Miradouro da Graça, Alfama, Príncipe Real'],
        ['fact', 'creator', '@ana.wanders'],
        ['fact', 'on-screen text', '“3 days in Lisbon”'],
        ['summary', 'summary', 'Sunset at Miradouro da Graça, dinner in Alfama, and a quiet place to stay in Príncipe Real.'],
        ['find', 'find it by', 'that lisbon reel / where to watch the sunset in lisbon'],
        ['make', 'make into', ['an itinerary', 'a map list', 'a packing list']],
      ],
    },
    shot: {
      input: 'Screenshot 2026-10-02 at 11.42 PM.png', tag: 'screenshot', busy: 'reading the screenshot', img: IMG + 'shot-colette.jpg', focus: [0.5, 0.36],
      meta: { title: 'Chez Colette, West Village', desc: 'The corner table by the window, most nights from 5:30. Walk-ins welcome.', m1: 'photos', m2: 'Oct 2' },
      fields: [
        ['what', 'what it is', 'screenshot of a restaurant’s instagram post'],
        ['fact', 'text in image', '“The corner table by the window is yours most nights from 5:30.”'],
        ['fact', 'place', 'Chez Colette, 12 Perry St, New York'],
        ['fact', 'where you were', 'Brooklyn, Thursday 11:42 pm'],
        ['summary', 'summary', 'A West Village bistro: ask for the window table, walk-ins welcome from 5:30.'],
        ['find', 'find it by', 'that french place with the window table / chez colette'],
        ['make', 'make into', ['a reminder', 'a plan for Thursday']],
      ],
    },
    article: {
      input: 'https://medium.com/@garrethow/how-to-remember-more', tag: 'article', busy: 'reading the article', img: LAND + 'cover-article.jpg', focus: [0.5, 0.5],
      meta: { title: 'How to remember more of what you read', desc: 'Reading without recall fades within days. A line of notes per chapter changes that.', m1: 'medium.com', m2: '2 min read' },
      fields: [
        ['fact', 'reading time', '2 min'],
        ['fact', 'author', 'Garret How'],
        ['what', 'what it is', 'article about memory and retention with practical tips'],
        ['summary', 'summary', 'We forget what we never try to recall. Write one line after each chapter and quiz yourself a day later.'],
        ['fact', 'key idea', 'Retrieval beats rereading.'],
        ['find', 'find it by', 'that article about remembering books / memory tips'],
        ['make', 'make into', ['flashcards', 'a study guide', 'a to-do list']],
      ],
    },
    paper: {
      input: 'https://arxiv.org/pdf/2307.03172', tag: 'pdf', busy: 'reading 18 pages', img: IMG + 'paper.png', focus: [0.5, 0.14],
      meta: { title: 'Lost in the Middle: How Language Models Use Long Contexts', desc: 'Liu et al. Language models use the start and end of a long input best.', m1: 'arxiv.org', m2: 'PDF' },
      fields: [
        ['fact', 'pages', '18'],
        ['what', 'what it is', 'research paper on how language models use long contexts'],
        ['summary', 'summary', 'Models use information at the start and end of a long input best; accuracy drops when the answer sits in the middle.'],
        ['fact', 'authors', 'Nelson F. Liu, Kevin Lin, John Hewitt and others'],
        ['fact', 'published', 'arXiv, July 2023'],
        ['find', 'find it by', 'the paper on long context windows / lost in the middle'],
        ['make', 'make into', ['flashcards', 'a study guide', 'a to-do list']],
      ],
    },
    tiktok: {
      input: 'https://www.tiktok.com/@sundaysupper/video/7391836274', tag: 'tiktok', busy: 'watching the video', img: IMG + 'shot-tiktok.jpg', focus: [0.5, 0.72],
      meta: { title: 'Tomato & mozzarella penne', desc: 'A 20-minute weeknight pasta: blistered tomatoes, torn mozzarella, basil.', m1: 'tiktok.com', m2: '0:58' },
      fields: [
        ['what', 'what it is', 'recipe video for a 20-minute tomato and mozzarella pasta'],
        ['fact', 'ingredients', 'penne, cherry tomatoes, mozzarella, basil, olive oil'],
        ['fact', 'on-screen text', '20-MINUTE DINNER, 5 INGREDIENTS'],
        ['fact', 'creator', '@sundaysupper'],
        ['summary', 'summary', 'Blister cherry tomatoes in olive oil, toss with penne and pasta water, finish with mozzarella and basil.'],
        ['find', 'find it by', 'that tomato pasta tiktok / quick weeknight pasta'],
        ['make', 'make into', ['a shopping list', 'a recipe card', 'a to-do list']],
      ],
    },
  };
  const ORDER = ['link', 'shot', 'article', 'paper', 'tiktok', 'reel', 'repo'];

  /* ---------------- the renderer ---------------- */
  const sides = { L: { top: 0, n: 0 }, R: { top: 0, n: 0 } };
  let nodeCount = 0;
  let titleFromAI = false;

  function setWord(key, p) {
    words.forEach((w) => {
      const on = w.dataset.ex === key;
      w.setAttribute('aria-pressed', String(on));
      w.style.setProperty('--p', on ? `${p}%` : '0%');
    });
  }

  function clearStage() {
    nodesEl.textContent = '';
    svg.textContent = '';
    card.classList.remove('is-in', 'is-note');
    resetMedia();
    stage.style.height = '';
    nodeCount = 0;
    titleFromAI = false;
  }

  /* ---------------- the card's picture ----------------
     Every run starts from an empty frame, and a slow image from an earlier run can't paint over a
     later one (mediaRun). A link gets MEDIA_DEADLINE to produce its own image; after that a
     placeholder for the kind of thing it is stands in, and if the real image turns up later it
     resolves over the placeholder. (v0.3: the card used to keep the previous example's picture.) */
  const MEDIA_DEADLINE = 750;
  const PH_DWELL = 550; // the least time a placeholder is shown before a late image replaces it
  let mediaRun = 0;

  // Pixel glyphs for the placeholders: 14×14, '#' = ink, drawn as crisp SVG runs.
  const GLYPHS = {
    page: ['##############', '#.#.#........#', '##############', '#............#', '#.#######....#', '#............#', '#.##########.#',
      '#.##########.#', '#.##########.#', '#............#', '#.#########..#', '#.#######....#', '#............#', '##############'],
    article: ['..##########..', '..#........#..', '..#.######.#..', '..#.######.#..', '..#........#..', '..#.######.#..', '..#........#..',
      '..#.######.#..', '..#........#..', '..#.####...#..', '..#........#..', '..#.######.#..', '..#........#..', '..##########..'],
    video: ['..............', '..............', '.############.', '##############', '#####.########', '#####..#######', '#####...######',
      '#####....#####', '#####...######', '#####..#######', '#####.########', '##############', '.############.', '..............'],
    repo: ['..............', '..............', '........#.....', '...#....#.#...', '..#.....#..#..', '.#.....#....#.', '#......#.....#',
      '#.....#......#', '.#....#.....#.', '..#...#....#..', '...#.#....#...', '.....#........', '..............', '..............'],
    book: ['..##########..', '..##.......#..', '..##.#####.#..', '..##.......#..', '..##.####..#..', '..##.......#..', '..##.......#..',
      '..##...#...#..', '..##..###..#..', '..##.#####.#..', '..##.......#..', '..##########..', '...#########..', '..............'],
    social: ['..............', '..............', '.############.', '#............#', '#.##########.#', '#............#', '#.#######....#',
      '#............#', '.##.#########.', '...##.........', '...#..........', '..............', '..............', '..............'],
    place: ['.....####.....', '...########...', '..###....###..', '.###......###.', '.##...##...##.', '.##..####..##.', '.##...##...##.',
      '.###......###.', '..###....###..', '...###..###...', '....######....', '.....####.....', '......##......', '..............'],
  };
  function glyphSvg(rows) {
    let d = '';
    rows.forEach((row, y) => {
      for (let x = 0; x < row.length;) {
        if (row[x] !== '#') { x++; continue; }
        let e = x;
        while (row[e] === '#') e++;
        d += `M${x} ${y}h${e - x}v1h-${e - x}z`;
        x = e;
      }
    });
    return `<svg viewBox="0 0 ${rows[0].length} ${rows.length}" shape-rendering="crispEdges" aria-hidden="true"><path d="${d}"/></svg>`;
  }
  // Places don't have a flavor of their own in the endpoint; their hosts give them away.
  const PLACE = /^((maps\.)?google\.[a-z.]+\/maps|maps\.google\.|maps\.apple\.com|maps\.app\.goo\.gl|goo\.gl\/maps|yelp\.[a-z.]+\/biz|opentable\.|resy\.com|tripadvisor\.|airbnb\.[a-z.]+\/rooms|booking\.com\/hotel)/i;
  const linkGlyph = (flavor, where) => (PLACE.test(where) ? 'place'
    : { repo: 'repo', video: 'video', book: 'book', social: 'social', article: 'article' }[flavor] || 'page');

  function resetMedia() {
    mediaRun++;
    pix.img = null;
    pix.lens = null;
    pix.ctx.setTransform(1, 0, 0, 1, 0, 0);
    pix.ctx.clearRect(0, 0, pix.canvas.width, pix.canvas.height);
    media.classList.remove('is-loading');
    media.querySelectorAll('.ph').forEach((n) => n.remove());
  }

  /** A stand-in picture for the kind of thing this is: a pixel glyph and the site for a link
      ({ glyph, label, favicon }), or a page for a document ({ page: true, tag, text?, title? }). */
  function showPlaceholder(spec) {
    media.classList.remove('is-loading');
    let ph = [...media.querySelectorAll('.ph')].find((n) => !n.classList.contains('is-out'));
    if (!ph) { ph = document.createElement('div'); ph.shownAt = performance.now(); media.appendChild(ph); }
    ph.className = spec.page ? 'ph ph-doc' : 'ph';
    ph.textContent = '';
    if (spec.page) {
      const page = document.createElement('div');
      page.className = 'ph-page';
      if (spec.title) { const h = document.createElement('b'); h.className = 'ph-title'; h.textContent = spec.title; page.appendChild(h); }
      if (spec.text) {
        for (const line of spec.text.split('\n').slice(0, 18)) {
          const p = document.createElement('p');
          if (/^#{1,6}\s/.test(line)) p.className = 'h';
          p.textContent = line.replace(/^#{1,6}\s+/, '').trim() || ' ';
          page.appendChild(p);
        }
      } else {
        page.insertAdjacentHTML('beforeend', '<i></i><i style="width:84%"></i><i></i><i style="width:62%"></i><i></i><i style="width:76%"></i><i></i><i style="width:58%"></i><i></i><i style="width:80%"></i>');
      }
      const ext = document.createElement('span');
      ext.className = 'tag ph-ext';
      ext.textContent = spec.tag;
      page.appendChild(ext);
      ph.appendChild(page);
    } else {
      ph.insertAdjacentHTML('beforeend', glyphSvg(GLYPHS[spec.glyph] || GLYPHS.page));
      const label = document.createElement('span');
      label.className = 'ph-label';
      if (spec.favicon) {
        const icon = new Image();
        icon.alt = '';
        icon.onerror = () => icon.remove();
        icon.src = spec.favicon;
        label.appendChild(icon);
      }
      label.append(spec.label || '');
      ph.appendChild(label);
    }
    return ph;
  }

  /** Show the card in its "reading" state. mode: 'loading' (a picture is on its way), 'media'
      (a placeholder will stand in) or 'note' (no picture at all). */
  function cardStart({ tag, title, m1: a = '', busy, mode = 'loading' }) {
    kindEl.textContent = tag;
    m1.textContent = a;
    m2.textContent = '';
    titleEl.innerHTML = '';
    const b = document.createElement('span');
    b.className = 'busy';
    b.dataset.spin = '';
    b.textContent = `| ${busy}…`;
    titleEl.appendChild(b);
    descEl.innerHTML = '<span class="skel">······························</span><span class="skel">·····················</span>';
    card.classList.toggle('is-note', mode === 'note');
    media.classList.toggle('is-loading', mode === 'loading');
    if (mode === 'note') { titleEl.textContent = title; descEl.textContent = ''; }
    card.dataset.pendingTitle = title || '';
    card.classList.add('is-in');
  }

  function cardMeta({ title, desc, m1: a, m2: b }) {
    if (title) { titleEl.textContent = title; titleFromAI = false; }
    if (desc !== undefined) descEl.textContent = desc || '';
    if (a !== undefined) m1.textContent = a;
    if (b !== undefined) m2.textContent = b;
  }

  /** Resolve an image into the card block by block. False if it failed or a newer run took over. */
  async function resolveImage(src, focus, t) {
    const run = mediaRun;
    let img;
    try { img = await S.loadImage(src); } catch { return false; }
    if (run !== mediaRun || (t && t.cancelled) || !img.naturalWidth) return false;
    // A placeholder that has only just appeared stays up a moment, so a late image reads as the
    // next step rather than a flicker.
    const ph = media.querySelector('.ph:not(.is-out)');
    const dwell = ph ? PH_DWELL - (performance.now() - ph.shownAt) : 0;
    if (dwell > 0) await new Promise((r) => setTimeout(r, dwell));
    if (run !== mediaRun) return false;
    pix.img = img;
    pix.focus = focus || [0.5, 0.5];
    pix.resize();
    media.classList.remove('is-loading');
    ph?.classList.add('is-out');
    for (const block of [26, 18, 12, 8, 5, 3, 1]) {
      if (run !== mediaRun) return false;
      pix.render(block);
      await (t ? S.wait(95, t) : new Promise((r) => setTimeout(r, 95)));
    }
    ph?.remove();
    return true;
  }

  function roundedElbow(ax, ay, nx, ny) {
    const dy = ny - ay;
    const mx = (ax + nx) / 2;
    if (Math.abs(dy) < 26) return `M${ax} ${ay} C${mx} ${ay} ${mx} ${ny} ${nx} ${ny}`;
    const r = 12;
    const dir = nx > ax ? 1 : -1;
    const sy = dy > 0 ? 1 : -1;
    return `M${ax} ${ay} H${mx - dir * r} Q${mx} ${ay} ${mx} ${ay + sy * r} V${ny - sy * r} Q${mx} ${ny} ${mx + dir * r} ${ny} H${nx}`;
  }

  function drawLeader(d, start, animate, duration = 520) {
    const ns = 'http://www.w3.org/2000/svg';
    const path = document.createElementNS(ns, 'path');
    path.setAttribute('d', d);
    svg.appendChild(path);
    const dot = document.createElementNS(ns, 'circle');
    dot.setAttribute('cx', start[0]); dot.setAttribute('cy', start[1]); dot.setAttribute('r', 2.6);
    svg.appendChild(dot);
    if (!animate || S.reduced()) return Promise.resolve();
    const len = path.getTotalLength();
    path.style.strokeDasharray = `${len}`;
    path.style.strokeDashoffset = `${len}`;
    const spark = document.createElementNS(ns, 'circle');
    spark.setAttribute('class', 'spark');
    spark.setAttribute('r', 4);
    svg.appendChild(spark);
    const t0 = performance.now();
    return new Promise((resolve) => {
      const frame = (now) => {
        const k = Math.min(1, (now - t0) / duration);
        const e = 1 - Math.pow(1 - k, 3);
        path.style.strokeDashoffset = `${len * (1 - e)}`;
        const p = path.getPointAtLength(len * e);
        spark.setAttribute('cx', p.x); spark.setAttribute('cy', p.y);
        if (k < 1) requestAnimationFrame(frame);
        else { path.style.strokeDasharray = ''; spark.style.transition = 'opacity .5s'; spark.style.opacity = '0'; setTimeout(() => spark.remove(), 520); resolve(); }
      };
      requestAnimationFrame(frame);
    });
  }

  function growStage(bottom) {
    if (narrow.matches) return;
    const need = Math.ceil(bottom + 44);
    if (need > (parseFloat(stage.style.height) || BASE_HEIGHT)) stage.style.height = `${need}px`;
  }

  /** Add one finding: a window beside (or, for "find it by", under) the card, its value decrypting in. */
  async function addField({ k, l, v }, animate = true, fast = false) {
    if (k === 'make') return addMake({ l, v }, animate);
    const find = k === 'find';
    const el = document.createElement('div');
    el.className = 'node win' + (find ? ' is-find' : '');
    el.innerHTML = `<div class="win-bar"><span></span><span>${find ? 'search' : '↳'}</span></div><div class="node-body"></div>`;
    el.querySelector('.win-bar span').textContent = l;
    Object.assign(el.dataset, { k, l, v: JSON.stringify(v) });
    const body = el.querySelector('.node-body');
    body.textContent = v;
    nodesEl.appendChild(el);
    // An image, doc or note has no title of its own: the AI's reading becomes the card title.
    if (k === 'what' && !titleFromAI && card.dataset.pendingTitle !== undefined && card.dataset.aiTitle === '1') {
      titleFromAI = true;
      S.decrypt(titleEl, v.charAt(0).toUpperCase() + v.slice(1));
    }
    if (!narrow.matches) {
      const cardL = card.offsetLeft, cardT = card.offsetTop, cardW = card.offsetWidth, cardH = card.offsetHeight;
      const sw = stage.clientWidth;
      const w = el.offsetWidth, h = el.offsetHeight;
      let d, start, left, top;
      if (find) {
        const cx = cardL + cardW / 2;
        top = Math.max(cardT + cardH + 48, 0);
        left = cx - w / 2;
        el.style.setProperty('--origin', 'center top');
        start = [cx, cardT + cardH];
        d = `M${cx} ${cardT + cardH} V${top}`;
      } else {
        const side = sides.R.n <= sides.L.n ? 'R' : 'L';
        const gap = Math.min(92, Math.max(36, (sw - cardW - 2 * w) / 2 - 36));
        const s = sides[side];
        if (!s.n) s.top = cardT + 2;
        top = s.top;
        s.top += h + 18;
        const idx = s.n++;
        left = side === 'R' ? cardL + cardW + gap : cardL - gap - w;
        el.style.setProperty('--origin', side === 'R' ? 'left center' : 'right center');
        const ay = Math.min(cardT + cardH - 26, cardT + 44 + idx * 92);
        const ax = side === 'R' ? cardL + cardW : cardL;
        const nx = side === 'R' ? left : left + w;
        start = [ax, ay];
        d = roundedElbow(ax, ay, nx, top + 10.5);
      }
      el.style.left = `${left}px`;
      el.style.top = `${top}px`;
      growStage(top + h);
      body.textContent = '';
      await drawLeader(d, start, animate, fast ? 260 : 520);
    } else {
      body.textContent = '';
    }
    el.classList.add('is-in');
    nodeCount++;
    if (k === 'summary' && descEl.querySelector('.skel')) S.decrypt(descEl, v);
    if (!animate) { body.textContent = v; return; }
    const decrypting = S.decrypt(body, v, fast ? { duration: Math.min(650, 220 + v.length * 4) } : undefined);
    if (!fast) await decrypting;
  }

  /* "make into" (beta): what Stash can turn this save into, as buttons, in a window of its own
     colour under "find it by". The transformations aren't in this demo, and the window says so. */
  async function addMake({ l, v }, animate = true) {
    const el = document.createElement('div');
    el.className = 'node win is-make';
    el.innerHTML = '<div class="win-bar"><span></span><span class="beta">beta</span></div><div class="node-body"><div class="mk-opts"></div><p class="mk-note px" role="status"></p></div>';
    el.querySelector('.win-bar span').textContent = l;
    Object.assign(el.dataset, { k: 'make', l, v: JSON.stringify(v) });
    const opts = el.querySelector('.mk-opts');
    const buttons = v.map((label) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'mk';
      b.setAttribute('aria-pressed', 'false');
      b.textContent = label;
      opts.appendChild(b);
      return b;
    });
    nodesEl.appendChild(el);
    if (!narrow.matches) {
      // Under "find it by" if it's there, else under the card; joined by a short leader.
      const above = [...nodesEl.querySelectorAll('.node.is-find')].pop();
      const cx = card.offsetLeft + card.offsetWidth / 2;
      const anchor = above ? above.offsetTop + above.offsetHeight : card.offsetTop + card.offsetHeight;
      const top = anchor + (above ? 30 : 48);
      el.style.setProperty('--origin', 'center top');
      el.style.left = `${cx - el.offsetWidth / 2}px`;
      el.style.top = `${top}px`;
      growStage(top + el.offsetHeight);
      buttons.forEach((b) => (b.style.visibility = 'hidden'));
      await drawLeader(`M${cx} ${anchor} V${top}`, [cx, anchor], animate, 300);
    } else {
      buttons.forEach((b) => (b.style.visibility = 'hidden'));
    }
    el.classList.add('is-in');
    for (const b of buttons) {
      b.style.visibility = '';
      if (animate && !S.reduced()) { b.classList.add('is-new'); await new Promise((r) => setTimeout(r, 120)); }
    }
  }
  // One delegated handler for every "make into" button, live or example.
  nodesEl.addEventListener('click', (e) => {
    const b = e.target.closest('.mk');
    if (!b) return;
    const node = b.closest('.is-make');
    node.querySelectorAll('.mk').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
    node.querySelector('.mk-note').textContent = `${b.textContent}: coming soon in the beta`;
  });
  // What a live save could be made into, by the kind of thing it is.
  const MAKE = {
    repo: ['a setup checklist', 'a cheat sheet'],
    video: ['a summary', 'flashcards', 'a to-do list'],
    social: ['a summary', 'a to-do list'],
    book: ['a reading plan', 'flashcards'],
    place: ['an itinerary', 'a reminder'],
    image: ['a to-do list', 'a reminder', 'flashcards'],
    note: ['a to-do list', 'a reminder'],
  };
  const makeFor = (kind) => MAKE[kind] || ['flashcards', 'a study guide', 'a to-do list'];

  function resetSides() { sides.L = { top: 0, n: 0 }; sides.R = { top: 0, n: 0 }; }

  /* ---------------- example loop ---------------- */
  let tok = null;
  let paused = false;
  let inView = false;
  let live = false;
  let current = S.param('ex') && EX[S.param('ex')] ? S.param('ex') : 'tiktok';

  function showDemoText(text) {
    form.classList.toggle('is-demo', !!text);
    demo.textContent = text || '';
  }

  async function playExample(key, t) {
    const ex = EX[key];
    current = key;
    setWord(key, 0);
    clearStage();
    resetSides();
    card.dataset.aiTitle = '0';
    showDemoText('');
    form.classList.remove('show-kbd', 'press');
    await S.wait(650, t);
    form.classList.add('show-kbd');
    await S.wait(480, t);
    showDemoText(ex.input);
    await S.wait(900, t);
    form.classList.remove('show-kbd');
    form.classList.add('press');
    await S.wait(200, t);
    form.classList.remove('press');

    cardStart({ tag: ex.tag, title: ex.meta.title, m1: ex.meta.m1, busy: ex.busy, mode: 'loading' });
    await S.wait(380, t);
    showDemoText('');
    await S.wait(900, t);
    await resolveImage(ex.img, ex.focus, t);
    cardMeta(ex.meta);
    await S.wait(520, t);
    for (const [k, l, v] of ex.fields) {
      if (t.cancelled) throw S.CANCEL;
      await addField({ k, l, v });
      await S.wait(420, t);
    }
    const hold = 5200, step = 80;
    for (let e = 0; e < hold; e += step) { setWord(key, Math.round((e / hold) * 100)); await S.wait(step, t); }
    setWord(key, 100);
  }

  async function runExamples(startKey) {
    if (tok) tok.cancelled = true;
    const t = (tok = S.token());
    t.paused = paused; t.hidden = !inView;
    let i = ORDER.indexOf(startKey);
    try {
      for (;;) { await playExample(ORDER[i], t); i = (i + 1) % ORDER.length; }
    } catch (err) { if (err !== S.CANCEL) throw err; }
  }
  function stopExamples() { if (tok) { tok.cancelled = true; tok = null; } }

  async function showFinal(key) {
    const ex = EX[key];
    setWord(key, 100);
    clearStage(); resetSides();
    card.dataset.aiTitle = '0';
    showDemoText('');
    cardStart({ tag: ex.tag, title: ex.meta.title, m1: ex.meta.m1, busy: ex.busy, mode: 'loading' });
    const run = mediaRun;
    try {
      const img = await S.loadImage(ex.img);
      if (run === mediaRun) { pix.img = img; pix.focus = ex.focus; pix.resize(); media.classList.remove('is-loading'); pix.render(1); }
    } catch { /* keep the dither */ }
    cardMeta(ex.meta);
    for (const [k, l, v] of ex.fields) await addField({ k, l, v }, false);
  }

  /* ---------------- live: the visitor's own save ---------------- */
  let file = null;
  let fileUrl = null;
  let running = null;      // AbortController of a live run
  let hasResult = false;
  let resultFor = null;    // what the shown result was made from
  let resumeTimer = 0;

  function say(html, cls = '') {
    const old = [...lines.children];
    old.forEach((el) => {
      el.classList.remove('is-on');
      el.classList.add('is-out');
      setTimeout(() => el.remove(), 600);
    });
    if (!html) return null;
    const p = document.createElement('p');
    p.className = `try-line ${cls}`.trim();
    p.innerHTML = html;
    lines.appendChild(p);
    requestAnimationFrame(() => requestAnimationFrame(() => p.classList.add('is-on')));
    return p;
  }

  const SEND_CHIP = '<span class="send-chip" role="img" aria-label="Send"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5M6 11l6-6 6 6"/></svg></span>';
  const INVITE = 'Give it a try! Paste a link, drop in an image, or add a doc (under 2 MB) and watch the enrichment:';

  function whatIsIt() {
    if (file) return S.fileKind(file) === 'image' ? 'image' : 'doc';
    const v = input.value.trim();
    if (!v) return '';
    return S.looksLikeUrl(v) ? 'link' : 'note';
  }

  function refresh() {
    const kind = whatIsIt();
    send.disabled = !kind || !!running;
    form.classList.toggle('has-value', !!kind);
    if (!live) return;
    const subject = file || input.value.trim();
    if (hasResult && subject === resultFor) return; // the result and its status line stay put
    if (kind && !running) {
      const prev = lines.lastElementChild;
      if (!prev || prev.dataset.kind !== kind) {
        const p = say(`Now press ${SEND_CHIP} to watch this ${kind} get more valuable`);
        if (p) p.dataset.kind = kind;
      }
    } else if (!kind && !running && !hasResult) {
      const prev = lines.lastElementChild;
      if (!prev || prev.dataset.kind !== 'invite') { const p = say(INVITE); if (p) p.dataset.kind = 'invite'; }
    }
  }

  function enterLive() {
    clearTimeout(resumeTimer);
    if (live) return;
    live = true;
    stopExamples();
    words.forEach((w) => { w.setAttribute('aria-pressed', 'false'); w.style.setProperty('--p', '0%'); });
    showDemoText('');
    form.classList.add('is-live');
    if (!hasResult) { clearStage(); resetSides(); }
    const p = say(INVITE);
    if (p) p.dataset.kind = 'invite';
    refresh();
  }

  function leaveLive() {
    live = false;
    form.classList.remove('is-live', 'has-value');
    say('');
    hasResult = false;
    if (!S.reduced()) runExamples(current);
  }

  function setFile(f) {
    if (!f) return;
    if (f.size > S.MAX_FILE_BYTES) { say(`That file is ${S.prettyBytes(f.size)}. Try one under 2 MB.`, 'is-error'); return; }
    const ok = /^image\/(png|jpeg|webp|gif)$/.test(f.type) || f.type === 'application/pdf' || /\.(pdf|txt|md|markdown)$/i.test(f.name) || /^text\//.test(f.type);
    if (!ok) { say(/hei[cf]/i.test(f.type + f.name) ? 'HEIC photos aren’t supported in the demo yet. Try a JPG or PNG.' : 'Try a JPG, PNG, WebP, PDF or text file.', 'is-error'); return; }
    file = f;
    if (fileUrl) URL.revokeObjectURL(fileUrl);
    fileUrl = URL.createObjectURL(f);
    input.value = '';
    chip.hidden = false;
    form.classList.add('has-file');
    chipName.textContent = f.name;
    chipSize.textContent = S.prettyBytes(f.size);
    if (/^image\//.test(f.type)) { chipThumb.style.backgroundImage = `url("${fileUrl}")`; chipThumb.textContent = ''; }
    else { chipThumb.style.backgroundImage = ''; chipThumb.textContent = extLabel(f); }
    enterLive();
    refresh();
  }

  /** PDF, MD, TXT…: a document's kind, short enough for a tag. */
  function extLabel(f) {
    if (/pdf/i.test(f.type + f.name)) return 'PDF';
    const ext = (f.name.match(/\.([a-z0-9]+)$/i) || [])[1] || 'txt';
    return /^(md|markdown)$/i.test(ext) ? 'MD' : ext.slice(0, 4).toUpperCase();
  }

  function clearFile() {
    file = null;
    if (fileUrl) { URL.revokeObjectURL(fileUrl); fileUrl = null; }
    chip.hidden = true;
    form.classList.remove('has-file');
    fileInput.value = '';
    refresh();
  }

  async function runLive() {
    const kind = whatIsIt();
    if (!kind) return;
    if (running) running.abort();
    const controller = (running = new AbortController());
    const started = performance.now();
    const text = input.value.trim();
    resultFor = file || text;
    let payload;
    try { payload = file ? await S.fileToPayload(file) : kind === 'link' ? { url: text } : { text }; }
    catch { say('That file couldn’t be read. Try another one.', 'is-error'); running = null; refresh(); return; }

    form.classList.add('press');
    setTimeout(() => form.classList.remove('press'), 180);
    send.disabled = true;
    clearStage(); resetSides();
    hasResult = true;
    const status = say('<span data-spin>|</span> reading…', 'is-status');
    let host = '';
    let where = '';
    if (kind === 'link') {
      try {
        const u = new URL(/^https?:/i.test(text) ? text : `https://${text}`);
        host = u.hostname.replace(/^www\./, '');
        where = host + u.pathname;
      } catch { host = where = text; }
    }
    card.dataset.aiTitle = kind === 'link' ? '0' : '1';
    const run = mediaRun;
    const isPdf = kind === 'doc' && /pdf/i.test(file.type + file.name);
    let linkPh = null; // a link's placeholder, refined as the stream says more about it
    if (kind === 'image') {
      cardStart({ tag: 'image', title: file.name, m1: 'your image', busy: 'looking at the image' });
      resolveImage(fileUrl, [0.5, 0.5], null);
    } else if (kind === 'doc') {
      const ext = extLabel(file);
      cardStart({ tag: isPdf ? 'pdf' : 'doc', title: file.name, m1: S.prettyBytes(file.size), busy: 'reading the document', mode: 'media' });
      if (isPdf) showPlaceholder({ page: true, tag: ext });
      else {
        // A text file can preview itself: its first lines, on a page.
        file.text()
          .then((t) => { if (run === mediaRun) showPlaceholder({ page: true, tag: ext, text: t.slice(0, 1600) }); })
          .catch(() => { if (run === mediaRun) showPlaceholder({ page: true, tag: ext }); });
      }
    } else if (kind === 'note') {
      cardStart({ tag: 'note', title: text.length > 120 ? text.slice(0, 118) + '…' : text, m1: 'your note', busy: 'reading the note', mode: 'note' });
    } else {
      cardStart({ tag: 'link', title: host, m1: host, busy: 'reading the page' });
      linkPh = { glyph: linkGlyph('generic', where), label: host, favicon: null };
      setTimeout(() => { if (run === mediaRun && !pix.img) showPlaceholder(linkPh); }, MEDIA_DEADLINE);
    }
    // Refresh a link's placeholder if it's already standing in (and no real image has landed).
    const refreshPh = () => { if (linkPh && run === mediaRun && !pix.img && media.querySelector('.ph:not(.is-out)')) showPlaceholder(linkPh); };
    if (kind !== 'link') setTimeout(() => { if (titleEl.querySelector('.busy')) { titleEl.textContent = card.dataset.pendingTitle; } }, 300);

    // Findings can arrive faster than their windows animate in: queue them so each still lands
    // with its line, in order, without waiting for the previous one to finish decrypting.
    const queue = [];
    let draining = null;
    const drain = async () => {
      while (queue.length) { await addField(queue.shift(), true, true); await new Promise((r) => setTimeout(r, 70)); }
      draining = null;
    };
    const push = (f) => { queue.push(f); if (!draining) draining = drain(); };
    // Facts the page itself gave (language, license, stars, pages, reading time…) arrive in one burst
    // before the model speaks: they share one "details" window.
    const FORMAT = { stars: (v) => `${v} stars`, pages: (v) => `${v} pages`, 'reading time': (v) => `${v} read`, author: (v) => `by ${v}` };
    let instant = [];
    let instantTimer = 0;
    let modelStarted = false;
    const flushInstant = () => {
      clearTimeout(instantTimer);
      if (!instant.length) return;
      push({ k: 'fact', l: 'details', v: instant.join(', ') });
      instant = [];
    };
    const setStatus = (text) => { const st = lines.querySelector('.is-status [data-spin]')?.parentElement; if (st) st.innerHTML = `<span data-spin>|</span> ${text}`; };
    let failed = false;
    let networkDone = 0;
    await S.enrich(payload, (event, data) => {
      if (controller.signal.aborted) return;
      if (event === 'start') {
        if (linkPh && data.flavor) { linkPh.glyph = linkGlyph(data.flavor, where); refreshPh(); }
      } else if (event === 'meta') {
        setStatus('found it, gathering the background…');
        if (!linkPh) {
          // Only a PDF sends meta besides a link: its own title, which then stays the card's title.
          if (data.title) { cardMeta({ title: data.title }); card.dataset.aiTitle = '0'; }
        } else {
          cardMeta({ title: data.title || undefined, desc: data.description || '', m1: data.site || host });
        }
        if (linkPh) {
          if (data.flavor) linkPh.glyph = linkGlyph(data.flavor, where);
          if (data.favicon) linkPh.favicon = data.favicon;
          if (data.image) {
            refreshPh();
            // GitHub's cards put the repo's name at the left edge; most others centre what matters.
            const focus = /^github\.com\//.test(where) ? [0.36, 0.5] : [0.5, 0.42];
            resolveImage(data.image, focus, null).then((ok) => { if (!ok && run === mediaRun && !pix.img) showPlaceholder(linkPh); });
          } else if (run === mediaRun && !pix.img) showPlaceholder(linkPh); // no picture of its own: stand in now
        } else if (isPdf && data.title && run === mediaRun) {
          showPlaceholder({ page: true, tag: 'PDF', title: data.title }); // the PDF's own title, on its page
        }
      } else if (event === 'field') {
        if (!modelStarted && data.k === 'fact') {
          instant.push((FORMAT[data.l] || ((v) => v))(data.v));
          clearTimeout(instantTimer);
          instantTimer = setTimeout(flushInstant, 120);
          return;
        }
        if (!modelStarted) { modelStarted = true; flushInstant(); setStatus('reading what it says…'); }
        push(data);
      } else if (event === 'done') {
        networkDone = performance.now();
      } else if (event === 'error') {
        failed = true;
        media.classList.remove('is-loading');
        if (linkPh && run === mediaRun && !pix.img) showPlaceholder(linkPh);
        if (titleEl.querySelector('.busy')) titleEl.textContent = card.dataset.pendingTitle || '';
        descEl.textContent = '';
        say(`${escapeHtml(data.message || 'Something went wrong.')} <button type="button" data-again>Try another one</button>`, 'is-error');
      }
    }, controller.signal);
    flushInstant();
    // Last, what it could be made into (beta), chosen by the kind of thing it is.
    if (!failed && !controller.signal.aborted) push({ k: 'make', l: 'make into', v: makeFor(kind === 'link' ? linkPh.glyph : kind) });
    if (draining) await draining;
    if (controller.signal.aborted) return;
    running = null;
    if (!failed) {
      const secs = (((networkDone || performance.now()) - started) / 1000).toFixed(1);
      say(`Gathered in ${secs} s. Stash keeps all of this for every save. <button type="button" data-again>Try another one</button>`, 'is-status');
    }
    status?.remove();
    if (titleEl.querySelector('.busy')) titleEl.textContent = card.dataset.pendingTitle || host;
    if (descEl.querySelector('.skel')) descEl.textContent = '';
    refresh();
  }

  const escapeHtml = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  /* ---------------- wiring ---------------- */
  input.addEventListener('focus', enterLive);
  input.addEventListener('input', () => { if (file && input.value) clearFile(); refresh(); });
  input.addEventListener('blur', () => {
    clearTimeout(resumeTimer);
    resumeTimer = setTimeout(() => {
      if (document.activeElement === input || running || hasResult || whatIsIt()) return;
      leaveLive();
    }, 5000);
  });
  form.addEventListener('submit', (e) => { e.preventDefault(); runLive(); });
  attach.addEventListener('click', () => { enterLive(); fileInput.click(); });
  fileInput.addEventListener('change', () => setFile(fileInput.files && fileInput.files[0]));
  chipX.addEventListener('click', () => { clearFile(); input.focus(); });
  lines.addEventListener('click', (e) => {
    if (!e.target.closest('[data-again]')) return;
    hasResult = false;
    clearFile();
    input.value = '';
    clearStage(); resetSides();
    const p = say(INVITE);
    if (p) p.dataset.kind = 'invite';
    input.focus();
    refresh();
  });

  let dragDepth = 0;
  stage.addEventListener('dragenter', (e) => { e.preventDefault(); dragDepth++; stage.classList.add('is-dragging'); enterLive(); });
  stage.addEventListener('dragover', (e) => { e.preventDefault(); });
  stage.addEventListener('dragleave', () => { if (--dragDepth <= 0) { dragDepth = 0; stage.classList.remove('is-dragging'); } });
  stage.addEventListener('drop', (e) => {
    e.preventDefault();
    dragDepth = 0;
    stage.classList.remove('is-dragging');
    const f = e.dataTransfer.files && e.dataTransfer.files[0];
    if (f) { setFile(f); return; }
    const uri = (e.dataTransfer.getData('text/uri-list') || e.dataTransfer.getData('text/plain') || '').split('\n')[0].trim();
    if (uri) { clearFile(); input.value = uri; input.focus(); refresh(); }
  });

  words.forEach((w) => w.addEventListener('click', () => {
    live = false;
    form.classList.remove('is-live', 'has-value');
    say('');
    hasResult = false;
    if (running) { running.abort(); running = null; }
    if (S.reduced()) { current = w.dataset.ex; showFinal(current); return; }
    runExamples(w.dataset.ex);
  }));

  toggle.addEventListener('click', () => {
    paused = !paused;
    toggle.setAttribute('aria-pressed', String(paused));
    toggle.textContent = paused ? 'play' : 'pause';
    if (tok) tok.paused = paused;
  });

  window.addEventListener('resize', () => {
    clearTimeout(runExamples._r);
    runExamples._r = setTimeout(() => {
      if (!nodesEl.children.length || narrow.matches) return;
      // Re-place the windows that are already out, without animating them again.
      const done = [...nodesEl.children].map((el) => ({ k: el.dataset.k, l: el.dataset.l, v: JSON.parse(el.dataset.v) }));
      nodesEl.textContent = ''; svg.textContent = ''; resetSides(); stage.style.height = '';
      done.reduce((p, f) => p.then(() => addField(f, false)), Promise.resolve());
    }, 160);
  });

  if (S.reduced()) {
    toggle.hidden = true;
    showFinal(current);
  } else {
    S.watch(stage, (seen) => {
      inView = seen;
      if (tok) tok.hidden = !seen;
      if (seen && !tok && !live) runExamples(current);
    }, 0.25);
    document.addEventListener('visibilitychange', () => { if (tok) tok.hidden = document.hidden || !inView; });
  }
  refresh();
})();
