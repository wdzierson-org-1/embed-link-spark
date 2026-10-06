/* The live enrichment endpoint (supabase/functions/homepage-enrich): a POST whose response is a
   Server-Sent Events stream (start → meta → field… → done | error). EventSource can't POST,
   so this reads the stream by hand. Shared by the "try it" composer and the hero pool. */
(() => {
  const S = window.Stash;
  S.ENRICH_URL = 'https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/homepage-enrich';
  S.MAX_FILE_BYTES = 2 * 1024 * 1024;

  /** Calls on(event, data) for every event; resolves when the stream ends. */
  S.enrich = async (payload, on, signal) => {
    let res;
    try {
      res = await fetch(S.ENRICH_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        signal,
      });
    } catch (err) {
      if (err && err.name === 'AbortError') return;
      on('error', { code: 'network', message: 'Couldn’t reach Stash. Check your connection and try again.' });
      return;
    }
    if (!res.ok || !res.body) {
      let message = 'Something went wrong. Try another one.';
      try { message = (await res.json()).error || message; } catch { /* not JSON */ }
      on('error', { code: res.status, message });
      return;
    }
    const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
    let buffer = '';
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += value;
        let cut;
        while ((cut = buffer.indexOf('\n\n')) >= 0) {
          const block = buffer.slice(0, cut);
          buffer = buffer.slice(cut + 2);
          let event = 'message';
          let data = '';
          for (const line of block.split('\n')) {
            if (line.startsWith('event:')) event = line.slice(6).trim();
            else if (line.startsWith('data:')) data += line.slice(5).trim();
          }
          if (data) { try { on(event, JSON.parse(data)); } catch { /* malformed event */ } }
        }
      }
    } catch (err) {
      if (!(err && err.name === 'AbortError')) on('error', { code: 'stream', message: 'The connection dropped. Try again.' });
    }
  };

  S.looksLikeUrl = (text) => {
    const t = text.trim();
    return !/\s/.test(t) && (/^https?:\/\/\S+$/i.test(t) || /^[\w-]+(\.[\w-]+)+(\/\S*)?$/.test(t));
  };

  S.fileKind = (file) =>
    /^image\//.test(file.type) ? 'image' : file.type === 'application/pdf' || /\.pdf$/i.test(file.name) ? 'doc' : 'doc';

  S.fileToPayload = (file) => new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve({ file: { name: file.name, type: file.type, data: String(reader.result).replace(/^data:[^,]*,/, '') } });
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(file);
  });

  S.prettyBytes = (n) => (n < 1024 ? `${n} B` : n < 1024 * 1024 ? `${Math.round(n / 1024)} KB` : `${(n / 1024 / 1024).toFixed(1)} MB`);
})();
