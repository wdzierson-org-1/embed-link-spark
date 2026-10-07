/* Hero: the stash as a tank of liquid, drawn in ASCII.
   A FLIP fluid (particles + staggered MAC grid, after Matthias Müller's "Ten Minute Physics"
   FLIP demo) fills the bottom of the hero. Each character cell is shaded by how many particles
   it holds and how fast they move, so calm water reads as light dots and splashes as heavy
   glyphs. The pointer stirs it; clicks splash; saved things (tags) are tossed in and sink.
   Same idea and parameters as React Bits Pro "Liquid Ascii", written from scratch here. */
(() => {
  const S = window.Stash;
  const hero = document.querySelector('.hero');
  if (!hero) return;
  const canvas = hero.querySelector('.hero-ascii');
  const ctx = canvas.getContext('2d');
  const dropLayer = hero.querySelector('.hero-drops');
  const toast = hero.querySelector('.hero-toast');

  const FLUID = 0, AIR = 1, SOLID = 2;
  const RAMP = ' ·:-~=+*#%@';

  class Flip {
    constructor(width, height, spacing, radius, maxParticles) {
      this.density = 1000;
      this.fNumX = Math.floor(width / spacing) + 1;
      this.fNumY = Math.floor(height / spacing) + 1;
      this.h = Math.max(width / this.fNumX, height / this.fNumY);
      this.fInvSpacing = 1 / this.h;
      const n = (this.fNumCells = this.fNumX * this.fNumY);
      this.u = new Float32Array(n); this.v = new Float32Array(n);
      this.du = new Float32Array(n); this.dv = new Float32Array(n);
      this.prevU = new Float32Array(n); this.prevV = new Float32Array(n);
      this.p = new Float32Array(n); this.s = new Float32Array(n);
      this.cellType = new Int32Array(n);
      this.particleDensity = new Float32Array(n);
      this.particleRestDensity = 0;
      this.maxParticles = maxParticles;
      this.pos = new Float32Array(2 * maxParticles);
      this.vel = new Float32Array(2 * maxParticles);
      this.r = radius;
      this.pInvSpacing = 1 / (2.2 * radius);
      this.pNumX = Math.floor(width * this.pInvSpacing) + 1;
      this.pNumY = Math.floor(height * this.pInvSpacing) + 1;
      this.pNumCells = this.pNumX * this.pNumY;
      this.numCellParticles = new Int32Array(this.pNumCells);
      this.firstCellParticle = new Int32Array(this.pNumCells + 1);
      this.cellParticleIds = new Int32Array(maxParticles);
      this.num = 0;
    }

    integrate(dt, gx, gy) {
      const { pos, vel } = this;
      for (let i = 0; i < this.num; i++) {
        vel[2 * i] += dt * gx;
        vel[2 * i + 1] += dt * gy;
        pos[2 * i] += vel[2 * i] * dt;
        pos[2 * i + 1] += vel[2 * i + 1] * dt;
      }
    }

    pushApart(iters) {
      const { pos, pInvSpacing: inv, pNumX, pNumY } = this;
      const counts = this.numCellParticles, first = this.firstCellParticle, ids = this.cellParticleIds;
      counts.fill(0);
      for (let i = 0; i < this.num; i++) {
        const xi = S.clamp(Math.floor(pos[2 * i] * inv), 0, pNumX - 1);
        const yi = S.clamp(Math.floor(pos[2 * i + 1] * inv), 0, pNumY - 1);
        counts[xi * pNumY + yi]++;
      }
      let acc = 0;
      for (let i = 0; i < this.pNumCells; i++) { acc += counts[i]; first[i] = acc; }
      first[this.pNumCells] = acc;
      for (let i = 0; i < this.num; i++) {
        const xi = S.clamp(Math.floor(pos[2 * i] * inv), 0, pNumX - 1);
        const yi = S.clamp(Math.floor(pos[2 * i + 1] * inv), 0, pNumY - 1);
        const c = xi * pNumY + yi;
        first[c]--;
        ids[first[c]] = i;
      }
      const minDist = 2 * this.r, minDist2 = minDist * minDist;
      for (let it = 0; it < iters; it++) {
        for (let i = 0; i < this.num; i++) {
          const px = pos[2 * i], py = pos[2 * i + 1];
          const pxi = Math.floor(px * inv), pyi = Math.floor(py * inv);
          const x0 = Math.max(pxi - 1, 0), y0 = Math.max(pyi - 1, 0);
          const x1 = Math.min(pxi + 1, pNumX - 1), y1 = Math.min(pyi + 1, pNumY - 1);
          for (let xi = x0; xi <= x1; xi++) {
            for (let yi = y0; yi <= y1; yi++) {
              const c = xi * pNumY + yi;
              for (let j = first[c], end = first[c + 1]; j < end; j++) {
                const id = ids[j];
                if (id === i) continue;
                let dx = pos[2 * id] - px, dy = pos[2 * id + 1] - py;
                const d2 = dx * dx + dy * dy;
                if (d2 > minDist2 || d2 === 0) continue;
                const d = Math.sqrt(d2);
                const s = (0.5 * (minDist - d)) / d;
                dx *= s; dy *= s;
                pos[2 * i] -= dx; pos[2 * i + 1] -= dy;
                pos[2 * id] += dx; pos[2 * id + 1] += dy;
              }
            }
          }
        }
      }
    }

    collide(ox, oy, orad, ovx, ovy) {
      const { pos, vel, h, r } = this;
      const minX = h + r, maxX = (this.fNumX - 1) * h - r;
      const minY = h + r, maxY = (this.fNumY - 1) * h - r;
      const md = orad + r, md2 = md * md;
      for (let i = 0; i < this.num; i++) {
        let x = pos[2 * i], y = pos[2 * i + 1];
        if (orad > 0) {
          const dx = x - ox, dy = y - oy;
          if (dx * dx + dy * dy < md2) { vel[2 * i] = ovx; vel[2 * i + 1] = ovy; }
        }
        if (x < minX) { x = minX; vel[2 * i] = 0; }
        if (x > maxX) { x = maxX; vel[2 * i] = 0; }
        if (y < minY) { y = minY; vel[2 * i + 1] = 0; }
        if (y > maxY) { y = maxY; vel[2 * i + 1] = 0; }
        pos[2 * i] = x; pos[2 * i + 1] = y;
      }
    }

    updateDensity() {
      const n = this.fNumY, h = this.h, h1 = this.fInvSpacing, h2 = 0.5 * h;
      const d = this.particleDensity, pos = this.pos;
      d.fill(0);
      for (let i = 0; i < this.num; i++) {
        const x = S.clamp(pos[2 * i], h, (this.fNumX - 1) * h);
        const y = S.clamp(pos[2 * i + 1], h, (this.fNumY - 1) * h);
        const x0 = Math.floor((x - h2) * h1), tx = (x - h2 - x0 * h) * h1, x1 = Math.min(x0 + 1, this.fNumX - 2);
        const y0 = Math.floor((y - h2) * h1), ty = (y - h2 - y0 * h) * h1, y1 = Math.min(y0 + 1, this.fNumY - 2);
        const sx = 1 - tx, sy = 1 - ty;
        if (x0 < this.fNumX && y0 < this.fNumY) d[x0 * n + y0] += sx * sy;
        if (x1 < this.fNumX && y0 < this.fNumY) d[x1 * n + y0] += tx * sy;
        if (x1 < this.fNumX && y1 < this.fNumY) d[x1 * n + y1] += tx * ty;
        if (x0 < this.fNumX && y1 < this.fNumY) d[x0 * n + y1] += sx * ty;
      }
      if (this.particleRestDensity === 0) {
        let sum = 0, cells = 0;
        for (let i = 0; i < this.fNumCells; i++) if (this.cellType[i] === FLUID) { sum += d[i]; cells++; }
        if (cells > 0) this.particleRestDensity = sum / cells;
      }
    }

    transfer(toGrid, flipRatio) {
      const n = this.fNumY, h = this.h, h1 = this.fInvSpacing, h2 = 0.5 * h;
      const { pos, vel, cellType, s } = this;
      if (toGrid) {
        this.prevU.set(this.u); this.prevV.set(this.v);
        this.du.fill(0); this.dv.fill(0); this.u.fill(0); this.v.fill(0);
        for (let i = 0; i < this.fNumCells; i++) cellType[i] = s[i] === 0 ? SOLID : AIR;
        for (let i = 0; i < this.num; i++) {
          const xi = S.clamp(Math.floor(pos[2 * i] * h1), 0, this.fNumX - 1);
          const yi = S.clamp(Math.floor(pos[2 * i + 1] * h1), 0, this.fNumY - 1);
          const c = xi * n + yi;
          if (cellType[c] === AIR) cellType[c] = FLUID;
        }
      }
      for (let comp = 0; comp < 2; comp++) {
        const dx = comp === 0 ? 0 : h2, dy = comp === 0 ? h2 : 0;
        const f = comp === 0 ? this.u : this.v;
        const prevF = comp === 0 ? this.prevU : this.prevV;
        const d = comp === 0 ? this.du : this.dv;
        for (let i = 0; i < this.num; i++) {
          const x = S.clamp(pos[2 * i], h, (this.fNumX - 1) * h);
          const y = S.clamp(pos[2 * i + 1], h, (this.fNumY - 1) * h);
          const x0 = Math.min(Math.floor((x - dx) * h1), this.fNumX - 2), tx = (x - dx - x0 * h) * h1, x1 = Math.min(x0 + 1, this.fNumX - 2);
          const y0 = Math.min(Math.floor((y - dy) * h1), this.fNumY - 2), ty = (y - dy - y0 * h) * h1, y1 = Math.min(y0 + 1, this.fNumY - 2);
          const sx = 1 - tx, sy = 1 - ty;
          const d0 = sx * sy, d1 = tx * sy, d2 = tx * ty, d3 = sx * ty;
          const nr0 = x0 * n + y0, nr1 = x1 * n + y0, nr2 = x1 * n + y1, nr3 = x0 * n + y1;
          if (toGrid) {
            const pv = vel[2 * i + comp];
            f[nr0] += pv * d0; d[nr0] += d0;
            f[nr1] += pv * d1; d[nr1] += d1;
            f[nr2] += pv * d2; d[nr2] += d2;
            f[nr3] += pv * d3; d[nr3] += d3;
          } else {
            const off = comp === 0 ? n : 1;
            const v0 = cellType[nr0] !== AIR || cellType[nr0 - off] !== AIR ? 1 : 0;
            const v1 = cellType[nr1] !== AIR || cellType[nr1 - off] !== AIR ? 1 : 0;
            const v2 = cellType[nr2] !== AIR || cellType[nr2 - off] !== AIR ? 1 : 0;
            const v3 = cellType[nr3] !== AIR || cellType[nr3 - off] !== AIR ? 1 : 0;
            const sum = v0 * d0 + v1 * d1 + v2 * d2 + v3 * d3;
            if (sum > 0) {
              const pic = (v0 * d0 * f[nr0] + v1 * d1 * f[nr1] + v2 * d2 * f[nr2] + v3 * d3 * f[nr3]) / sum;
              const corr = (v0 * d0 * (f[nr0] - prevF[nr0]) + v1 * d1 * (f[nr1] - prevF[nr1]) +
                v2 * d2 * (f[nr2] - prevF[nr2]) + v3 * d3 * (f[nr3] - prevF[nr3])) / sum;
              const flip = vel[2 * i + comp] + corr;
              vel[2 * i + comp] = (1 - flipRatio) * pic + flipRatio * flip;
            }
          }
        }
        if (toGrid) {
          for (let i = 0; i < f.length; i++) if (d[i] > 0) f[i] /= d[i];
          for (let i = 0; i < this.fNumX; i++) {
            for (let j = 0; j < this.fNumY; j++) {
              const solid = cellType[i * n + j] === SOLID;
              if (solid || (i > 0 && cellType[(i - 1) * n + j] === SOLID)) this.u[i * n + j] = this.prevU[i * n + j];
              if (solid || (j > 0 && cellType[i * n + j - 1] === SOLID)) this.v[i * n + j] = this.prevV[i * n + j];
            }
          }
        }
      }
    }

    solve(iters, dt, overRelax) {
      const n = this.fNumY, cp = (this.density * this.h) / dt;
      const { u, v, s, p, cellType, particleDensity: pd } = this;
      p.fill(0);
      this.prevU.set(u); this.prevV.set(v);
      for (let it = 0; it < iters; it++) {
        for (let i = 1; i < this.fNumX - 1; i++) {
          for (let j = 1; j < this.fNumY - 1; j++) {
            const c = i * n + j;
            if (cellType[c] !== FLUID) continue;
            const left = (i - 1) * n + j, right = (i + 1) * n + j, bottom = c - 1, top = c + 1;
            const sx0 = s[left], sx1 = s[right], sy0 = s[bottom], sy1 = s[top];
            const sSum = sx0 + sx1 + sy0 + sy1;
            if (sSum === 0) continue;
            let div = u[right] - u[c] + v[top] - v[c];
            if (this.particleRestDensity > 0) {
              const compression = pd[c] - this.particleRestDensity;
              if (compression > 0) div -= compression;
            }
            const pp = (-div / sSum) * overRelax;
            p[c] += cp * pp;
            u[c] -= sx0 * pp; u[right] += sx1 * pp;
            v[c] -= sy0 * pp; v[top] += sy1 * pp;
          }
        }
      }
    }

    setObstacle(x, y, rad, vx, vy) {
      const n = this.fNumY, h = this.h;
      for (let i = 1; i < this.fNumX - 2; i++) {
        for (let j = 1; j < this.fNumY - 2; j++) {
          this.s[i * n + j] = 1;
          const dx = (i + 0.5) * h - x, dy = (j + 0.5) * h - y;
          if (rad > 0 && dx * dx + dy * dy < rad * rad) {
            this.s[i * n + j] = 0;
            this.u[i * n + j] = vx; this.u[(i + 1) * n + j] = vx;
            this.v[i * n + j] = vy; this.v[i * n + j + 1] = vy;
          }
        }
      }
    }
  }

  /* ---------- scene ---------- */
  const SIM_H = 3;
  const TIME = 0.8; // the pool runs at 80% speed (v0.2: "slow it down a little bit")
  // v0.3: a slightly lower pool, so the longer headline and the picture tiles have air to fall through.
  const P = { gravity: -9.81, flip: 0.86, pressureIters: 40, separationIters: 2, overRelax: 1.9, fill: 0.35 };
  let W = 0, H = 0, dpr = 1, cell = 16, font = 16.5, cols = 0, rows = 0, scale = 1, simW = 0;
  let fluid = null, expected = 3, ceilY = 0;
  let counts, speeds, surface;
  let glyph = 0, atlases = [];
  let running = false, onScreen = true, raf = 0;
  let t = 0, lastPointer = -1e9;
  const obs = { x: -9, y: -9, vx: 0, vy: 0, r: 0, px: -9, py: -9 };
  const pointer = { x: 0, y: 0, active: false };
  let simCost = 0;

  // The pool's reaction to each save: neon rings through the glyphs, then a black band that
  // decrypts what Stash found. (v0.3: the rings live in the ASCII only; no glow above the water.)
  const SCRAMBLE = '#%&*+=<>/\\|{}[]0123456789abcdefxyz';
  const pulses = [];
  let band = null;
  const isViolet = () => document.documentElement.dataset.spot === 'violet';
  const neon = () => (isViolet() ? ['#c8ff3d', '#00e5ff', '#ff4fd8', '#ffd400'] : ['#ff2bd6', '#7a3cff', '#00b4ff', '#ff5a1f']);

  function build() {
    const rect = hero.getBoundingClientRect();
    W = Math.round(rect.width); H = Math.round(rect.height);
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    const small = W < 700;
    // Departure Mono is drawn on an 11px grid: 16.5px is 1.5× (crisp at 2× DPR), 11px is 1×.
    cell = small ? 13 : 16;
    font = small ? 11 : 16.5;
    cols = Math.ceil(W / cell); rows = Math.ceil(H / cell);
    counts = new Uint16Array(cols * rows); speeds = new Float32Array(cols * rows); surface = new Int16Array(cols);
    scale = H / SIM_H; simW = W / scale;

    const res = small ? 56 : 64;
    const h = SIM_H / res;
    const r = 0.3 * h;
    const dx = 2 * r, dy = (Math.sqrt(3) / 2) * dx;
    const numX = Math.floor((simW - 2 * h - 2 * r) / dx);
    const numY = Math.floor((P.fill * SIM_H - 2 * h - 2 * r) / dy);
    fluid = new Flip(simW, SIM_H, h, r, numX * numY);
    let k = 0;
    for (let i = 0; i < numX; i++) {
      for (let j = 0; j < numY; j++) {
        fluid.pos[k++] = h + r + dx * i + (j % 2 === 0 ? 0 : r);
        fluid.pos[k++] = h + r + dy * j;
      }
    }
    fluid.num = numX * numY;
    const n = fluid.fNumY;
    for (let i = 0; i < fluid.fNumX; i++) {
      for (let j = 0; j < fluid.fNumY; j++) fluid.s[i * n + j] = i === 0 || i === fluid.fNumX - 1 || j === 0 ? 0 : 1;
    }
    expected = (cell * cell) / (dx * scale * dy * scale);
    ceilY = Math.max(P.fill * SIM_H + 0.12, (H - (textBottom() + 64)) / scale);
    measureCopy();
    buildAtlas();
    drawTexture();
    band = null;
    pulses.length = 0;
    for (let i = 0; i < 40; i++) step((1 / 60) * TIME, 2.4 * Math.sin(i / 9), 0);
  }

  function makeAtlas(chars, color) {
    const a = document.createElement('canvas');
    a.width = glyph * chars.length; a.height = glyph;
    const g = a.getContext('2d');
    g.fillStyle = color;
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.font = `${font * dpr}px Pixel, ui-monospace, monospace`;
    Array.from(chars).forEach((ch, i) => { if (ch !== ' ') g.fillText(ch, i * glyph + glyph / 2, glyph / 2 + dpr * 0.5); });
    return a;
  }
  function buildAtlas() {
    glyph = Math.round(cell * dpr);
    atlases = [makeAtlas(RAMP, S.css('--ascii') || '#000'), ...neon().map((c) => makeAtlas(RAMP, c))];
  }

  /* ---------- texture (v0.3) ----------
     The sheet the pool sits on, after the dithered desktop on typesafe.ai but quieter: a fine dot
     grid and a few stippled spheres lit from the top right, fading out before the waterline so the
     glyphs stay clean. Drawn once per size and per spot colour. */
  const tex = hero.querySelector('.hero-tex');
  const BAYER4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  const hash2 = (x, y) => {
    let h = (x * 374761393 + y * 668265263) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
  };
  const smoothstep = (a, b, v) => { const k = S.clamp((v - a) / (b - a), 0, 1); return k * k * (3 - 2 * k); };

  function drawTexture() {
    if (!tex) return;
    tex.width = Math.round(W * dpr); tex.height = Math.round(H * dpr);
    const g = tex.getContext('2d');
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    const violet = isViolet();
    const seaTop = H * (1 - P.fill);
    const fadeAt = (y) => 1 - smoothstep(seaTop - 160, seaTop - 12, y);
    // 1. A fine dot grid, like a cutting mat.
    g.fillStyle = `rgba(0,0,0,${violet ? 0.13 : 0.08})`;
    for (let y = 2; y < seaTop; y += 4) {
      g.globalAlpha = fadeAt(y);
      for (let x = 2; x < W; x += 4) g.fillRect(x, y, 1, 1);
    }
    g.globalAlpha = 1;
    // 2. Stippled spheres: dense on the shadow side, thinning to a little dust past the rim.
    const blobs = W < 700
      ? [{ x: W * 0.96, y: H * 0.12, r: W * 0.36 }, { x: W * 0.02, y: H * 0.52, r: W * 0.28 }]
      : [{ x: W * 0.9, y: H * 0.3, r: Math.min(270, W * 0.17) }, { x: W * 0.2, y: H * 0.62, r: Math.min(210, W * 0.14) }, { x: W * 0.57, y: H * 0.03, r: Math.min(150, W * 0.1) }];
    const c = 3;
    g.fillStyle = `rgba(0,0,0,${violet ? 0.3 : 0.22})`;
    for (let y = 0; y < seaTop; y += c) {
      const fy = fadeAt(y);
      if (fy <= 0.01) continue;
      const j = (y / c) | 0;
      for (let x = 0; x < W; x += c) {
        let d = 0;
        for (const b of blobs) {
          const dx = (x - b.x) / b.r, dy = (y - b.y) / b.r;
          const r = Math.sqrt(dx * dx + dy * dy);
          if (r > 1.5) continue;
          const body = 1 - smoothstep(0.8, 1.0, r); // a crisp rim, so it reads as a sphere
          const shade = S.clamp(0.45 - 0.55 * dx + 0.65 * dy, 0, 1); // lit from the top right
          const dust = 0.06 * (1 - smoothstep(1.0, 1.5, r));
          d = Math.max(d, body * (0.06 + 0.94 * shade) + dust);
        }
        d *= fy;
        if (d < 0.02) continue;
        const i = (x / c) | 0;
        const threshold = (BAYER4[(j & 3) * 4 + (i & 3)] + 0.5) / 16 + (hash2(i, j) - 0.5) * 0.3;
        if (d > threshold) g.fillRect(x, y, 1.5, 1.5);
      }
    }
  }

  function step(dt, gx, extraTilt) {
    fluid.setObstacle(obs.x, obs.y, obs.r, obs.vx, obs.vy);
    fluid.integrate(dt, gx + (extraTilt || 0), P.gravity);
    // Soft lid just under the copy: spray that reaches it loses its lift and is pulled back
    // down, so a wild stir can't bury the headline.
    if (ceilY > 0) {
      const { pos, vel } = fluid;
      for (let i = 0; i < fluid.num; i++) {
        const over = pos[2 * i + 1] - ceilY;
        if (over > 0) vel[2 * i + 1] = Math.min(vel[2 * i + 1], 0) - over * 110 * dt;
      }
    }
    fluid.pushApart(P.separationIters);
    fluid.collide(obs.x, obs.y, obs.r, obs.vx, obs.vy);
    fluid.transfer(true);
    fluid.updateDensity();
    fluid.solve(P.pressureIters, dt, P.overRelax);
    fluid.transfer(false, P.flip);
  }

  const PULSE_MS = 2400;
  const RING = 210;
  const ringRadius = (p, now) => 20 + ((now - p.t0) / 1000) * (W < 700 ? 170 : 270);

  function render(now = performance.now()) {
    counts.fill(0); speeds.fill(0); surface.fill(rows);
    const { pos, vel } = fluid;
    for (let i = 0; i < fluid.num; i++) {
      const x = pos[2 * i] * scale, y = H - pos[2 * i + 1] * scale;
      const c = (x / cell) | 0, r = (y / cell) | 0;
      if (c < 0 || c >= cols || r < 0 || r >= rows) continue;
      const k = r * cols + c;
      counts[k]++;
      speeds[k] += Math.abs(vel[2 * i]) + Math.abs(vel[2 * i + 1]);
      if (r < surface[c]) surface[c] = r;
    }
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    for (let i = pulses.length - 1; i >= 0; i--) if (now - pulses[i].t0 > PULSE_MS) pulses.splice(i, 1);
    const colors = neon();

    // The pool: weight by depth, motion and crowding. A landing sends concentric neon rings out
    // through the glyphs themselves; as a ring fades its glyphs drop back to ink one by one.
    const last = RAMP.length - 1;
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const k = r * cols + c, n = counts[k];
        if (!n) continue;
        const sp = speeds[k] / n;
        const depth = Math.min(1, (r - surface[c]) / 16);
        const jitter = (((c * 73856093) ^ (r * 19349663)) & 1023) / 1023 - 0.5; // breaks row banding
        let w = 0.1 + 0.4 * depth + 0.3 * Math.min(sp / 1.4, 1.6) + 0.08 * (n / expected - 1) + 0.16 * jitter;
        if (surface[c] === r) w += 0.3;
        let atlas = atlases[0];
        for (const p of pulses) {
          const ring = ringRadius(p, now) - Math.hypot((c + 0.5) * cell - p.x, (r + 0.5) * cell - p.y);
          if (ring >= 0 && ring < RING) {
            const fade = 1 - (now - p.t0) / PULSE_MS;
            if (jitter + 0.5 > fade * 1.25) break;
            atlas = atlases[1 + (Math.floor(ring / 42) % colors.length)];
            w += 0.55 * (1 - ring / RING) * fade;
            break;
          }
        }
        const idx = Math.max(1, Math.min(last, 1 + Math.floor(w * 9)));
        ctx.globalAlpha = 0.62 + 0.38 * Math.min(1, w * 1.5);
        ctx.drawImage(atlas, idx * glyph, 0, glyph, glyph, Math.round(c * cell * dpr), Math.round(r * cell * dpr), glyph, glyph);
      }
    }
    ctx.globalAlpha = 1;

    // The decrypted findings, on a black band inside the pool.
    if (band) drawBand(now);
  }

  /* ---------- the decrypt band ---------- */
  function wrapBand(b) {
    const out = [];
    let start = 0;
    const text = b.text;
    while (start < text.length) {
      let end = Math.min(text.length, start + b.width);
      if (end < text.length) {
        const sp = text.lastIndexOf(' ', end);
        if (sp > start + b.width * 0.5) end = sp;
      }
      out.push({ off: start, s: text.slice(start, end) });
      start = end;
      while (text[start] === ' ') start++;
    }
    return out;
  }
  function setBandText(b, text, now = performance.now()) {
    // Whatever the old and new text share stays decrypted; everything after it decrypts anew.
    const old = b.text;
    let common = 0;
    while (common < old.length && common < text.length && old[common] === text[common]) common++;
    b.reveal.length = common;
    let at = Math.max(now, b.lastReveal || 0) + 120;
    for (let i = common; i < text.length; i++) { b.reveal[i] = at; at += text[i] === ' ' ? 4 : 16; }
    b.lastReveal = at;
    b.text = text;
  }
  // The band is set at the font's own advance (a terminal line), not the pool's wider grid.
  let charW = 10;
  function measureChar() {
    ctx.save();
    ctx.font = `${font * dpr}px Pixel, ui-monospace, monospace`;
    charW = ctx.measureText('M').width / dpr || font * 0.6;
    ctx.restore();
  }
  function spawnBand(text, x, live) {
    if (band) band.hideAt = Math.min(band.hideAt || Infinity, performance.now());
    measureChar();
    const width = Math.max(16, Math.min(64, Math.floor((W - 64) / charW)));
    const x0 = S.clamp(x - (width * charW) / 2, 28, Math.max(28, W - width * charW - 28));
    const sRow = surface ? surface[S.clamp(Math.round(x / cell), 0, cols - 1)] : rows - 8;
    const next = { text: '', reveal: [], width, x0, row: S.clamp(sRow + 3, 4, rows - 6), live, hideAt: 0 };
    setBandText(next, text);
    if (!live) next.hideAt = next.lastReveal + 3600;
    band = next;
    return next;
  }
  function finishBand(b) { if (b && !b.hideAt) b.hideAt = Math.max(performance.now(), b.lastReveal) + 4200; }

  function drawBand(now) {
    const b = band;
    const lines = wrapBand(b);
    const total = b.text.length;
    const state = (i) => {
      if (b.hideAt) {
        const gone = b.hideAt + (total - i) * 4;
        if (now >= gone + 150) return 0;          // gone
        if (now >= gone) return 1;                // scrambling out
      }
      const rv = b.reveal[i];
      if (rv === undefined || now < rv - 260) return 0; // not reached yet
      return now < rv ? 1 : 2;                    // scrambling in, then final
    };
    let anyVisible = false;
    const color = isViolet() ? '#ffffff' : (S.css('--spot') || '#a3f53b');
    ctx.font = `${font * dpr}px Pixel, ui-monospace, monospace`;
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'left';
    for (let li = 0; li < lines.length; li++) {
      const { off, s } = lines[li];
      const lineH = Math.round(cell * 1.4);
      const y = Math.round((b.row * cell + li * lineH) * dpr);
      let first = -1, lastJ = -1;
      for (let j = 0; j < s.length; j++) if (state(off + j)) { if (first < 0) first = j; lastJ = j; }
      if (first < 0) continue;
      anyVisible = true;
      ctx.globalAlpha = 1;
      ctx.fillStyle = '#000';
      ctx.fillRect(Math.round((b.x0 + (first - 0.9) * charW) * dpr), y, Math.round((lastJ - first + 2.8) * charW * dpr), lineH * dpr);
      ctx.fillStyle = color;
      for (let j = 0; j < s.length; j++) {
        const st = state(off + j);
        const ch = s[j];
        if (!st || ch === ' ') continue;
        ctx.globalAlpha = st === 2 ? 1 : 0.5;
        ctx.fillText(st === 2 ? ch : SCRAMBLE[(Math.random() * SCRAMBLE.length) | 0], Math.round((b.x0 + j * charW) * dpr), y + (lineH * dpr) / 2 + dpr * 0.5);
      }
    }
    ctx.globalAlpha = 1;
    if (b.hideAt && now > b.hideAt + 400 && !anyVisible) band = null;
  }

  /* ---------- pointer: stir, splash, toss ---------- */
  function toSim(px, py) { return [px / scale, (H - py) / scale]; }

  hero.addEventListener('pointermove', (e) => {
    const rect = hero.getBoundingClientRect();
    pointer.x = e.clientX - rect.left; pointer.y = e.clientY - rect.top; pointer.active = true;
    lastPointer = performance.now();
  });
  hero.addEventListener('pointerleave', () => { pointer.active = false; });

  function splash(px, py, strength) {
    const [sx, sy] = toSim(px, py);
    const R = 0.2, R2 = R * R;
    const { pos, vel } = fluid;
    for (let i = 0; i < fluid.num; i++) {
      const dx = pos[2 * i] - sx, dy = pos[2 * i + 1] - sy, d2 = dx * dx + dy * dy;
      if (d2 > R2 * 4) continue;
      const d = Math.sqrt(d2) + 1e-4;
      if (d < R) {
        const f = 1 - d / R;
        vel[2 * i + 1] -= strength * f * 1.6;
        vel[2 * i] += (dx / d) * strength * f * 1.1;
      } else {
        const f = 1 - (d - R) / R;
        vel[2 * i + 1] += strength * f * 0.9;
        vel[2 * i] += (dx / d) * strength * f * 0.5;
      }
    }
  }

  function surfaceY(px) {
    const c = S.clamp((px / cell) | 0, 0, cols - 1);
    return surface && surface[c] < rows ? surface[c] * cell : H;
  }

  /* ---------- saves dropped into the pool ----------
     Each one appears labelled with what kind of thing it is ("link: …", "place: …"), hangs for a
     moment so it can be read, then drops. Pictures come in as small, square, low-res tiles: photos
     shrunk to 18×18, and pixel art where a save is a place, a paper or a book. What Stash gathers
     for each one is illustrative (the endpoint is only called for a visitor's own paste). */
  const LAND = '/site/landing/';
  const IMG = '/site/img/';
  const SAVES = [
    { k: 'link', v: 'medium.com/how-to-remember-more', info: 'link: medium.com/how-to-remember-more >> article about memory and retention with practical tips >> 2 minute read >> author: garret how >>' },
    { k: 'photo', v: 'IMG_0412.JPG', tile: { src: IMG + 'bag.jpg', focus: [0.5, 0.55] }, info: 'photo: img_0412.jpg >> woven leather tote, tan, brass buckle >> saved from a shop window, soho >>' },
    { k: 'link', v: 'github.com/charmbracelet/gum', info: 'link: github.com/charmbracelet/gum >> repo: a tool for glamorous shell scripts >> go, mit license >> install: brew install gum >>' },
    { k: 'place', v: 'Chez Colette', tile: { art: 'map' }, info: 'place: chez colette >> french bistro, 12 perry st, west village >> window table from 5:30 >>' },
    { k: 'video', v: '@sundaysupper', tile: { src: LAND + 'cover-recipe.jpg', focus: [0.62, 0.5] }, info: 'video: @sundaysupper on tiktok >> recipe: 20-minute tomato and mozzarella penne >> 5 ingredients >> 58 sec >>' },
    { k: 'paper', v: '2307.03172v3.pdf', tile: { art: 'paper' }, info: 'paper: 2307.03172v3.pdf >> lost in the middle, liu et al. >> models use the start and end of a long context best >> 18 pages >>' },
    { k: 'voice memo', v: '0:42', info: 'voice memo: 0:42 >> transcribed >> “book the cabin for the long weekend” >> reminder: friday >>' },
    { k: 'book', v: 'Walden', tile: { art: 'book' }, info: 'book: walden >> henry david thoreau, 1854 >> title and author read from the cover >>' },
    { k: 'link', v: 'nytimes.com/…/best-weeknight-pasta', info: 'link: nytimes.com/…/best-weeknight-pasta >> recipe: weeknight pasta >> 25 min, 6 ingredients >>' },
    { k: 'screenshot', v: 'IMG_4471.PNG', tile: { src: IMG + 'shot-colette.jpg', focus: [0.5, 0.36] }, info: 'screenshot: img_4471.png >> restaurant post: chez colette, 12 perry st >> text read from the image >> window table from 5:30 >>' },
    { k: 'note', v: 'book the cabin for the long weekend', info: 'note >> reminder: book the cabin >> before friday >>' },
    { k: 'image', v: 'Kitchen, take two.png', tile: { src: IMG + 'moodboard.jpg' }, info: 'image: kitchen, take two.png >> kitchen moodboard >> green zellige, travertine, walnut >> 3 colors pulled >>' },
    { k: 'link', v: 'maps.apple.com/?q=Chez+Colette', info: 'link: maps.apple.com >> place: chez colette >> french bistro, west village >> open from 5:30 >>' },
    { k: 'photo', v: 'IMG_2290.JPG', tile: { src: IMG + 'hotel-courtyard.jpg' }, info: 'photo: img_2290.jpg >> tiled courtyard, casa do pátio, lisbon >> place read from the photo >>' },
    { k: 'boarding pass', v: 'BOS → SFO, Fri 7:05', info: 'boarding pass >> bos to sfo, fri 7:05 am >> seat 14c, gate b12 >>' },
  ];
  const HOLD = 560;  // ms a save hangs before it drops (v0.3: "hold it for an extra half a second")
  const TILE = 18;   // pixels across a picture tile

  // Pixel art for saves that aren't photos. Coordinates are tile pixels.
  const ART = {
    map(f) {
      f('#efe9da', 0, 0, 18, 18);                                   // land
      f('#e3dbc8', 12, 0, 3, 6); f('#e3dbc8', 16, 7, 2, 5); f('#e3dbc8', 4, 13, 7, 5); // built-up blocks
      f('#bfdca6', 4, 1, 6, 4);                                     // a park
      f('#a7cce8', 0, 0, 3, 18); f('#a7cce8', 3, 10, 1, 8);         // the river
      f('#ffffff', 3, 6, 15, 1); f('#ffffff', 4, 12, 14, 1);        // streets
      f('#ffffff', 11, 0, 1, 18); f('#ffffff', 15, 0, 1, 18);
      f('#2f7cf6', 4, 12, 8, 1); f('#2f7cf6', 11, 6, 1, 7); f('#2f7cf6', 11, 6, 3, 1); // the route
      f('#2f7cf6', 3, 11, 2, 2);                                    // you are here
      f('#e5483b', 13, 2, 3, 3); f('#e5483b', 14, 5, 1, 1); f('#ffffff', 14, 3, 1, 1); // the pin
    },
    paper(f) {
      f('#fbfaf6', 0, 0, 18, 18);                                   // the page
      f('#d9d8d2', 1, 3, 1, 12);                                    // the arXiv stamp down the margin
      f('#202020', 4, 2, 11, 1); f('#202020', 5, 3, 9, 1);          // title
      f('#8c8c88', 6, 5, 7, 1);                                     // authors
      f('#bdbcb6', 4, 7, 11, 1); f('#bdbcb6', 4, 8, 9, 1);          // abstract
      for (const y of [10, 12, 14, 16]) f('#c4c3bd', 3, y, 6, 1);   // two columns
      f('#a9bfdc', 10, 10, 6, 3);                                   // a figure
      f('#c4c3bd', 10, 14, 6, 1); f('#c4c3bd', 10, 16, 4, 1);
    },
    book(f) {
      f('#e9e1cf', 0, 0, 18, 18);                                   // cover
      f('#d3c8ae', 0, 0, 2, 18); f('#f6f0e3', 2, 0, 1, 18);         // spine and its highlight
      f('#6f7464', 6, 2, 8, 1);                                     // author
      f('#1d2a22', 5, 4, 10, 2); f('#1d2a22', 6, 6, 8, 1);          // WALDEN
      f('#6f7464', 7, 8, 6, 1);                                     // or, Life in the Woods
      f('#1d2a22', 7, 10, 1, 1); f('#1d2a22', 6, 11, 3, 1); f('#1d2a22', 5, 12, 5, 1); f('#1d2a22', 7, 13, 1, 2); // a pine
      f('#1d2a22', 13, 11, 1, 1); f('#1d2a22', 12, 12, 3, 1); f('#1d2a22', 11, 13, 5, 1); f('#1d2a22', 13, 14, 1, 1);
      f('#1d2a22', 4, 15, 12, 1);                                   // the shore
    },
  };
  const tiles = new Map();
  /** The 18×18 source for a save's picture: { canvas, ready }. Photos shrink in two steps so each
      tile pixel is an average, not a sample. */
  function tileFor(spec) {
    const key = spec.src || spec.art;
    if (tiles.has(key)) return tiles.get(key);
    const c = document.createElement('canvas');
    c.width = c.height = TILE;
    const g = c.getContext('2d');
    const entry = { canvas: c, ready: false };
    tiles.set(key, entry);
    if (spec.art) {
      ART[spec.art]((color, x, y, w = 1, h = 1) => { g.fillStyle = color; g.fillRect(x, y, w, h); });
      entry.ready = true;
    } else {
      entry.loading = S.loadImage(spec.src).then((img) => {
        const [fx, fy] = spec.focus || [0.5, 0.5];
        const s = Math.min(img.naturalWidth, img.naturalHeight);
        const sx = S.clamp(img.naturalWidth * fx - s / 2, 0, img.naturalWidth - s);
        const sy = S.clamp(img.naturalHeight * fy - s / 2, 0, img.naturalHeight - s);
        const mid = document.createElement('canvas');
        mid.width = mid.height = TILE * 4;
        const m = mid.getContext('2d');
        m.imageSmoothingQuality = 'high';
        m.drawImage(img, sx, sy, s, s, 0, 0, TILE * 4, TILE * 4);
        g.imageSmoothingQuality = 'high';
        g.drawImage(mid, 0, 0, TILE * 4, TILE * 4, 0, 0, TILE, TILE);
        entry.ready = true;
      }).catch(() => {});
    }
    return entry;
  }

  let saveIdx = 0;
  const drops = [];

  /** A save's element: its tile (if it has a picture and there's room for one) over its label. */
  function makeDrop(save, textOnly) {
    const el = document.createElement('span');
    el.className = 'drop is-new';
    const tile = save.tile && !textOnly ? tileFor(save.tile) : null;
    if (tile && tile.ready) {
      const c = document.createElement('canvas');
      c.width = c.height = TILE;
      c.getContext('2d').drawImage(tile.canvas, 0, 0);
      el.appendChild(c);
      el.classList.add('has-tile');
    }
    const tag = document.createElement('span');
    tag.className = 'drop-tag';
    const kind = document.createElement('b');
    kind.textContent = `${save.k}:`;
    tag.append(kind, ` ${save.v}`);
    el.appendChild(tag);
    dropLayer.appendChild(el);
    return el;
  }

  /** Hang a save, centred on x, with its top at y. opts: info (what the band will say), hold (ms). */
  function launch(el, save, x, y, opts = {}) {
    const now = performance.now();
    const d = {
      el, x, y, y0: y, vx: 0, vy: 0, w: el.offsetWidth, h: el.offsetHeight,
      rot: (Math.random() - 0.5) * 6, vr: 0, landed: false, released: false, t: 0,
      info: opts.info || { text: save.info }, born: now, holdUntil: now + (opts.hold ?? HOLD),
      drift: (Math.random() - 0.5) * 1.1,
    };
    d.x = S.clamp(x - d.w / 2, 8, W - d.w - 8);
    drops.push(d);
    place(d);
    return d;
  }
  function toss(save, x, y, opts = {}) {
    if (drops.length > 6) return null;
    return launch(makeDrop(save, opts.textOnly), save, x, y, opts);
  }
  function place(d) { d.el.style.transform = `translate(${d.x.toFixed(1)}px, ${d.y.toFixed(1)}px) rotate(${d.rot.toFixed(2)}deg)`; }

  // What the copy occupies, line by line: a headline's lines are shorter than its column, so a save
  // can hang in any clear patch of sky (the gap between the headline and the lead is the big one)
  // and never crosses the words or the buttons.
  let copy = [];
  function measureCopy() {
    const hr = hero.getBoundingClientRect();
    const range = document.createRange();
    range.selectNodeContents(hero.querySelector('h1'));
    const rects = [...range.getClientRects(), ...[...hero.querySelectorAll('.hero-aside > *')].map((el) => el.getBoundingClientRect())];
    copy = rects.filter((r) => r.width && r.height).map((r) => ({ x0: r.left - hr.left, x1: r.right - hr.left, bottom: r.bottom - hr.top }));
  }
  function ceilingFor(x0, x1) {
    let c = 64; // under the nav
    for (const b of copy) if (b.x1 > x0 - 28 && b.x0 < x1 + 28) c = Math.max(c, b.bottom + 18);
    return c;
  }
  function textBottom() {
    const inner = hero.querySelector('.hero-inner').getBoundingClientRect();
    return inner.bottom - hero.getBoundingClientRect().top;
  }
  /** Spots where a drop this size has clear sky above the pool, with room to fall. */
  function spotsFor(w, h) {
    const out = [];
    for (let x = w / 2 + 12; x <= W - w / 2 - 12; x += 24) {
      const ceil = ceilingFor(x - w / 2, x + w / 2);
      const water = Math.min(surfaceY(x - w / 2 + 4), surfaceY(x), surfaceY(x + w / 2 - 4));
      if (water - ceil >= h + 56) out.push({ x, ceil, water });
    }
    return out;
  }
  const hangAt = (spot, h, lift) => Math.max(spot.ceil, spot.water - h - lift);

  function tossNext() {
    if (drops.length > 6) return;
    const save = SAVES[saveIdx++ % SAVES.length];
    // A picture if there's room for one, else just the label; no room at all, skip this one.
    for (const textOnly of save.tile ? [false, true] : [true]) {
      const el = makeDrop(save, textOnly);
      const spots = spotsFor(el.offsetWidth, el.offsetHeight);
      if (spots.length) {
        const spot = spots[(Math.random() * spots.length) | 0];
        launch(el, save, spot.x, hangAt(spot, el.offsetHeight, 70 + Math.random() * 60));
        return;
      }
      el.remove();
    }
  }

  /** A save lands: the pool pulses, then a band decrypts what was found. */
  function react(cx, sy, info) {
    pulses.push({ x: cx, y: Math.min(H - cell, sy + cell * 2), t0: performance.now() });
    if (pulses.length > 3) pulses.shift();
    setTimeout(() => {
      if (!info) return;
      if (info.live) { info.band = spawnBand(info.compose(), cx, true); if (info.complete) finishBand(info.band); }
      else if (!(band && band.live && !band.hideAt)) spawnBand(info.text, cx, false); // a visitor's own save keeps the stage
    }, 420);
  }

  function updateDrops(now) {
    for (let i = drops.length - 1; i >= 0; i--) {
      const d = drops[i];
      if (!d.landed && now < d.holdUntil) {
        d.y = d.y0 + Math.sin((now - d.born) / 320) * 1.5; // hanging, breathing, while it's read
        place(d);
        continue;
      }
      if (!d.released) { d.released = true; d.vx = d.drift; d.vy = 0.3; d.vr = (Math.random() - 0.5) * 0.6; }
      d.t++;
      if (!d.landed) {
        d.vy += 0.2; d.x += d.vx; d.y += d.vy; d.rot += d.vr;
        const cx = d.x + d.w / 2;
        if (d.y + d.h >= surfaceY(cx) + 4) {
          d.landed = true;
          splash(cx, surfaceY(cx), Math.min(3, 0.7 + d.vy * 0.24));
          react(cx, surfaceY(cx), d.info);
          d.el.classList.add('is-in');
          d.vy *= 0.18; d.vx *= 0.3;
          setTimeout(() => d.el.remove(), 950);
        }
      } else {
        d.y += d.vy; d.x += d.vx;
      }
      place(d);
      if (d.landed && d.t > 400) d.el.remove();
      if (!d.el.isConnected) drops.splice(i, 1);
    }
  }

  hero.addEventListener('click', (e) => {
    if (e.target.closest('a, button')) return;
    if (S.reduced()) return;
    const rect = hero.getBoundingClientRect();
    const x = e.clientX - rect.left, y = e.clientY - rect.top;
    if (y >= surfaceY(x) - 6) { splash(x, y, 2.4); pulses.push({ x, y, t0: performance.now() }); }
    else toss(SAVES[saveIdx++ % SAVES.length], x, y - 10, { textOnly: surfaceY(x) - y < 150 });
  });

  /* Paste anywhere: the real enrichment endpoint reads it while it hangs and falls; the band shows
     what it found. */
  document.addEventListener('paste', (e) => {
    const el = document.activeElement;
    if (el && (el.isContentEditable || /^(INPUT|TEXTAREA)$/.test(el.tagName))) return;
    const text = (e.clipboardData && e.clipboardData.getData('text') || '').trim().replace(/\s+/g, ' ');
    if (!text || !onScreen || S.reduced()) return;
    const isUrl = S.looksLikeUrl(text);
    const kind = isUrl ? 'link' : 'note';
    const value = isUrl ? text.replace(/^https?:\/\/(www\.)?/i, '').replace(/[?#].*$/, '') : text;
    const label = value.length > 48 ? `${value.slice(0, 47)}…` : value;
    const info = {
      live: true, complete: false, band: null, head: `${kind}: ${label}`.toLowerCase(), what: '', facts: [],
      compose() {
        const parts = [this.head];
        if (this.what) parts.push(this.what);
        parts.push(...this.facts.slice(0, 3));
        return parts.join(' >> ') + (this.complete ? ' >>' : ' >> …');
      },
      update() {
        if (!this.band) return;
        const next = this.compose();
        if (next !== this.band.text) setBandText(this.band, next);
        if (this.complete) finishBand(this.band);
      },
    };
    // The visitor's own save always goes in, in the clearest sky there is.
    const drop = makeDrop({ k: kind, v: label }, true);
    const spots = spotsFor(drop.offsetWidth, drop.offsetHeight);
    const spot = spots.length ? spots[Math.floor(spots.length * 0.62)] : { x: W * 0.62, ceil: textBottom() + 14, water: surfaceY(W * 0.62) };
    launch(drop, { k: kind, v: label }, spot.x, hangAt(spot, drop.offsetHeight, 120), { info });
    nextToss = Math.max(nextToss, 12000); // let the visitor's save have the pool to itself for a while
    toast.textContent = 'Reading it for real. (The demo keeps nothing.)';
    toast.classList.add('is-on');
    clearTimeout(toast._t);
    toast._t = setTimeout(() => toast.classList.remove('is-on'), 2600);
    S.enrich(isUrl ? { url: text } : { text }, (event, data) => {
      if (event === 'field') {
        if (data.k === 'what') info.what = data.v.toLowerCase();
        else if (data.k === 'fact') info.facts.push(/reading time/.test(data.l) ? `${data.v} read` : `${data.l}: ${data.v}`.toLowerCase());
      } else if (event === 'error') {
        info.what = (data.message || 'couldn’t read that').toLowerCase().replace(/\.$/, '');
        info.complete = true;
      } else if (event === 'done') {
        info.complete = true;
      }
      info.update();
    }).finally(() => { info.complete = true; info.update(); });
  });

  // Idle: an unseen paddle drifts along the waterline, so the surface keeps moving.
  function idlePaddle(dt) {
    const fillY = P.fill * SIM_H;
    const nx = simW * (0.5 + 0.44 * Math.sin(t * 0.29));
    const ny = fillY * (0.98 + 0.16 * Math.sin(t * 0.83));
    obs.vx = (nx - obs.px) / dt; obs.vy = (ny - obs.py) / dt;
    if (Math.abs(obs.vx) > 9 || Math.abs(obs.vy) > 9) { obs.vx = 0; obs.vy = 0; }
    obs.x = nx; obs.y = ny; obs.r = 0.085 * SIM_H;
    obs.px = obs.x; obs.py = obs.y;
  }

  /* `#still`: a frozen, representative frame for renders — motion in the water, a save just landed
     with its rings and its decrypted findings, a place tile and a link hanging in the air.
     (Reduced motion: calm tank only.) */
  function stillFrame() {
    for (let i = 0; i < 170; i++) { t += 1 / 60; idlePaddle(1 / 60); step((1 / 60) * TIME, 0.55 * Math.sin(t * 0.47), 0); }
    render();
    const now = performance.now();
    const x = W * 0.42;
    pulses.push({ x, y: surfaceY(x) + cell * 2, t0: now - 760 });
    const b = spawnBand(SAVES[0].info, x, false);
    b.reveal = b.reveal.map(() => now - 1000);
    b.hideAt = 0;
    render(now);
    // `pick` is how far along the row of clear spots (left to right) the save hangs.
    const hang = (save, textOnly, pick, lift, rot) => {
      const el = makeDrop(save, textOnly);
      const spots = spotsFor(el.offsetWidth, el.offsetHeight);
      if (!spots.length) { el.remove(); return; }
      const spot = spots[Math.round(pick * (spots.length - 1))];
      const d = launch(el, save, spot.x, hangAt(spot, el.offsetHeight, lift), { hold: Infinity });
      d.rot = rot;
      place(d);
    };
    hang(SAVES.find((s) => s.k === 'place'), false, 0.5, 70, -3);
    hang(SAVES.find((s) => s.k === 'link' && /github/.test(s.v)), true, 0.08, 40, 2);
  }

  /* ---------- loop ---------- */
  let nextToss = 2200, lastFrame = 0;
  function frame(now) {
    raf = 0;
    if (!running) return;
    const dt = (1 / 60) * TIME;
    t += dt;
    const idle = now - lastPointer > 2200;
    const mode = pointer.active && !idle ? 'pointer' : 'idle';
    if (mode !== obs.mode) {
      // Switching hands between the idle paddle and the pointer: start from rest, no jump.
      const [sx, sy] = mode === 'pointer' ? toSim(pointer.x, pointer.y) : [obs.x, obs.y];
      obs.px = sx; obs.py = sy; obs.mode = mode;
    }
    if (mode === 'pointer') {
      const [sx, sy] = toSim(pointer.x, pointer.y);
      obs.vx = S.clamp((sx - obs.px) / dt, -6, 6); obs.vy = S.clamp((sy - obs.py) / dt, -6, 6);
      obs.x = sx; obs.y = sy; obs.r = 0.1 * SIM_H;
    } else {
      idlePaddle(dt);
    }
    obs.px = obs.x; obs.py = obs.y;
    const t0 = performance.now();
    step(dt, 0.55 * Math.sin(t * 0.47), 0);
    simCost = simCost * 0.9 + (performance.now() - t0) * 0.1;
    if (simCost > 11 && P.pressureIters > 20) { P.pressureIters -= 5; }
    render(now);
    updateDrops(now);
    if (!S.reduced()) {
      nextToss -= now - (lastFrame || now);
      if (nextToss <= 0) { tossNext(); nextToss = 4600 + Math.random() * 2600; }
    }
    lastFrame = now;
    raf = requestAnimationFrame(frame);
  }
  function start() { if (!running && !S.reduced()) { running = true; lastFrame = 0; raf = requestAnimationFrame(frame); } }
  function stop() { running = false; if (raf) cancelAnimationFrame(raf); raf = 0; }

  function boot() {
    build();
    render();
    if (S.still) { stillFrame(); return; }
    if (S.reduced()) return;
    S.watch(hero, (seen) => { onScreen = seen; seen && !document.hidden ? start() : stop(); }, 0.02);
    document.addEventListener('visibilitychange', () => (document.hidden ? stop() : onScreen && start()));
  }

  let lastW = 0, lastH = 0;
  window.addEventListener('resize', () => {
    clearTimeout(boot._r);
    boot._r = setTimeout(() => {
      const r = hero.getBoundingClientRect();
      if (Math.abs(r.width - lastW) > 30 || Math.abs(r.height - lastH) / Math.max(1, lastH) > 0.15) {
        lastW = r.width; lastH = r.height; build(); render();
      }
    }, 180);
  });
  S.onSpot(() => { if (fluid) { buildAtlas(); drawTexture(); render(); } });

  // Picture tiles start loading now, so the first one is ready by the time it's dropped.
  const tilesReady = Promise.all(SAVES.filter((s) => s.tile).map((s) => tileFor(s.tile).loading));
  Promise.all([document.fonts.load('11px Pixel').catch(() => {}), S.still ? tilesReady : null]).then(() => {
    const r = hero.getBoundingClientRect(); lastW = r.width; lastH = r.height;
    boot();
  });
})();
