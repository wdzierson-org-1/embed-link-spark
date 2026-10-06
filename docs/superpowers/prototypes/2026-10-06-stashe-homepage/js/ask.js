/* Your AI, over MCP: a Claude-style chat asking about things saved to Stash and answering from
   them, one exchange at a time, on a loop. Built into every [data-ask] element (the homepage
   panel and mcp.html share this one source). Reduced motion and #still show the first exchange,
   finished. The saves are the same illustrative ones the rest of the page shows. */
(() => {
  const S = window.Stash;
  const hosts = [...document.querySelectorAll('[data-ask]')];
  if (!hosts.length) return;

  const SYMBOL = '<svg class="ico" viewBox="0 0 724 764" aria-hidden="true"><use href="#st4sh-symbol"/></svg>';
  const TALKS = [
    {
      q: 'What was that design repo I saved last month?',
      tool: 'search_stash("design repo")',
      a: 'It’s **pbakaus/impeccable**. You saved it on Sep 28 with the note “the design language that makes your AI harness better at design,” and Stash has its README if you want to set it up.',
    },
    {
      q: 'What seat am I in on Friday’s flight?',
      tool: 'search_stash("boarding pass")',
      a: '**14C**, on Northline 214 from Boston to San Francisco. Boarding is at 6:25 AM from gate **B12**. Stash read it off the boarding pass you screenshotted.',
    },
    {
      q: 'Which hotels did I save for Lisbon?',
      tool: 'search_stash("lisbon hotels")',
      a: 'Three: **Casa do Pátio** in Alfama (your note says “the tiled courtyard!”), **Miradouro 22** in Graça for the rooftop, and **Jardim Escondido** in Príncipe Real.',
    },
  ];

  const make = (tag, cls) => { const n = document.createElement(tag); n.className = cls; return n; };

  async function talk(thread, x, t, still) {
    thread.textContent = '';
    const user = thread.appendChild(make('p', 'cl-user'));
    if (still) user.textContent = x.q; else { await S.wait(600, t); await S.typeInto(user, x.q, t, 34); }
    const tool = thread.appendChild(make('p', 'cl-tool'));
    tool.innerHTML = `<span class="sp"></span>${SYMBOL}<span>Searching Stash</span><em></em>`;
    tool.querySelector('em').textContent = x.tool;
    if (!still) await S.wait(1250, t);
    tool.classList.add('is-done');
    tool.querySelector('span:not(.sp)').textContent = 'Searched Stash';
    const answer = thread.appendChild(make('p', 'mcp-ans'));
    if (still) answer.innerHTML = S.bold(x.a);
    else { await S.wait(250, t); await S.streamInto(answer, x.a, t, 13); }
  }

  hosts.forEach((host) => {
    host.innerHTML = '<div class="mcp-demo win ask"><div class="win-bar"><span>claude.ai</span><span>stash connected</span></div><div class="mcp-demo-body cl-thread"></div></div>';
    const thread = host.querySelector('.cl-thread');
    // The first exchange starts out finished, so the window is never empty; the loop moves on from it.
    talk(thread, TALKS[0], S.token(), true);
    if (S.reduced()) return;
    let tok = null, inView = false, i = 1;
    const run = async () => {
      const t = (tok = S.token());
      t.hidden = !inView || document.hidden;
      try {
        await S.wait(2600, t);
        for (;;) { await talk(thread, TALKS[i++ % TALKS.length], t, false); await S.wait(3400, t); }
      } catch (err) { if (err !== S.CANCEL) throw err; }
    };
    S.watch(host, (seen) => { inView = seen; if (tok) tok.hidden = !seen || document.hidden; if (seen && !tok) run(); }, 0.25);
    document.addEventListener('visibilitychange', () => { if (tok) tok.hidden = document.hidden || !inView; });
  });
})();
