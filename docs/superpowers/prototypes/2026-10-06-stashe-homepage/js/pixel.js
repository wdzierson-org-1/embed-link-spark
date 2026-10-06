/* Pixel reveal (after React Bits Pro "Pixelate Hover", written from scratch).
   An image drawn as big blocks; a lens of progressively finer blocks brings part of it back
   into focus. Used two ways: the enrichment card resolves block-by-block as Stashe reads it,
   and the "take your saves with you" memories stay fuzzy until you point at them. */
(() => {
  const S = window.Stashe;
  const cache = new Map();
  S.loadImage = (src) => {
    if (!cache.has(src)) {
      cache.set(src, new Promise((res, rej) => {
        const im = new Image();
        im.decoding = 'async';
        im.onload = () => res(im);
        im.onerror = () => rej(new Error('image failed: ' + src));
        im.src = src;
      }));
    }
    return cache.get(src);
  };

  class PixelImage {
    constructor(canvas, opts = {}) {
      this.canvas = canvas;
      this.ctx = canvas.getContext('2d');
      this.focus = opts.focus || [0.5, 0.5];
      this.block = opts.block || 16;
      this.small = document.createElement('canvas');
      this.sctx = this.small.getContext('2d');
      this.img = null;
      this.lens = null;
    }
    async set(src, focus) {
      this.img = await S.loadImage(src);
      if (focus) this.focus = focus;
      this.resize();
      return this;
    }
    resize() {
      const r = this.canvas.getBoundingClientRect();
      this.w = Math.max(1, Math.round(r.width));
      this.h = Math.max(1, Math.round(r.height));
      this.dpr = Math.min(window.devicePixelRatio || 1, 2);
      const cw = Math.round(this.w * this.dpr), ch = Math.round(this.h * this.dpr);
      if (this.canvas.width !== cw || this.canvas.height !== ch) { this.canvas.width = cw; this.canvas.height = ch; }
    }
    cover() {
      const iw = this.img.naturalWidth, ih = this.img.naturalHeight;
      const cr = this.w / this.h, ir = iw / ih;
      let sw, sh;
      if (ir > cr) { sh = ih; sw = ih * cr; } else { sw = iw; sh = iw / cr; }
      const sx = S.clamp(iw * this.focus[0] - sw / 2, 0, iw - sw);
      const sy = S.clamp(ih * this.focus[1] - sh / 2, 0, ih - sh);
      return [sx, sy, sw, sh];
    }
    level(block) {
      const { ctx, img } = this;
      const [sx, sy, sw, sh] = this.cover();
      const cw = this.canvas.width, ch = this.canvas.height;
      if (block <= 1) {
        ctx.imageSmoothingEnabled = true;
        ctx.imageSmoothingQuality = 'high';
        ctx.drawImage(img, sx, sy, sw, sh, 0, 0, cw, ch);
        return;
      }
      const bw = Math.max(1, Math.round(this.w / block)), bh = Math.max(1, Math.round(this.h / block));
      if (this.small.width !== bw || this.small.height !== bh) { this.small.width = bw; this.small.height = bh; }
      this.sctx.imageSmoothingEnabled = true;
      this.sctx.imageSmoothingQuality = 'high';
      this.sctx.drawImage(img, sx, sy, sw, sh, 0, 0, bw, bh);
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(this.small, 0, 0, bw, bh, 0, 0, cw, ch);
    }
    render(block = this.block) {
      if (!this.img) return;
      const { ctx, dpr } = this;
      this.level(block);
      if (this.lens && block > 1) {
        const { x, y, r } = this.lens;
        // Rings of finer blocks toward the centre: a focusing lens, not a crossfade.
        const rings = [[1, Math.max(2, Math.round(block / 2))], [0.74, Math.max(2, Math.round(block / 4))], [0.5, 1]];
        for (const [k, b] of rings) {
          ctx.save();
          ctx.beginPath();
          ctx.arc(x * dpr, y * dpr, r * k * dpr, 0, Math.PI * 2);
          ctx.clip();
          this.level(b);
          ctx.restore();
        }
      }
    }
  }
  S.PixelImage = PixelImage;

  /* ---------- Take your saves with you: fuzzy memories ---------- */
  const section = document.querySelector('.s-carry');
  if (!section) return;
  const items = [...section.querySelectorAll('.memory canvas')].map((canvas, i) => {
    const focus = canvas.dataset.focus ? canvas.dataset.focus.split(',').map(Number) : [0.5, 0.5];
    const pi = new PixelImage(canvas, { block: 18, focus });
    const m = { canvas, pi, i, hover: false, clear: false, block: 18, lx: 0, ly: 0, tx: 0, ty: 0, ready: false };
    pi.set(canvas.dataset.src).then(() => {
      m.ready = true;
      m.lx = m.tx = pi.w * 0.5; m.ly = m.ty = pi.h * 0.5;
      if (S.reduced() && !S.still) { pi.render(1); return; }
      pi.lens = { x: pi.w * (0.36 + 0.3 * (i % 2)), y: pi.h * 0.46, r: Math.min(pi.w, pi.h) * 0.36 };
      pi.render(m.block);
    }).catch(() => {});
    canvas.addEventListener('pointermove', (e) => {
      const r = canvas.getBoundingClientRect();
      m.tx = e.clientX - r.left; m.ty = e.clientY - r.top; m.hover = true;
    });
    canvas.addEventListener('pointerleave', () => { m.hover = false; });
    canvas.addEventListener('click', () => { m.clear = !m.clear; });
    return m;
  });

  let raf = 0, live = false, inView = false, t = 0;
  function tick() {
    raf = 0;
    if (!live) return;
    t += 1 / 60;
    for (const m of items) {
      if (!m.ready) continue;
      const { pi } = m;
      if (!m.hover) {
        // Idle: the lens wanders on its own path so the effect reads without a pointer.
        m.tx = pi.w * (0.5 + 0.3 * Math.sin(t * 0.55 + m.i * 2.1));
        m.ty = pi.h * (0.5 + 0.26 * Math.sin(t * 0.83 + m.i * 1.3));
      }
      m.lx += (m.tx - m.lx) * (m.hover ? 0.22 : 0.06);
      m.ly += (m.ty - m.ly) * (m.hover ? 0.22 : 0.06);
      const target = m.clear ? 1 : 18;
      m.block += (target - m.block) * 0.14;
      const b = m.block < 1.6 ? 1 : Math.round(m.block);
      pi.lens = { x: m.lx, y: m.ly, r: Math.min(pi.w, pi.h) * (m.hover ? 0.42 : 0.34) };
      pi.render(b);
    }
    raf = requestAnimationFrame(tick);
  }
  if (!S.reduced()) {
    const sync = () => {
      live = inView && !document.hidden;
      if (live && !raf) raf = requestAnimationFrame(tick);
    };
    S.watch(section, (seen) => { inView = seen; sync(); }, 0.05);
    document.addEventListener('visibilitychange', sync);
  }
  window.addEventListener('resize', () => items.forEach((m) => { if (m.ready) { m.pi.resize(); m.pi.render(S.reduced() && !S.still ? 1 : Math.round(m.block)); } }));
})();
