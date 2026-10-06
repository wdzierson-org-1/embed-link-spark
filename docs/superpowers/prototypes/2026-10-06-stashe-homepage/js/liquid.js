/* Hero: the stash as a tank of liquid, drawn in ASCII.
   A FLIP fluid (particles + staggered MAC grid, after Matthias Müller's "Ten Minute Physics"
   FLIP demo) fills the bottom of the hero. Each character cell is shaded by how many particles
   it holds and how fast they move, so calm water reads as light dots and splashes as heavy
   glyphs. The pointer stirs it; clicks splash; saved things (tags) are tossed in and sink.
   Same idea and parameters as React Bits Pro "Liquid Ascii", written from scratch here. */
(() => {
  const S = window.Stashe;
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
  const P = { gravity: -9.81, flip: 0.86, pressureIters: 40, separationIters: 2, overRelax: 1.9, fill: 0.37 };
  let W = 0, H = 0, dpr = 1, cell = 16, font = 16.5, cols = 0, rows = 0, scale = 1, simW = 0;
  let fluid = null, expected = 3, ceilY = 0;
  let counts, speeds, surface;
  let atlas = null, glyph = 0;
  let running = false, onScreen = true, raf = 0;
  let t = 0, lastPointer = -1e9;
  const obs = { x: -9, y: -9, vx: 0, vy: 0, r: 0, px: -9, py: -9 };
  const pointer = { x: 0, y: 0, active: false };
  let simCost = 0;

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
    const pxPerUnit = scale;
    expected = (cell * cell) / (dx * pxPerUnit * dy * pxPerUnit);
    ceilY = Math.max(P.fill * SIM_H + 0.12, (H - (textBottom() + 64)) / scale);
    buildAtlas();
    // settle, with a gentle initial tilt so the first frame already has a shape
    for (let i = 0; i < 40; i++) step(1 / 60, 2.4 * Math.sin(i / 9), 0);
  }

  function buildAtlas() {
    glyph = Math.round(cell * dpr);
    atlas = document.createElement('canvas');
    atlas.width = glyph * RAMP.length; atlas.height = glyph;
    const a = atlas.getContext('2d');
    a.fillStyle = S.css('--ascii') || '#000';
    a.textAlign = 'center'; a.textBaseline = 'middle';
    a.font = `${font * dpr}px Pixel, ui-monospace, monospace`;
    for (let i = 1; i < RAMP.length; i++) a.fillText(RAMP[i], i * glyph + glyph / 2, glyph / 2 + dpr * 0.5);
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

  function render() {
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
    const last = RAMP.length - 1;
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const k = r * cols + c, n = counts[k];
        if (!n) continue;
        const sp = speeds[k] / n;
        // Denser with depth (water darkens as it deepens), heavier where it moves or crowds,
        // and a bright line along the surface.
        const depth = Math.min(1, (r - surface[c]) / 16);
        const jitter = (((c * 73856093) ^ (r * 19349663)) & 1023) / 1023 - 0.5; // breaks row banding
        let w = 0.1 + 0.4 * depth + 0.3 * Math.min(sp / 1.4, 1.6) + 0.08 * (n / expected - 1) + 0.16 * jitter;
        if (surface[c] === r) w += 0.3;
        const idx = Math.max(1, Math.min(last, 1 + Math.floor(w * 9)));
        ctx.globalAlpha = 0.62 + 0.38 * Math.min(1, w * 1.5);
        ctx.drawImage(atlas, idx * glyph, 0, glyph, glyph, Math.round(c * cell * dpr), Math.round(r * cell * dpr), glyph, glyph);
      }
    }
    ctx.globalAlpha = 1;
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

  /* Tossed-in saves */
  const SAVES = [
    'tiktok.com/@sundaysupper/video/7391…', 'Screenshot 2026-10-02 at 9.14 PM.png', 'arxiv.org/abs/2307.03172',
    'github.com/charmbracelet/gum', 'medium.com/…/why-you-remember-so-little', 'Voice memo 0:42.m4a', 'IMG_2213.HEIC',
    'maps.apple.com/?q=Chez+Colette', 'Kitchen, take two.png', 'youtube.com/watch?v=…', 'Walden — cover photo',
    'nytimes.com/…/best-weeknight-pasta', 'Boarding pass BOS→SFO.png', 'note: book the cabin for the long weekend',
  ];
  let saveIdx = 0;
  const drops = [];

  function toss(text, x, y, vx, vy) {
    if (drops.length > 6) return;
    const el = document.createElement('span');
    el.className = 'drop';
    el.textContent = text;
    dropLayer.appendChild(el);
    const d = { el, x, y, vx, vy, w: el.offsetWidth, h: el.offsetHeight, rot: (Math.random() - 0.5) * 10, vr: (Math.random() - 0.5) * 1.2, landed: false, t: 0 };
    d.x = S.clamp(d.x - d.w / 2, 8, W - d.w - 8);
    drops.push(d);
    place(d);
  }
  function place(d) { d.el.style.transform = `translate(${d.x.toFixed(1)}px, ${d.y.toFixed(1)}px) rotate(${d.rot.toFixed(2)}deg)`; }

  // Tossed saves start below the copy, so they never cross the headline or the buttons.
  function textBottom() {
    const inner = hero.querySelector('.hero-inner').getBoundingClientRect();
    return inner.bottom - hero.getBoundingClientRect().top;
  }
  function tossNext() {
    const text = SAVES[saveIdx++ % SAVES.length];
    const x = W * (0.1 + Math.random() * 0.8);
    const floor = textBottom() + 14;
    const y = Math.max(floor, surfaceY(x) - 150 - Math.random() * 60);
    if (surfaceY(x) - y < 40) return; // the liquid has climbed too high here; skip this one
    toss(text, x, y, (Math.random() - 0.5) * 2.4, -1.2 - Math.random() * 1.2);
  }

  function updateDrops() {
    for (let i = drops.length - 1; i >= 0; i--) {
      const d = drops[i];
      d.t++;
      if (!d.landed) {
        d.vy += 0.34; d.x += d.vx; d.y += d.vy; d.rot += d.vr;
        const cx = d.x + d.w / 2;
        if (d.y + d.h >= surfaceY(cx) + 4) {
          d.landed = true;
          splash(cx, surfaceY(cx), Math.min(3.4, 0.8 + d.vy * 0.22));
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
    if (y >= surfaceY(x) - 6) splash(x, y, 2.6);
    else toss(SAVES[saveIdx++ % SAVES.length], x, y - 10, (Math.random() - 0.5) * 2, -1.5);
  });

  document.addEventListener('paste', (e) => {
    const el = document.activeElement;
    if (el && (el.isContentEditable || /^(INPUT|TEXTAREA)$/.test(el.tagName))) return;
    const text = (e.clipboardData && e.clipboardData.getData('text') || '').trim().replace(/\s+/g, ' ');
    if (!text || !onScreen || S.reduced()) return;
    toss(text.length > 52 ? text.slice(0, 51) + '…' : text, W * 0.62, Math.max(80, surfaceY(W * 0.62) - 240), -1.2, -2.5);
    toast.textContent = 'Stashed. (In this prototype it only splashes.)';
    toast.classList.add('is-on');
    clearTimeout(toast._t);
    toast._t = setTimeout(() => toast.classList.remove('is-on'), 2600);
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

  /* `#still`: a frozen, representative frame for renders — some motion in the water and two
     saves caught mid-toss. (Reduced motion gets the calm, settled tank and no tags.) */
  function stillFrame() {
    for (let i = 0; i < 170; i++) { t += 1 / 60; idlePaddle(1 / 60); step(1 / 60, 0.55 * Math.sin(t * 0.47), 0); }
    render();
    const put = (text, fx, lift, rot) => {
      const el = document.createElement('span');
      el.className = 'drop';
      el.textContent = text;
      dropLayer.appendChild(el);
      const x = S.clamp(W * fx - el.offsetWidth / 2, 8, W - el.offsetWidth - 8);
      el.style.transform = `translate(${x}px, ${surfaceY(W * fx) - lift}px) rotate(${rot}deg)`;
    };
    put('tiktok.com/@sundaysupper/video/7391…', 0.7, 96, 4);
    put('Screenshot 2026-10-02 at 9.14 PM.png', 0.34, 30, -3);
  }

  /* ---------- loop ---------- */
  let nextToss = 1600, lastFrame = 0;
  function frame(now) {
    raf = 0;
    if (!running) return;
    const dt = 1 / 60;
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
    render();
    updateDrops();
    if (!S.reduced()) {
      nextToss -= now - (lastFrame || now);
      if (nextToss <= 0) { tossNext(); nextToss = 2300 + Math.random() * 1600; }
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
