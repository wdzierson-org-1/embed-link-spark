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
  const mediaImg = card.querySelector('.scard-img');
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

  const LAND = '../../../src/assets/landing/';
  const IMG = '2026-10-06-stashe-homepage/img/';

  /* ---------------- examples ---------------- */
  const EX = {
    link: {
      input: 'https://github.com/charmbracelet/gum', tag: 'repo', busy: 'reading the readme', img: IMG + 'repo.png', focus: [0.5, 0.5],
      meta: { title: 'charmbracelet/gum', desc: 'A tool for glamorous shell scripts.', m1: 'github.com', m2: 'Go' },
      fields: [
        ['fact', 'language', 'Go'],
        ['fact', 'license', 'MIT'],
        ['what', 'what it is', 'a kit of prompts, pickers, spinners and inputs for shell scripts'],
        ['summary', 'summary', 'Lets plain shell scripts ask questions and offer choices, with no Go to write.'],
        ['fact', 'install', 'brew install gum'],
        ['find', 'find it by', 'that pretty terminal prompt thing / shell script pickers'],
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
      ],
    },
    tiktok: {
      input: 'https://www.tiktok.com/@sundaysupper/video/7391836274', tag: 'video', busy: 'watching the video', img: LAND + 'cover-recipe.jpg', focus: [0.62, 0.5],
      meta: { title: 'Tomato & mozzarella penne', desc: 'A 20-minute weeknight pasta: blistered tomatoes, torn mozzarella, basil.', m1: 'tiktok.com', m2: '0:58' },
      fields: [
        ['what', 'what it is', 'recipe video for a 20-minute tomato and mozzarella pasta'],
        ['fact', 'ingredients', 'penne, cherry tomatoes, mozzarella, basil, olive oil'],
        ['fact', 'on-screen text', '20-MINUTE DINNER, 5 INGREDIENTS'],
        ['fact', 'creator', '@sundaysupper'],
        ['summary', 'summary', 'Blister cherry tomatoes in olive oil, toss with penne and pasta water, finish with mozzarella and basil.'],
        ['find', 'find it by', 'that tomato pasta tiktok / quick weeknight pasta'],
      ],
    },
  };
  const ORDER = ['link', 'shot', 'article', 'paper', 'tiktok'];

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
    media.classList.remove('is-loading');
    media.querySelector('.doc-glyph')?.remove();
    mediaImg.hidden = true;
    mediaImg.removeAttribute('src');
    stage.style.height = '';
    nodeCount = 0;
    titleFromAI = false;
  }

  /** Show the card in its "reading" state. mode: 'image' | 'loading' | 'doc' | 'note'. */
  function cardStart({ tag, title, m1: a = '', busy, mode, docLabel }) {
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
    if (mode === 'doc') {
      const g = document.createElement('div');
      g.className = 'doc-glyph';
      g.innerHTML = '<i></i><i style="width:80%"></i><i></i><i style="width:64%"></i><i></i><i style="width:72%"></i><b></b>';
      g.querySelector('b').textContent = docLabel || 'PDF';
      media.appendChild(g);
    }
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

  async function resolveImage(src, focus, t) {
    try { await pix.set(src, focus); } catch { return false; }
    media.classList.remove('is-loading');
    if (t && t.cancelled) return false;
    for (const block of [26, 18, 12, 8, 5, 3, 1]) {
      pix.render(block);
      await (t ? S.wait(95, t) : new Promise((r) => setTimeout(r, 95)));
    }
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
    const find = k === 'find';
    const el = document.createElement('div');
    el.className = 'node win' + (find ? ' is-find' : '');
    el.innerHTML = `<div class="win-bar"><span></span><span>${find ? 'search' : '↳'}</span></div><div class="node-body"></div>`;
    el.querySelector('.win-bar span').textContent = l;
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
    try { await pix.set(ex.img, ex.focus); media.classList.remove('is-loading'); pix.render(1); } catch { /* keep the dither */ }
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
    else { chipThumb.style.backgroundImage = ''; chipThumb.textContent = /pdf/i.test(f.type + f.name) ? 'PDF' : 'TXT'; }
    enterLive();
    refresh();
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
    if (kind === 'link') { try { host = new URL(/^https?:/i.test(text) ? text : `https://${text}`).hostname.replace(/^www\./, ''); } catch { host = text; } }
    card.dataset.aiTitle = kind === 'link' ? '0' : '1';
    if (kind === 'image') {
      cardStart({ tag: 'image', title: file.name, m1: 'your image', busy: 'looking at the image', mode: 'loading' });
      resolveImage(fileUrl, [0.5, 0.5], null);
    } else if (kind === 'doc') {
      cardStart({ tag: /pdf/i.test(file.type + file.name) ? 'pdf' : 'doc', title: file.name, m1: S.prettyBytes(file.size), busy: 'reading the document', mode: 'doc', docLabel: /pdf/i.test(file.type + file.name) ? 'PDF' : 'TXT' });
    } else if (kind === 'note') {
      cardStart({ tag: 'note', title: text.length > 120 ? text.slice(0, 118) + '…' : text, m1: 'your note', busy: 'reading the note', mode: 'note' });
    } else {
      cardStart({ tag: 'link', title: host, m1: host, busy: 'reading the page', mode: 'loading' });
    }
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
      if (event === 'meta') {
        setStatus('found it, gathering the background…');
        cardMeta({ title: data.title || undefined, desc: data.description || '', m1: data.site || host });
        if (data.image) resolveImage(data.image, [0.5, 0.42], null).then((ok) => { if (!ok) media.classList.remove('is-loading'); });
        else media.classList.remove('is-loading');
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
        if (titleEl.querySelector('.busy')) titleEl.textContent = card.dataset.pendingTitle || '';
        descEl.textContent = '';
        say(`${escapeHtml(data.message || 'Something went wrong.')} <button type="button" data-again>Try another one</button>`, 'is-error');
      }
    }, controller.signal);
    flushInstant();
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
      const done = [...nodesEl.children].map((el) => ({ k: el.classList.contains('is-find') ? 'find' : 'fact', l: el.querySelector('.win-bar span').textContent, v: el.querySelector('.node-body').textContent }));
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
