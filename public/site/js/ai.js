/* "Your stash, inside every AI you use": two harnesses, each playing one conversation.
   Cursor: a design repo saved to Stash (pbakaus/impeccable, real) drives an edit to a pricing card.
   Claude: hotels saved to Stash (illustrative names) become a trip-planning answer.
   Tabs auto-advance; everything pauses offscreen and freezes on its last frame for reduced motion. */
(() => {
  const S = window.Stash;
  const demo = document.querySelector('[data-ai-demo]');
  if (!demo) return;
  const tabs = [...document.querySelectorAll('[data-ai-tab]')];
  const tabList = document.querySelector('.ai-tabs');
  const panes = { cursor: demo.querySelector('[data-aw="cursor"]'), claude: demo.querySelector('[data-aw="claude"]') };
  const IMG = '/site/img/';
  const SYMBOL = '<svg class="ico" viewBox="0 0 724 764" aria-hidden="true"><use href="#st4sh-symbol"/></svg>';
  const GH = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 .5a11.5 11.5 0 0 0-3.6 22.4c.6.1.8-.3.8-.6v-2c-3.2.7-3.9-1.5-3.9-1.5-.5-1.3-1.3-1.7-1.3-1.7-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.7-1.6-2.6-.3-5.3-1.3-5.3-5.7 0-1.3.5-2.3 1.2-3.1-.1-.3-.5-1.5.1-3.1 0 0 1-.3 3.2 1.2a11 11 0 0 1 5.8 0c2.2-1.5 3.2-1.2 3.2-1.2.6 1.6.2 2.8.1 3.1.8.8 1.2 1.9 1.2 3.1 0 4.4-2.7 5.4-5.3 5.7.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6A11.5 11.5 0 0 0 12 .5z"/></svg>';

  const sleep = (ms, t) => S.wait(ms, t);
  const { typeInto, streamInto } = S;
  const el = (tag, cls, html) => { const n = document.createElement(tag); if (cls) n.className = cls; if (html !== undefined) n.innerHTML = html; requestAnimationFrame(() => n.isConnected && S.follow(n)); return n; };

  /* ---------------- Cursor ---------------- */
  const cw = {
    msgs: panes.cursor.querySelector('[data-cw-msgs]'),
    code: panes.cursor.querySelector('[data-cw-code]'),
    status: panes.cursor.querySelector('[data-cw-status]'),
    agent: panes.cursor.querySelector('.cw-agent.is-active'),
  };
  const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const hl = (src) => esc(src)
    .replace(/(&quot;|")([^"]*?)("|&quot;)/g, '<span class="s">"$2"</span>')
    .replace(/\b(export|function|return|const)\b/g, '<span class="k">$1</span>')
    .replace(/(&lt;\/?)([a-z][a-z0-9]*)/g, '$1<span class="t">$2</span>')
    .replace(/\b(className|key)=/g, '<span class="a">$1</span>=');
  // [marker, text]: ' ' unchanged, '-' removed in the edit, '+' added by the edit.
  const DIFF = [
    [' ', 'export function PricingCard({ plan }: Props) {'],
    [' ', '  return ('],
    ['-', '    <div className="rounded-lg border p-5 shadow-md">'],
    ['+', '    <div className="rounded-2xl border p-6">'],
    ['-', '      <h3 className="text-sm text-gray-400">{plan.name}</h3>'],
    ['+', '      <h3 className="text-base font-medium text-ink">{plan.name}</h3>'],
    ['-', '      <p className="text-4xl font-bold">${plan.price}</p>'],
    ['+', '      <p className="text-4xl font-semibold tabular-nums">${plan.price}</p>'],
    ['-', '      <ul className="mt-3 space-y-1 text-gray-400">'],
    ['+', '      <ul className="mt-4 space-y-2 text-muted">'],
    [' ', '        {plan.features.map((f) => <li key={f}>{f}</li>)}'],
    [' ', '      </ul>'],
    ['-', '      <button className="mt-4 h-8 w-full bg-violet-500">'],
    ['+', '      <button className="mt-6 h-11 w-full rounded-full bg-ink">'],
    [' ', '        Get started'],
    [' ', '      </button>'],
    [' ', '    </div>'],
    [' ', '  );'],
    [' ', '}'],
  ];
  function renderCode(stage) {
    // stage 0: before the edit; 1: removed lines marked; 2: the edit applied (adds shown)
    cw.code.textContent = '';
    let n = 0;
    for (const [mk, text] of DIFF) {
      if (mk === '+' && stage < 1) continue;
      const line = el('div', 'cw-line' + (stage >= 1 && mk === '-' ? ' is-del' : '') + (stage >= 1 && mk === '+' ? ' is-add' : ''));
      line.innerHTML = `<span class="ln">${++n}</span><span class="mk">${stage >= 1 && mk !== ' ' ? mk : ' '}</span><span class="tx">${hl(text)}</span>`;
      if (mk === '+') line.dataset.add = '1';
      cw.code.appendChild(line);
    }
  }
  async function playCursor(t, still) {
    cw.msgs.textContent = '';
    cw.agent.classList.remove('is-done');
    cw.status.textContent = 'Waiting for you';
    renderCode(0);
    const user = cw.msgs.appendChild(el('div', 'cw-user reveal'));
    const prompt = 'Use that design repo I saved to Stash last week to polish the pricing card.';
    if (still) user.textContent = prompt; else { await sleep(500, t); await typeInto(user, prompt, t); }
    cw.status.textContent = 'Searching Stash';
    const step = cw.msgs.appendChild(el('div', 'cw-step reveal', `${SYMBOL}<span>Searching Stash</span><code>search_stash("design repo")</code>`));
    if (!still) await sleep(1100, t);
    step.querySelector('span').textContent = 'Searched Stash';
    cw.msgs.appendChild(el('div', 'cw-result reveal', `<span class="gh">${GH}</span><b>pbakaus/impeccable</b><small>saved Sep 28 · “the design language that makes your AI harness better at design”</small>`));
    if (!still) await sleep(700, t);
    const said = cw.msgs.appendChild(el('div', 'cw-text reveal'));
    const reply = 'Found it in your Stash. Running Impeccable’s polish pass on PricingCard.tsx: one type scale, tabular numbers for the price, a 44px button, and no light gray text.';
    if (still) said.textContent = reply; else await streamInto(said, reply, t, 18);
    cw.status.textContent = 'Editing PricingCard.tsx';
    if (still) { renderCode(1); } else {
      await sleep(400, t);
      renderCode(1);
      const adds = [...cw.code.querySelectorAll('[data-add]')];
      adds.forEach((l) => (l.style.display = 'none'));
      for (const l of adds) { await sleep(420, t); l.style.display = ''; l.classList.add('is-new'); }
      await sleep(500, t);
    }
    cw.msgs.appendChild(el('div', 'cw-edit reveal', '<span>PricingCard.tsx</span><span class="add">+5</span><span class="del">−5</span><span class="fx"><span>Undo</span><span>Keep</span></span>'));
    if (!still) await sleep(500, t);
    const done = cw.msgs.appendChild(el('div', 'cw-text reveal'));
    const close = 'Done. Want the same pass on the rest of the pricing page?';
    if (still) done.textContent = close; else await streamInto(done, close, t, 18);
    cw.agent.classList.add('is-done');
    cw.status.textContent = 'Ready for review';
  }

  /* ---------------- Claude ---------------- */
  const cl = { thread: panes.claude.querySelector('[data-cl-thread]') };
  const HOTELS = [
    { img: 'hotel-courtyard.jpg', name: 'Casa do Pátio', area: 'Alfama', from: 'saved from Instagram, Sep 12', note: 'the tiled courtyard!' },
    { img: 'hotel-rooftops.jpg', name: 'Miradouro 22', area: 'Graça', from: 'saved from an article, Aug 30', note: 'rooftop bar, river views' },
    { img: 'hotel-garden.jpg', name: 'Jardim Escondido', area: 'Príncipe Real', from: 'saved from TikTok, Sep 21', note: '8 rooms, plunge pool' },
  ];
  async function playClaude(t, still) {
    cl.thread.textContent = '';
    const user = cl.thread.appendChild(el('div', 'cl-user reveal'));
    const prompt = 'Planning Lisbon in November. Pull up the hotels I saved to Stash recently and help me pick one.';
    if (still) user.textContent = prompt; else { await sleep(500, t); await typeInto(user, prompt, t); }
    const tool = cl.thread.appendChild(el('div', 'cl-tool reveal', `<span class="sp"></span>${SYMBOL}<span>Searching Stash</span><em>hotels in Lisbon, saved recently</em>`));
    if (!still) await sleep(1300, t);
    tool.classList.add('is-done');
    tool.querySelector('span:not(.sp)').textContent = 'Searched Stash';
    tool.querySelector('em').textContent = '3 results';
    const cards = cl.thread.appendChild(el('div', 'cl-cards'));
    for (const h of HOTELS) {
      const c = cards.appendChild(el('div', 'cl-card reveal'));
      c.innerHTML = `<div class="im" style="background-image:url(${IMG}${h.img})"></div><div class="bd"><b></b><small></small><small></small><q></q></div>`;
      c.querySelector('b').textContent = h.name;
      const smalls = c.querySelectorAll('small');
      smalls[0].textContent = h.area; smalls[1].textContent = h.from;
      c.querySelector('q').textContent = h.note;
      if (!still) await sleep(260, t);
    }
    const answer = cl.thread.appendChild(el('div', 'cl-text reveal'));
    const text = 'You saved three. For November I’d book **Casa do Pátio**: it’s in Alfama, a short walk from the two restaurants you saved there, and your note on it says “the tiled courtyard!”. **Miradouro 22** is the pick for rooftop views, and **Jardim Escondido** is the quietest, though its plunge pool won’t see much use in November.';
    if (still) answer.innerHTML = text.replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>'); else { await sleep(300, t); await streamInto(answer, text, t, 15); }
  }

  /* ---------------- tabs + loop ---------------- */
  const PLAY = { cursor: playCursor, claude: playClaude };
  const DUR = { cursor: 21, claude: 19 };
  let current = S.param('ai') === 'claude' ? 'claude' : 'cursor';
  let tok = null;
  let inView = false;

  function select(name) {
    current = name;
    tabs.forEach((b) => {
      const on = b.dataset.aiTab === name;
      b.setAttribute('aria-selected', String(on));
      if (on) { b.style.setProperty('--dur', `${DUR[name]}s`); const bar = b.querySelector('.ai-tab-bar'); bar.style.animation = 'none'; bar.getBoundingClientRect(); bar.style.animation = ''; }
    });
    Object.entries(panes).forEach(([k, p]) => p.classList.toggle('is-on', k === name));
  }

  async function loop(start) {
    if (tok) tok.cancelled = true;
    const t = (tok = S.token());
    t.hidden = !inView;
    let name = start;
    try {
      for (;;) {
        select(name);
        await PLAY[name](t, false);
        await sleep(3200, t);
        name = name === 'cursor' ? 'claude' : 'cursor';
      }
    } catch (err) { if (err !== S.CANCEL) throw err; }
  }

  tabs.forEach((b) => b.addEventListener('click', () => {
    if (S.reduced()) { select(b.dataset.aiTab); PLAY[b.dataset.aiTab](S.token(), true); return; }
    loop(b.dataset.aiTab);
  }));

  if (S.reduced()) {
    select(current);
    playCursor(S.token(), true);
    playClaude(S.token(), true);
    tabList.classList.add('paused');
    return;
  }
  select(current);
  renderCode(0);
  S.watch(demo, (seen) => {
    inView = seen;
    tabList.classList.toggle('paused', !seen);
    if (tok) tok.hidden = !seen;
    if (seen && !tok) loop(current);
  }, 0.3);
  document.addEventListener('visibilitychange', () => { if (tok) tok.hidden = document.hidden || !inView; });
})();
