/* Halftone field (after React Bits Pro "Halftone Wave", written from scratch): a grid of dots
   sized by drifting fractal noise. Two uses:
   - the closing section, where the dots knock out around the headline like a print knockout;
   - the "with your AI" panel, as still dot clouds behind the windows (typesafe's dither). */
(() => {
  const S = window.Stashe;

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

  class Halftone {
    constructor(canvas, o) {
      this.canvas = canvas; this.ctx = canvas.getContext('2d'); this.o = o;
      this.knock = []; this.pointer = null;
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
    }
    render(t) {
      const { ctx, w, h, dpr, o } = this;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = S.css('--ascii') || '#000';
      const cell = o.cell, maxR = cell * o.dot * 0.5;
      const cols = Math.ceil(w / cell) + 1, rows = Math.ceil(h / cell) + 1;
      const sc = o.scale / Math.max(w, 1);
      ctx.beginPath();
      for (let j = 0; j < rows; j++) {
        for (let i = 0; i < cols; i++) {
          const x = i * cell + (j % 2 ? cell / 2 : 0), y = j * cell;
          let v = fbm(x * sc + t * o.sx, y * sc + t * o.sy, o.octaves);
          v = smooth(o.min, o.max, v);
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
    const ht = new Halftone(canvas, {
      cell: 13, dot: 0.92, scale: 3.2, octaves: 3, min: 0.38, max: 0.78, sx: 0.035, sy: 0.02, knockPad: 46,
      knockout: () => [...close.querySelectorAll('.t-giant, .close-cta .btn, .close-cta .px, .foot')],
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
