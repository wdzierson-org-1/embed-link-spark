import { applyShareHead, brief, buildShareCard, handleShare, renderShareHead, type SharedSave } from './share';

const SHELL = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Stash — save it fast, find it when you need it</title>
    <meta name="description" content="Capture links, PDFs, screenshots, and voice notes." />
    <meta name="author" content="Stash" />
    <link rel="icon" href="/favicon.ico?v=a4" sizes="48x48">
    <meta property="og:title" content="Stash — save it fast, find it when you need it" />
    <meta property="og:description" content="Capture links." />
    <meta property="og:type" content="website" />
    <meta property="og:url" content="https://www.gostash.it/" />
    <meta property="og:image" content="https://www.gostash.it/og-v2.jpg" />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:image" content="https://www.gostash.it/og-v2.jpg" />
    <script type="module" crossorigin src="/assets/index-abc.js"></script>
  </head>
  <body><div id="root"></div></body>
</html>`;

const save: SharedSave = {
  title: 'Introducing System One Models & Jev — TypeSafe AI Blog',
  description: 'TypeSafe AI is an AI lab building machine-native intelligence infrastructure for automation.',
  summary: 'A long summary. With several sentences.',
  type: 'link',
  file_path: 'covers/abc.jpg',
  username: 'will',
};
const URL = 'https://www.gostash.it/s/Xk3mN9pQ2a';

describe('the share card', () => {
  it('carries the save’s title, its description and its picture', () => {
    const card = buildShareCard(save, URL);
    expect(card.title).toBe('Introducing System One Models & Jev — TypeSafe AI Blog');
    expect(card.description).toBe(save.description);
    expect(card.image).toBe('https://uqqsgmwkvslaomzxptnp.supabase.co/storage/v1/object/public/stash-media/covers/abc.jpg');
    expect(card.largeImage).toBe(true);
  });

  it('falls back to the summary’s first sentence, then to Stash’s own line and image', () => {
    // A first sentence counts once it is 20 characters long (so "Dr." and the like don't end one)
    expect(buildShareCard({ ...save, description: null, summary: 'A long summary that says a lot. With several sentences.' }, URL).description).toBe('A long summary that says a lot.');
    expect(buildShareCard({ ...save, description: null }, URL).description).toBe('A long summary. With several sentences.');
    const bare = buildShareCard({ ...save, title: null, description: null, summary: null, file_path: null, type: 'text' }, URL);
    expect(bare.title).toBe('A save on Stash');
    expect(bare.description).toMatch(/Saved with Stash/);
    expect(bare.image).toBe('https://www.gostash.it/og-v2.jpg');
    expect(bare.largeImage).toBe(false);
  });

  it('keeps a rescued preview URL as the picture and knows audio has none', () => {
    expect(buildShareCard({ ...save, file_path: 'https://img.youtube.com/vi/x/hqdefault.jpg' }, URL).image).toBe('https://img.youtube.com/vi/x/hqdefault.jpg');
    expect(buildShareCard({ ...save, type: 'audio', file_path: 'audio/a.m4a' }, URL).image).toBe('https://www.gostash.it/og-v2.jpg');
  });

  it('keeps descriptions brief, cut at a word', () => {
    const long = 'word '.repeat(80).trim();
    const cut = brief(long, 200);
    expect(cut.length).toBeLessThanOrEqual(200);
    expect(cut.endsWith('…')).toBe(true);
    expect(cut).not.toMatch(/wor…$/);
    expect(brief('  spaced   out\n text ')).toBe('spaced out text');
  });
});

describe('the head', () => {
  it('escapes attribute values', () => {
    const head = renderShareHead(buildShareCard({ ...save, title: 'Tom & "Jerry" <3' }, URL));
    expect(head).toContain('content="Tom &amp; &quot;Jerry&quot; &lt;3"');
    expect(head).toContain('<title>Tom &amp; &quot;Jerry&quot; &lt;3 · Stash</title>');
    expect(head).toContain('<meta name="twitter:card" content="summary_large_image" />');
  });

  it('replaces the site’s card in the shell and leaves the rest alone', () => {
    const html = applyShareHead(SHELL, renderShareHead(buildShareCard(save, URL)));
    expect(html.match(/property="og:title"/g)).toHaveLength(1);
    expect(html).toContain(`<meta property="og:title" content="${save.title!.replace('&', '&amp;')}" />`);
    expect(html).not.toContain('save it fast, find it when you need it');
    expect(html).not.toContain('og:image:width');
    expect(html).toContain('<meta charset="UTF-8" />');
    expect(html).toContain('/assets/index-abc.js');
    expect(html).toContain('<link rel="icon"');
    expect(html.indexOf('og:title')).toBeGreaterThan(html.indexOf('name="viewport"'));
  });
});

describe('the handler', () => {
  const response = () => {
    const headers: Record<string, string> = {};
    let code = 0;
    let body = '';
    return {
      res: { setHeader: (k: string, v: string) => { headers[k] = v; }, status: (c: number) => ({ send: (b: string) => { code = c; body = b; } }) },
      read: () => ({ headers, code, body }),
    };
  };
  const fetcher = (rows: SharedSave[] | null) =>
    vi.fn(async (input: string | URL | Request) => {
      const url = String(input);
      if (url.includes('/rest/v1/rpc/shared_item')) return new Response(JSON.stringify(rows ?? []), { status: 200 });
      if (url.endsWith('/app.html')) return new Response(SHELL, { status: 200 });
      return new Response('', { status: 404 });
    }) as unknown as typeof fetch;

  it('answers the shell with the save’s card for a crawler', async () => {
    const { res, read } = response();
    const fetch = fetcher([save]);
    await handleShare({ query: { token: 'Xk3mN9pQ2a' }, headers: { host: 'www.gostash.it' } }, res, fetch);
    const { headers, code, body } = read();
    expect(code).toBe(200);
    expect(headers['Content-Type']).toContain('text/html');
    expect(body).toContain('<meta property="og:url" content="https://www.gostash.it/s/Xk3mN9pQ2a" />');
    expect(body).toContain('og:description');
    expect(body).toContain('/assets/index-abc.js');
    expect(String((fetch as unknown as { mock: { calls: unknown[][] } }).mock.calls[1][0])).toBe('https://www.gostash.it/app.html');
  });

  it('answers 404 with no card for a dead or malformed token, and never fetches the shell', async () => {
    for (const token of ['Xk3mN9pQ2a', 'nope']) {
      const { res, read } = response();
      const fetch = fetcher([]);
      await handleShare({ query: { token }, headers: { host: 'www.gostash.it' } }, res, fetch);
      expect(read().code).toBe(404);
      expect(read().body).toContain('This share link no longer works.');
      expect((fetch as unknown as { mock: { calls: unknown[][] } }).mock.calls.some((c) => String(c[0]).endsWith('/app.html'))).toBe(false);
    }
  });

  it('does not take the shell from a forged host', async () => {
    const { res, read } = response();
    const fetch = fetcher([save]);
    await handleShare({ query: { token: 'Xk3mN9pQ2a' }, headers: { host: 'evil.example' } }, res, fetch);
    expect(read().code).toBe(200);
    expect(String((fetch as unknown as { mock: { calls: unknown[][] } }).mock.calls[1][0])).toBe('https://www.gostash.it/app.html');
  });
});
