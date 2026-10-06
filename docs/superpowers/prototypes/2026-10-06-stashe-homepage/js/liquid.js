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
  const P = { gravity: -9.81, flip: 0.86, pressureIters: 40, separationIters: 2, overRelax: 1.9, fill: 0.37 };
  let W = 0, H = 0, dpr = 1, cell = 16, font = 16.5, cols = 0, rows = 0, scale = 1, simW = 0;
  let fluid = null, expected = 3, ceilY = 0;
  let counts, speeds, surface;
  let glyph = 0, atlases = [];
  let running = false, onScreen = true, raf = 0;
  let t = 0, lastPointer = -1e9;
  const obs = { x: -9, y: -9, vx: 0, vy: 0, r: 0, px: -9, py: -9 };
  const pointer = { x: 0, y: 0, active: false };
  let simCost = 0;

  // The pool's reaction to each save: neon rings, then a black band that decrypts what Stash found.
  const SCRAMBLE = '#%&*+=<>/\\|{}[]0123456789abcdefxyz';
  const pulses = [];
  let band = null;
  const isViolet = () => document.documentElement.dataset.spot === 'violet';
  const neon = () => (isViolet() ? ['#c8ff3d', '#00e5ff', '#ff4fd8', '#ffd400'] : ['#ff2bd6', '#7a3cff', '#00b4ff', '#ff5a1f']);
  const rgba = (hex, a) => `rgba(${parseInt(hex.slice(1, 3), 16)},${parseInt(hex.slice(3, 5), 16)},${parseInt(hex.slice(5, 7), 16)},${a})`;

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
    buildAtlas();
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

  const PULSE_MS = 2000;
  const ringRadius = (p, now) => 26 + ((now - p.t0) / 1000) * (W < 700 ? 190 : 300);

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

    // 1. Glow: concentric neon gradients spreading from each fresh drop, under the glyphs.
    for (let i = pulses.length - 1; i >= 0; i--) if (now - pulses[i].t0 > PULSE_MS) pulses.splice(i, 1);
    const colors = neon();
    for (const p of pulses) {
      const fade = 1 - (now - p.t0) / PULSE_MS;
      const R = ringRadius(p, now);
      const g = ctx.createRadialGradient(p.x * dpr, p.y * dpr, 0, p.x * dpr, p.y * dpr, R * dpr);
      g.addColorStop(0, `rgba(255,255,255,${0.5 * fade})`);
      colors.forEach((c, i) => g.addColorStop(0.3 + i * 0.16, rgba(c, 0.34 * fade)));
      g.addColorStop(1, rgba(colors[colors.length - 1], 0));
      ctx.fillStyle = g;
      ctx.fillRect((p.x - R) * dpr, (p.y - R) * dpr, 2 * R * dpr, 2 * R * dpr);
    }

    // 2. The pool: weight by depth, motion and crowding; rings tint and thicken the glyphs.
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
          if (ring >= 0 && ring < 190) {
            const fade = 1 - (now - p.t0) / PULSE_MS;
            atlas = atlases[1 + (Math.floor(ring / 38) % colors.length)];
            w += 0.45 * (1 - ring / 190) * fade;
            break;
          }
        }
        const idx = Math.max(1, Math.min(last, 1 + Math.floor(w * 9)));
        ctx.globalAlpha = 0.62 + 0.38 * Math.min(1, w * 1.5);
        ctx.drawImage(atlas, idx * glyph, 0, glyph, glyph, Math.round(c * cell * dpr), Math.round(r * cell * dpr), glyph, glyph);
      }
    }
    ctx.globalAlpha = 1;

    // 3. The decrypted findings, on a black band inside the pool.
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

  /* Tossed-in saves, each with what Stash gathers about it (illustrative). */
  const SAVES = [
    { tag: 'medium.com/how-to-remember-more', info: 'medium.com/how-to-remember-more >> article about memory and retention with practical tips >> 2 minute read >> author: garret how >>' },
    { tag: 'github.com/charmbracelet/gum', info: 'github.com/charmbracelet/gum >> repo: a tool for glamorous shell scripts >> go, mit license >> install: brew install gum >>' },
    { tag: 'tiktok.com/@sundaysupper/video/7391…', info: 'tiktok.com/@sundaysupper >> recipe video: 20-minute tomato and mozzarella penne >> 5 ingredients >> 58 sec >>' },
    { tag: 'Screenshot 2026-10-02 at 9.14 PM.png', info: 'screenshot >> restaurant post: chez colette, 12 perry st >> text read from the image >> window table from 5:30 >>' },
    { tag: 'arxiv.org/abs/2307.03172', info: 'arxiv.org/abs/2307.03172 >> paper: lost in the middle >> models use the start and end of a long context best >> 18 pages >>' },
    { tag: 'Voice memo 0:42.m4a', info: 'voice memo, 42 sec >> transcribed >> “book the cabin for the long weekend” >> reminder: friday >>' },
    { tag: 'IMG_2213.HEIC', info: 'photo >> book cover: walden, henry david thoreau >> title and author read from the cover >>' },
    { tag: 'maps.apple.com/?q=Chez+Colette', info: 'place: chez colette >> french bistro, west village >> open from 5:30 >>' },
    { tag: 'Kitchen, take two.png', info: 'image >> kitchen moodboard >> green zellige, travertine, walnut >> 3 colors pulled >>' },
    { tag: 'nytimes.com/…/best-weeknight-pasta', info: 'nytimes.com >> recipe: weeknight pasta >> 25 min, 6 ingredients >>' },
    { tag: 'Boarding pass BOS→SFO.png', info: 'boarding pass >> bos to sfo, fri 7:05 am >> seat 14c >>' },
    { tag: 'note: book the cabin for the long weekend', info: 'note >> reminder: book the cabin >> before friday >>' },
  ];
  let saveIdx = 0;
  const drops = [];

  function toss(text, x, y, vx, vy, info) {
    if (drops.length > 6) return null;
    const el = document.createElement('span');
    el.className = 'drop';
    el.textContent = text;
    dropLayer.appendChild(el);
    const d = { el, x, y, vx, vy, w: el.offsetWidth, h: el.offsetHeight, rot: (Math.random() - 0.5) * 10, vr: (Math.random() - 0.5) * 0.9, landed: false, t: 0, info };
    d.x = S.clamp(d.x - d.w / 2, 8, W - d.w - 8);
    drops.push(d);
    place(d);
    return d;
  }
  function place(d) { d.el.style.transform = `translate(${d.x.toFixed(1)}px, ${d.y.toFixed(1)}px) rotate(${d.rot.toFixed(2)}deg)`; }

  // Tossed saves start below the copy, so they never cross the headline or the buttons.
  function textBottom() {
    const inner = hero.querySelector('.hero-inner').getBoundingClientRect();
    return inner.bottom - hero.getBoundingClientRect().top;
  }
  function tossNext() {
    const save = SAVES[saveIdx++ % SAVES.length];
    const x = W * (0.12 + Math.random() * 0.76);
    const floor = textBottom() + 14;
    const y = Math.max(floor, surfaceY(x) - 150 - Math.random() * 60);
    if (surfaceY(x) - y < 40) return;
    toss(save.tag, x, y, (Math.random() - 0.5) * 1.6, -0.8 - Math.random() * 0.8, { text: save.info });
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

  function updateDrops() {
    for (let i = drops.length - 1; i >= 0; i--) {
      const d = drops[i];
      d.t++;
      if (!d.landed) {
        d.vy += 0.22; d.x += d.vx; d.y += d.vy; d.rot += d.vr;
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
    else { const save = SAVES[saveIdx++ % SAVES.length]; toss(save.tag, x, y - 10, (Math.random() - 0.5) * 1.6, -1.2, { text: save.info }); }
  });

  /* Paste anywhere: the real enrichment endpoint reads it while it falls; the band shows what it found. */
  document.addEventListener('paste', (e) => {
    const el = document.activeElement;
    if (el && (el.isContentEditable || /^(INPUT|TEXTAREA)$/.test(el.tagName))) return;
    const text = (e.clipboardData && e.clipboardData.getData('text') || '').trim().replace(/\s+/g, ' ');
    if (!text || !onScreen || S.reduced()) return;
    const isUrl = S.looksLikeUrl(text);
    const label = isUrl ? text.replace(/^https?:\/\/(www\.)?/i, '').replace(/[?#].*$/, '').slice(0, 52) : `note: ${text.slice(0, 40)}${text.length > 40 ? '…' : ''}`;
    const info = {
      live: true, complete: false, band: null, head: label.toLowerCase(), what: '', facts: [],
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
    toss(text.length > 52 ? text.slice(0, 51) + '…' : text, W * 0.62, Math.max(textBottom() + 14, surfaceY(W * 0.62) - 200), -1, -1.4, info);
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

  /* `#still`: a frozen, representative frame for renders — motion in the water, one save mid-toss,
     one just landed with its pulse and its decrypted findings. (Reduced motion: calm tank only.) */
  function stillFrame() {
    for (let i = 0; i < 170; i++) { t += 1 / 60; idlePaddle(1 / 60); step((1 / 60) * TIME, 0.55 * Math.sin(t * 0.47), 0); }
    render();
    const now = performance.now();
    const x = W * 0.46;
    pulses.push({ x, y: surfaceY(x) + cell * 2, t0: now - 520 });
    const b = spawnBand(SAVES[0].info, x, false);
    b.reveal = b.reveal.map(() => now - 1000);
    b.hideAt = 0;
    render(now);
    const el = document.createElement('span');
    el.className = 'drop';
    el.textContent = SAVES[1].tag;
    dropLayer.appendChild(el);
    const dx = S.clamp(W * 0.8 - el.offsetWidth / 2, 8, W - el.offsetWidth - 8);
    el.style.transform = `translate(${dx}px, ${surfaceY(W * 0.8) - 110}px) rotate(4deg)`;
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
    updateDrops();
    if (!S.reduced()) {
      nextToss -= now - (lastFrame || now);
      if (nextToss <= 0) { tossNext(); nextToss = 4200 + Math.random() * 2600; }
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
  S.onSpot(() => { if (fluid) { buildAtlas(); render(); } });

  document.fonts.load('11px Pixel').catch(() => {}).then(() => {
    const r = hero.getBoundingClientRect(); lastW = r.width; lastH = r.height;
    boot();
  });
})();
