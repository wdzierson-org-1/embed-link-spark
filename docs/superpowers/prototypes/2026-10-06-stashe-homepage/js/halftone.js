/* Halftone field (after React Bits Pro "Halftone Wave", written from scratch): a grid of dots
   sized by drifting fractal noise. Two uses:
   - the closing section, where the dots knock out around the headline like a print knockout;
   - the "with your AI" panel, as still dot clouds behind the windows (typesafe's dither). */
(() => {
  const S = window.Stash;

  // Value noise with a fixed seed, so every render of the page matches.
  const P = new Uint8Array(512);
  (() => {
    const p = Array.from({ length: 256 }, (_, i) => i);
    let seed = 1337;
    for (let i = 255; i > 0; i--) {
      seed = (seed * 16807) % 2147483647;
      const j = seed % (i + 1);
      [p[i], p[j]] = [p[j], p[i]];
    }
    for (let i = 0; i < 512; i++) P[i] = p[i & 255];
  })();
  const fade = (t) => t * t * (3 - 2 * t);
  const hash = (x, y) => P[(P[x & 255] + y) & 511] / 255;
  function noise(x, y) {
    const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi;
    const a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1);
    const u = fade(xf), v = fade(yf);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }
  function fbm(x, y, oct) {
    let s = 0, amp = 0.5, f = 1, norm = 0;
    for (let i = 0; i < oct; i++) { s += amp * noise(x * f, y * f); norm += amp; amp *= 0.5; f *= 2; }
    return s / norm;
  }
  const smooth = (a, b, v) => { const t = S.clamp((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };

  /** Draws an SVG <symbol> (paths under translate/scale groups) into a 2D context with Path2D,
      so its shape can be sampled without tainting the canvas. */
  function drawSymbol(g, symbol, x, y, w, h) {
    const [vx, vy, vw, vh] = symbol.getAttribute('viewBox').split(/[\s,]+/).map(Number);
    const s = Math.min(w / vw, h / vh);
    g.save();
    g.translate(x + (w - vw * s) / 2, y + (h - vh * s));
    g.scale(s, s);
    g.translate(-vx, -vy);
    const walk = (node) => {
      for (const child of node.children) {
        g.save();
        for (const [, fn, args] of (child.getAttribute('transform') || '').matchAll(/(translate|scale)\(([^)]*)\)/g)) {
          const [a, b] = args.split(/[\s,]+/).map(Number);
          if (fn === 'translate') g.translate(a, b || 0); else g.scale(a, b === undefined || Number.isNaN(b) ? a : b);
        }
        if (child.tagName.toLowerCase() === 'path') g.fill(new Path2D(child.getAttribute('d')), child.getAttribute('fill-rule') === 'evenodd' ? 'evenodd' : 'nonzero');
        else walk(child);
        g.restore();
      }
    };
    walk(symbol);
    g.restore();
  }

  class Halftone {
    constructor(canvas, o) {
      this.canvas = canvas; this.ctx = canvas.getContext('2d'); this.o = o;
      this.knock = []; this.pointer = null; this.mask = null;
      this.resize();
    }
    resize() {
      const r = this.canvas.getBoundingClientRect();
      this.w = r.width; this.h = r.height;
      this.dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.canvas.width = Math.round(this.w * this.dpr); this.canvas.height = Math.round(this.h * this.dpr);
      if (this.o.knockout) {
        const cr = this.canvas.getBoundingClientRect();
        this.knock = this.o.knockout().map((el) => {
          const b = el.getBoundingClientRect();
          return { x0: b.left - cr.left, y0: b.top - cr.top, x1: b.right - cr.left, y1: b.bottom - cr.top };
        });
      }
      // A shape the dots fill in completely: the wordmark, set into its band (1 px per sample).
      this.mask = null;
      if (this.o.maskFrom) {
        const area = this.o.maskFrom.area.getBoundingClientRect();
        const cr = this.canvas.getBoundingClientRect();
        const m = document.createElement('canvas');
        m.width = Math.max(1, Math.round(this.w)); m.height = Math.max(1, Math.round(this.h));
        const g = m.getContext('2d');
        g.fillStyle = '#000';
        const pad = Math.max(16, area.width * 0.02);
        drawSymbol(g, this.o.maskFrom.symbol, area.left - cr.left + pad, area.top - cr.top + 8, area.width - pad * 2, area.height - 34);
        this.mask = { data: g.getImageData(0, 0, m.width, m.height).data, w: m.width, h: m.height,
          y0: area.top - cr.top, y1: area.bottom - cr.top };
      }
    }
    maskAt(x, y) {
      const m = this.mask;
      if (!m) return 0;
      const xi = x | 0, yi = y | 0;
      if (xi < 0 || yi < 0 || xi >= m.w || yi >= m.h) return 0;
      return m.data[(yi * m.w + xi) * 4 + 3] / 255;
    }
    render(t) {
      const { ctx, w, h, dpr, o } = this;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = S.css('--ascii') || '#000';
      const cell = w < 700 && o.cellSmall ? o.cellSmall : o.cell, maxR = cell * o.dot * 0.5;
      const cols = Math.ceil(w / cell) + 1, rows = Math.ceil(h / cell) + 1;
      const sc = o.scale / Math.max(w, 1);
      ctx.beginPath();
      for (let j = 0; j < rows; j++) {
        for (let i = 0; i < cols; i++) {
          const x = i * cell + (j % 2 ? cell / 2 : 0), y = j * cell;
          const n = fbm(x * sc + t * o.sx, y * sc + t * o.sy, o.octaves);
          let v = smooth(o.min, o.max, n);
          const inside = this.maskAt(x, y);
          if (inside) v = Math.max(v, inside * (0.86 + 0.14 * n));
          else if (this.mask && y > this.mask.y0 && y < this.mask.y1) v *= 0.32; // quiet around the letters
          if (this.knock.length) {
            let k = 1;
            for (const r of this.knock) {
              const dx = Math.max(r.x0 - x, 0, x - r.x1), dy = Math.max(r.y0 - y, 0, y - r.y1);
              const d = Math.hypot(dx, dy);
              k = Math.min(k, smooth(o.knockPad * 0.25, o.knockPad, d));
            }
            v *= k;
          }
          if (this.pointer) {
            const dx = x - this.pointer.x, dy = y - this.pointer.y;
            v = Math.min(1, v + 0.55 * Math.exp(-(dx * dx + dy * dy) / (2 * 110 * 110)));
          }
          const r = v * maxR;
          if (r < 0.35) continue;
          ctx.moveTo(x + r, y);
          ctx.arc(x, y, r, 0, Math.PI * 2);
        }
      }
      ctx.fill();
    }
  }

  /* Closing section: drifting, with a knockout under the type and a little pointer heat. */
  const close = document.querySelector('.s-close');
  if (close) {
    const canvas = close.querySelector('canvas');
    // v0.2: denser field, and the wordmark set in dots along the bottom (duotone, like a print).
    const ht = new Halftone(canvas, {
      cell: 12, cellSmall: 6, dot: 1, scale: 3.2, octaves: 3, min: 0.3, max: 0.7, sx: 0.035, sy: 0.02, knockPad: 40,
      knockout: () => [...close.querySelectorAll('.t-giant, .close-cta .btn, .close-cta .px, .foot a, .foot span, .foot .wordmark')],
      maskFrom: { area: close.querySelector('.close-mark'), symbol: document.getElementById('st4sh-wordmark') },
    });
    let t = 0, raf = 0, live = false, inView = false;
    const frame = () => {
      raf = 0;
      if (!live) return;
      t += 1 / 60;
      ht.render(t);
      raf = requestAnimationFrame(frame);
    };
    const sync = () => { live = inView && !document.hidden && !S.reduced(); if (live && !raf) raf = requestAnimationFrame(frame); };
    close.addEventListener('pointermove', (e) => {
      const r = canvas.getBoundingClientRect();
      ht.pointer = { x: e.clientX - r.left, y: e.clientY - r.top };
      if (S.reduced()) ht.render(t);
    });
    close.addEventListener('pointerleave', () => { ht.pointer = null; if (S.reduced()) ht.render(t); });
    document.fonts.ready.then(() => { ht.resize(); ht.render(0); });
    S.watch(close, (seen) => { inView = seen; sync(); }, 0.02);
    document.addEventListener('visibilitychange', sync);
    window.addEventListener('resize', () => { clearTimeout(ht._r); ht._r = setTimeout(() => { ht.resize(); ht.render(t); }, 150); });
    S.onSpot(() => ht.render(t));
  }

  /* AI panel: still clouds of dots (no animation — the windows are the content). */
  const demo = document.querySelector('[data-ai-demo]');
  if (demo) {
    const canvas = demo.querySelector('canvas');
    const ht = new Halftone(canvas, { cell: 7, dot: 0.95, scale: 2.4, octaves: 4, min: 0.43, max: 0.7, sx: 0, sy: 0 });
    const draw = () => { ht.resize(); ht.render(17.3); };
    draw();
    window.addEventListener('resize', () => { clearTimeout(ht._r); ht._r = setTimeout(draw, 150); });
    S.onSpot(draw);
  }
})();
