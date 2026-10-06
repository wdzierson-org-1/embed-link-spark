/* Site chrome shared by the homepage and its pages (Chrome extension, MCP, iPhone): the logo
   sprite, the nav, the footer and the prototype's review panel, written once here so the pages
   can't drift apart. Loaded first among the scripts at the end of <body> (it only touches the
   DOM; page.js, which runs next, wires the spot-colour and copy buttons it adds). */
(() => {
  const me = document.currentScript;
  const folder = new URL('../', me.src);
  const homeUrl = new URL('../2026-10-06-stashe-homepage.html', folder).href;
  const pageUrl = (name) => new URL(name, folder).href;
  const onHome = !!document.querySelector('.hero');
  const home = (hash = '') => (onHome ? hash || '#top' : homeUrl + hash);
  const here = document.body.dataset.page || 'home';

  /* The ST4SH kit as a sprite: the wordmark and the A/4 symbol, both in currentColor. */
  document.body.insertAdjacentHTML('afterbegin', `<svg class="sprite" aria-hidden="true" focusable="false" width="0" height="0" style="position:absolute"><symbol id="st4sh-wordmark" viewBox="30 30 3095.4 730"><g fill="currentColor" transform="translate(32 32) scale(1)"> <g transform="translate(-42.814 713.012) scale(1 -1)"> <path transform="translate(0 0)" fill-rule="evenodd" d="M42.814 207.887H163.883Q170.446 149.361 215.834 117.46Q261.223 85.559 340.587 85.559Q382.401 85.559 414.364 97.972Q446.328 110.385 463.734 134.142Q481.141 157.899 481.141 190.287Q481.141 220.113 466.578 238.239Q452.016 256.364 425.034 268.139Q398.052 279.915 349.502 293.34Q323.801 301.052 297.101 307.765Q277.389 313.765 256.963 319.052Q191.963 338.915 151.032 360.133Q110.101 381.352 86.095 418.433Q62.089 455.514 62.089 513.389Q62.089 570.976 93.739 616.488Q125.389 662 181.976 687.506Q238.563 713.012 310.3 713.012Q385.761 713.012 444.642 685.862Q503.523 658.713 539.672 607.419Q575.822 556.125 584.098 486.263H463.465Q453.627 544.352 411.951 579.396Q370.275 614.441 308.887 614.441Q270.498 614.441 241.885 603.097Q213.272 591.753 198.003 570.99Q182.733 550.227 182.733 522.401Q182.733 493.713 196.584 476.3Q210.434 458.887 238.347 446.468Q266.26 434.049 320.822 418.761L364.073 406.911Q452.486 382.336 503.124 355.911Q553.761 329.486 577.842 291.905Q601.923 254.324 601.923 198.587Q601.923 134.287 569.78 86.425Q537.636 38.563 478.699 12.775Q419.761 -13.012 341.737 -13.012Q251.575 -13.012 185.775 12.85Q119.976 38.713 83.538 88.294Q47.101 137.875 42.814 207.887Z"/> <path transform="translate(610 0)" fill-rule="evenodd" d="M264.465 596.554H35.113V700H614.324V596.554H384.972V0H264.465Z"/> <path transform="translate(1150 0)" fill-rule="evenodd" d="M0 0 448 700H568V280H660V177H568V0H448V177H232L119 0ZM297 280H448V516Z"/> <path transform="translate(1835 0)" fill-rule="evenodd" d="M42.814 207.887H163.883Q170.446 149.361 215.834 117.46Q261.223 85.559 340.587 85.559Q382.401 85.559 414.364 97.972Q446.328 110.385 463.734 134.142Q481.141 157.899 481.141 190.287Q481.141 220.113 466.578 238.239Q452.016 256.364 425.034 268.139Q398.052 279.915 349.502 293.34Q323.801 301.052 297.101 307.765Q277.389 313.765 256.963 319.052Q191.963 338.915 151.032 360.133Q110.101 381.352 86.095 418.433Q62.089 455.514 62.089 513.389Q62.089 570.976 93.739 616.488Q125.389 662 181.976 687.506Q238.563 713.012 310.3 713.012Q385.761 713.012 444.642 685.862Q503.523 658.713 539.672 607.419Q575.822 556.125 584.098 486.263H463.465Q453.627 544.352 411.951 579.396Q370.275 614.441 308.887 614.441Q270.498 614.441 241.885 603.097Q213.272 591.753 198.003 570.99Q182.733 550.227 182.733 522.401Q182.733 493.713 196.584 476.3Q210.434 458.887 238.347 446.468Q266.26 434.049 320.822 418.761L364.073 406.911Q452.486 382.336 503.124 355.911Q553.761 329.486 577.842 291.905Q601.923 254.324 601.923 198.587Q601.923 134.287 569.78 86.425Q537.636 38.563 478.699 12.775Q419.761 -13.012 341.737 -13.012Q251.575 -13.012 185.775 12.85Q119.976 38.713 83.538 88.294Q47.101 137.875 42.814 207.887Z"/> <path transform="translate(2470 0)" fill-rule="evenodd" d="M74.077 700H194.584V411.073H543.692V700H664.199V0H543.692V307.627H194.584V0H74.077Z"/> </g></g></symbol><symbol id="st4sh-symbol" viewBox="0 0 724 764"><path fill="currentColor" fill-rule="evenodd" transform="translate(32 732) scale(1.0 -1.0)" d="M0 0 448 700H568V280H660V177H568V0H448V177H232L119 0ZM297 280H448V516Z"/></symbol></svg>`);

  const fill = (selector, html) => { const slot = document.querySelector(selector); if (slot) slot.outerHTML = html; };

  fill('[data-site-nav]', `
<nav class="nav" aria-label="Main">
  <div class="nav-group"><a class="brand" href="${home()}" aria-label="Stash, home"><svg class="wordmark" aria-hidden="true"><use href="#st4sh-wordmark"/></svg></a></div>
  <div class="nav-group nav-mid"><a href="${home('#how')}">Try it</a><a href="${home('#phone')}">On your phone</a><a href="${home('#ai')}">With your AI</a><a href="${home('#anywhere')}">Anywhere</a></div>
  <div class="nav-group"><a class="nav-signin" href="${home('#start')}">Sign in</a><a class="nav-cta" href="${home('#start')}">Get Stash</a></div>
</nav>`);

  /* Footer: the brand, then one column per job — set-up guides; the iPhone app (in beta, with a
     sign-up for the App Store release); contact and the legal pages. */
  const current = (name) => (here === name ? ' aria-current="page"' : '');
  fill('[data-site-footer]', `
<footer class="wrap foot">
  <div class="foot-brand">
    <a class="foot-mark" href="${home()}" aria-label="Stash, home"><svg class="wordmark" aria-hidden="true"><use href="#st4sh-wordmark"/></svg></a>
    <p>Smarter saving.<br>$4.99 a month.</p>
  </div>
  <nav class="foot-col" aria-labelledby="foot-setup">
    <h2 class="px" id="foot-setup">set up</h2>
    <a href="${pageUrl('extension.html')}"${current('extension')}>Chrome extension</a>
    <a href="${pageUrl('mcp.html')}"${current('mcp')}>Connect your AI (MCP)</a>
  </nav>
  <div class="foot-col foot-app">
    <h2 class="px" id="foot-app">iphone app</h2>
    <a href="${pageUrl('iphone.html')}"${current('iphone')}>Stash for iPhone</a>
    <p>In beta now. Get one email, the day it’s on the App Store.</p>
    <form class="notify" data-notify novalidate aria-labelledby="foot-app">
      <input type="email" name="email" placeholder="you@example.com" autocomplete="email" aria-label="Your email" required>
      <button type="submit">Notify me</button>
    </form>
  </div>
  <nav class="foot-col" aria-labelledby="foot-co">
    <h2 class="px" id="foot-co">company</h2>
    <a href="mailto:will@dzierson.com">Contact</a>
    <a href="https://www.gostash.it/terms">Terms</a>
    <a href="https://www.gostash.it/privacy">Privacy</a>
  </nav>
  <p class="foot-legal">© 2026 Stash</p>
</footer>`);

  const label = { home: 'stash home v0.4', extension: 'stash v0.4 · extension', mcp: 'stash v0.4 · mcp', iphone: 'stash v0.4 · iphone' }[here];
  document.body.insertAdjacentHTML('beforeend', `
<aside class="review" aria-label="Prototype controls">
  <span>${label}</span>
  <span role="group" aria-label="Spot colour">
    <button data-spot-btn="lime" aria-pressed="true"><i style="background:#a3f53b"></i>lime</button>
    <button data-spot-btn="violet" aria-pressed="false"><i style="background:#6d5bd0"></i>violet</button>
  </span>
</aside>`);

  /* "Notify me": there's no list behind it yet, so the form says so plainly instead of pretending. */
  document.querySelectorAll('[data-notify]').forEach((form) => {
    const input = form.querySelector('input');
    const msg = document.createElement('p');
    msg.className = 'notify-msg';
    msg.setAttribute('role', 'status');
    form.after(msg);
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.value.trim())) {
        msg.textContent = 'That doesn’t look like an email address. Check it and try again.';
        msg.className = 'notify-msg is-error';
        input.focus();
        return;
      }
      form.classList.add('is-sent');
      msg.innerHTML = 'We’ll email you once, the day it’s out. <span class="tag">prototype: not sent</span>';
      msg.className = 'notify-msg is-done';
    });
  });
})();
