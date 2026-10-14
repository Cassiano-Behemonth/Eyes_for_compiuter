/**
 * Motor procedural do Olho do Dragão / Criatura
 * Adaptado fielmente das fórmulas e algoritmos em CoreGraphics/Swift
 */

class SeededRandom {
  constructor(seed = 1234) {
    this.state = (BigInt(seed) + 0x9E3779B97F4A7C15n) & 0xFFFFFFFFFFFFFFFFn;
  }
  next() {
    this.state = (this.state * 6364136223846793005n + 1442695040888963407n) & 0xFFFFFFFFFFFFFFFFn;
    const val = Number((this.state >> 33n) & 0xFFFFFFn);
    return val / 0xFFFFFF;
  }
  range(lo, hi) {
    return lo + (hi - lo) * this.next();
  }
}

class CreatureEyeEngine {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d', { alpha: false });
    this.theme = window.ThemeManager.current;

    // Dimensões
    this.width = 0;
    this.height = 0;
    this.scale = window.devicePixelRatio || 1;
    this.a = 0;       // meia-largura do olho
    this.b = 0;       // meia-altura do olho
    this.irisR = 0;   // raio da íris
    this.center = { x: 0, y: 0 };

    // Texturas em cache (desenhadas uma vez e reutilizadas a 60fps)
    this.skinCanvas = document.createElement('canvas');
    this.scleraCanvas = document.createElement('canvas');
    this.irisCanvas = document.createElement('canvas');
    this.texturesReady = false;

    // Estado da animação
    this.target = null; // { x: -1..1, y: -1..1 }
    this.closeness = 0;
    this.gaze = { x: 0, y: 0 };
    this.pupilWidth = 0.42;
    this.openness = 1.0;

    this.lastStep = performance.now();
    this.lastTargetTime = performance.now();
    this.hadTarget = false;
    this.wander = { x: 0, y: 0 };
    this.nextWander = 0;

    this.blinkStart = null;
    this.blinkMembrane = false;
    this.nextBlink = performance.now() + 4000;

    this.breathPhase = 0;
    this.angerStart = -100000;
    this.startle = -100000;
    this.rng = new SeededRandom(Date.now());

    this.animId = null;
    this.onResize();
  }

  setTheme(newTheme) {
    this.theme = newTheme;
    this.buildTextures();
  }

  onResize() {
    const rect = this.canvas.getBoundingClientRect();
    this.width = rect.width;
    this.height = rect.height;
    this.scale = window.devicePixelRatio || 1;

    this.canvas.width = Math.ceil(this.width * this.scale);
    this.canvas.height = Math.ceil(this.height * this.scale);

    const a = Math.min(this.width * 0.36, this.height * 0.6);
    const b = a * 0.4;
    this.a = a;
    this.b = b;
    this.irisR = b * 1.32;
    this.center = { x: this.width / 2, y: this.height * 0.52 };

    this.buildTextures();
  }

  // ================= TEXTURAS PROCEDURAIS =================

  buildTextures() {
    this.buildSkin();
    this.buildSclera();
    this.buildIris();
    this.texturesReady = true;
  }

  buildSkin() {
    const c = this.skinCanvas;
    c.width = Math.ceil(this.width * this.scale);
    c.height = Math.ceil(this.height * this.scale);
    const ctx = c.getContext('2d');
    ctx.scale(this.scale, this.scale);

    const w = this.width;
    const h = this.height;
    const eyeCenter = this.center;
    const a = this.a;
    const b = this.b;
    const theme = this.theme;
    let rng = new SeededRandom(1234);

    // Fundo escuro base das escamas
    ctx.fillStyle = shadeColor(theme.escamas, 0.07);
    ctx.fillRect(0, 0, w, h);

    function lightAt(p) {
      const dx = (p.x - eyeCenter.x) / (a * 1.5);
      const dy = (p.y - eyeCenter.y) / (a * 0.95);
      return Math.exp(-(dx * dx + dy * dy));
    }

    // Escamas em fileiras
    const sw = a * 0.13;
    const rowH = sw * 0.42;
    let row = 0;
    let y = -sw;

    while (y < h + sw) {
      let x = (row % 2 === 0 ? 0 : sw / 2) - sw;
      while (x < w + sw) {
        const jx = x + rng.range(-sw * 0.04, sw * 0.04);
        const l = lightAt({ x: jx, y: y + sw * 0.3 }) * rng.range(0.75, 1.15);
        const base = 0.13 + 0.87 * l;

        // Desenho da escama individual
        ctx.save();
        ctx.beginPath();
        ctx.moveTo(jx - sw / 2, y + sw * 0.8);
        ctx.lineTo(jx - sw / 2, y + sw * 0.35);
        ctx.quadraticCurveTo(jx - sw / 2, y + sw * 0.02, jx, y);
        ctx.quadraticCurveTo(jx + sw / 2, y + sw * 0.02, jx + sw / 2, y + sw * 0.35);
        ctx.lineTo(jx + sw / 2, y + sw * 0.8);
        ctx.closePath();

        // Sombra da escama projetada
        ctx.shadowColor = 'rgba(0,0,0,0.6)';
        ctx.shadowOffsetY = sw * 0.05;
        ctx.shadowBlur = sw * 0.1;

        // Gradiente interno da escama
        const grad = ctx.createLinearGradient(jx, y + sw * 0.8, jx, y + sw * 0.1);
        grad.addColorStop(0, shadeColor(theme.escamas, base * 0.45));
        grad.addColorStop(1, shadeColor(theme.escamas, base));
        ctx.fillStyle = grad;
        ctx.fill();

        // Borda inferior iluminada
        ctx.shadowColor = 'transparent';
        ctx.beginPath();
        ctx.moveTo(jx - sw / 2, y + sw * 0.35);
        ctx.quadraticCurveTo(jx - sw / 2, y + sw * 0.02, jx, y);
        ctx.quadraticCurveTo(jx + sw / 2, y + sw * 0.02, jx + sw / 2, y + sw * 0.35);
        ctx.strokeStyle = shadeColor(theme.escamas, base * 1.7, 0.8);
        ctx.lineWidth = Math.max(1, sw * 0.03);
        ctx.stroke();

        ctx.restore();
        x += sw;
      }
      y += rowH;
      row++;
    }

    // Pele das pálpebras
    ctx.save();
    this.traceAlmond(ctx, eyeCenter, a, b, 1.0);
    ctx.clip();
    const radGrad = ctx.createRadialGradient(
      eyeCenter.x, eyeCenter.y - b * 0.1, 0,
      eyeCenter.x, eyeCenter.y - b * 0.1, a * 1.1
    );
    radGrad.addColorStop(0, shadeColor(theme.escamas, 0.76));
    radGrad.addColorStop(0.6, shadeColor(theme.escamas, 0.43));
    radGrad.addColorStop(1, shadeColor(theme.escamas, 0.14));
    ctx.fillStyle = radGrad;
    ctx.fill();

    // Grânulos da pálpebra
    const numGranules = Math.floor(a * 1.2);
    for (let i = 0; i < numGranules; i++) {
      const gx = eyeCenter.x + rng.range(-a * 1.1, a * 1.1);
      const gy = eyeCenter.y + rng.range(-b * 1.5, b * 1.5);
      const gr = b * rng.range(0.015, 0.04);
      ctx.fillStyle = rng.next() < 0.5 ? 'rgba(0,0,0,0.35)' : shadeColor(theme.escamas, 1.25, 0.18);
      ctx.beginPath();
      ctx.ellipse(gx, gy, gr, gr * 0.8, 0, 0, Math.PI * 2);
      ctx.fill();
    }

    // Vincos da pálpebra
    for (let o = 0.12; o <= 1.0; o += 0.11) {
      ctx.beginPath();
      this.traceAlmond(ctx, eyeCenter, a * (1 - 0.04 * o), b, o);
      ctx.strokeStyle = 'rgba(0,0,0,0.45)';
      ctx.lineWidth = Math.max(1, b * 0.022);
      ctx.stroke();

      ctx.beginPath();
      this.traceAlmond(ctx, { x: eyeCenter.x, y: eyeCenter.y - b * 0.025 }, a * (1 - 0.04 * o), b, o);
      ctx.strokeStyle = shadeColor(theme.escamas, 1.4, 0.18);
      ctx.lineWidth = Math.max(1, b * 0.012);
      ctx.stroke();
    }
    ctx.restore();

    // 9 Anéis concêntricos de escamas em volta do olho
    let sizes = [];
    let offsets = [];
    let acc = b * 0.12;
    for (let k = 0; k < 9; k++) {
      const s = a * 0.055 * (1 + 0.3 * k);
      sizes.push(s);
      offsets.push(acc + s * 0.5);
      acc += s * 0.78;
    }

    for (let k = sizes.length - 1; k >= 0; k--) {
      const s = sizes[k];
      const rx = a * 1.0 + offsets[k] * 1.05;
      const ry = b * 1.05 + offsets[k];
      const perimeter = Math.PI * (3 * (rx + ry) - Math.sqrt((3 * rx + ry) * (rx + 3 * ry)));
      const n = Math.max(8, Math.floor(perimeter / (s * 0.82)));
      const phase = k % 2 === 0 ? 0 : Math.PI / n;
      const ringLight = Math.exp(-k * 0.3);

      for (let i = 0; i < n; i++) {
        const t = (i / n) * Math.PI * 2 + phase + rng.range(-0.01, 0.01);
        const px = eyeCenter.x + Math.cos(t) * rx;
        const py = eyeCenter.y + Math.sin(t) * ry;
        const normal = Math.atan2(Math.sin(t) * rx, Math.cos(t) * ry);
        const ew = s * rng.range(0.95, 1.12);
        const eh = s * rng.range(0.78, 0.92);
        const l = ringLight * (0.75 + 0.25 * Math.max(0, -Math.sin(t))) * rng.range(0.8, 1.15);

        ctx.save();
        ctx.translate(px, py);
        ctx.rotate(normal - Math.PI / 2);

        ctx.beginPath();
        ctx.moveTo(-ew / 2, eh * 0.1);
        ctx.bezierCurveTo(-ew * 0.45, eh * 0.75, ew * 0.45, eh * 0.75, ew / 2, eh * 0.1);
        ctx.bezierCurveTo(ew * 0.5, -eh * 0.65, -ew * 0.5, -eh * 0.65, -ew / 2, eh * 0.1);
        ctx.closePath();

        ctx.shadowColor = 'rgba(0,0,0,0.95)';
        ctx.shadowBlur = s * 0.35;
        ctx.fillStyle = shadeColor(theme.escamas, 0.11);
        ctx.fill();

        ctx.shadowColor = 'transparent';
        const pgrad = ctx.createRadialGradient(0, -eh * 0.35, 0, 0, eh * 0.1, ew * 0.75);
        pgrad.addColorStop(0, shadeColor(theme.escamas, 1.45 * l));
        pgrad.addColorStop(0.55, shadeColor(theme.escamas, 0.58 * l));
        pgrad.addColorStop(1, shadeColor(theme.escamas, 0.09));
        ctx.fillStyle = pgrad;
        ctx.fill();

        ctx.restore();
      }
    }

    // Vinheta nas bordas da tela
    const maxDim = Math.max(w, h);
    const vign = ctx.createRadialGradient(eyeCenter.x, eyeCenter.y, a * 0.9, eyeCenter.x, eyeCenter.y, maxDim * 0.75);
    vign.addColorStop(0, 'rgba(0,0,0,0)');
    vign.addColorStop(0.6, 'rgba(0,0,0,0.6)');
    vign.addColorStop(1, 'rgba(0,0,0,0.96)');
    ctx.fillStyle = vign;
    ctx.fillRect(0, 0, w, h);
  }

  buildSclera() {
    const c = this.scleraCanvas;
    const sw = this.a * 2;
    const sh = this.b * 2.8;
    c.width = Math.ceil(sw * this.scale);
    c.height = Math.ceil(sh * this.scale);
    const ctx = c.getContext('2d');
    ctx.scale(this.scale, this.scale);

    const cx = sw / 2;
    const cy = sh / 2;
    const theme = this.theme;
    let rng = new SeededRandom(99);

    // Gradiente esclera
    const sgrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, sw / 2);
    const stops = theme.esclera;
    for (let i = 0; i < stops.length; i++) {
      sgrad.addColorStop(i / (stops.length - 1), stops[i]);
    }
    ctx.fillStyle = sgrad;
    ctx.fillRect(0, 0, sw, sh);

    // 44 veias ramificadas
    for (let i = 0; i < 44; i++) {
      const fromLeft = rng.next() < 0.5;
      let p = {
        x: fromLeft ? rng.range(0, sw * 0.12) : rng.range(sw * 0.88, sw),
        y: rng.range(sh * 0.2, sh * 0.8)
      };
      let heading = Math.atan2(cy - p.y, cx - p.x) + rng.range(-0.6, 0.6);
      const steps = Math.floor(rng.range(10, 26));
      let lineWidth = sw * rng.range(0.002, 0.005);

      for (let s = 0; s < steps; s++) {
        heading += rng.range(-0.45, 0.45);
        const next = {
          x: p.x + Math.cos(heading) * sw * 0.012,
          y: p.y + Math.sin(heading) * sw * 0.012
        };
        ctx.strokeStyle = colorWithAlpha(theme.veias, 0.55);
        ctx.lineWidth = Math.max(0.5, lineWidth);
        ctx.beginPath();
        ctx.moveTo(p.x, p.y);
        ctx.lineTo(next.x, next.y);
        ctx.stroke();
        p = next;
        lineWidth *= 0.92;
      }
    }
  }

  buildIris() {
    const c = this.irisCanvas;
    const R = this.irisR;
    c.width = Math.ceil(R * 2 * this.scale);
    c.height = Math.ceil(R * 2 * this.scale);
    const ctx = c.getContext('2d');
    ctx.scale(this.scale, this.scale);

    const cx = R;
    const cy = R;
    const theme = this.theme;
    let rng = new SeededRandom(7);

    ctx.save();
    ctx.beginPath();
    ctx.arc(cx, cy, R, 0, Math.PI * 2);
    ctx.clip();

    // Gradiente base da íris
    const igrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, R);
    const stops = theme.iris;
    for (let i = 0; i < stops.length; i++) {
      igrad.addColorStop(i / (stops.length - 1), stops[i]);
    }
    ctx.fillStyle = igrad;
    ctx.fillRect(0, 0, R * 2, R * 2);

    // 1600 fibras radiais
    const fibers = theme.fibras;
    for (let i = 0; i < 1600; i++) {
      const angle = rng.range(0, Math.PI * 2);
      const r0 = R * rng.range(0.08, 0.45);
      const r1 = R * rng.range(0.55, 1.0);
      const wobble = rng.range(-0.09, 0.09);
      const pick = rng.next();
      let color;
      if (pick < 0.4) {
        color = colorWithAlpha(fibers[0], rng.range(0.08, 0.3));
      } else if (pick < 0.75) {
        color = colorWithAlpha(fibers[1], rng.range(0.1, 0.35));
      } else {
        color = colorWithAlpha(fibers[2], rng.range(0.2, 0.5));
      }

      const p0 = { x: cx + Math.cos(angle) * r0, y: cy + Math.sin(angle) * r0 };
      const p1 = { x: cx + Math.cos(angle + wobble) * r1, y: cy + Math.sin(angle + wobble) * r1 };
      const ctrl = {
        x: cx + Math.cos(angle - wobble * 1.5) * (r0 + r1) / 2,
        y: cy + Math.sin(angle - wobble * 1.5) * (r0 + r1) / 2
      };

      ctx.strokeStyle = color;
      ctx.lineWidth = rng.range(0.6, 2.4) * (R / 300);
      ctx.beginPath();
      ctx.moveTo(p0.x, p0.y);
      ctx.quadraticCurveTo(ctrl.x, ctrl.y, p1.x, p1.y);
      ctx.stroke();
    }

    // 80 criptas escuras
    for (let i = 0; i < 80; i++) {
      const cr = R * rng.range(0.35, 0.8);
      const ca = rng.range(0, Math.PI * 2);
      const px = cx + Math.cos(ca) * cr;
      const py = cy + Math.sin(ca) * cr;
      const s = R * rng.range(0.015, 0.055);
      ctx.fillStyle = shadeColor(fibers[2], 0.64, rng.range(0.25, 0.5));
      ctx.beginPath();
      ctx.ellipse(px, py, s, s * 0.7, 0, 0, Math.PI * 2);
      ctx.fill();
    }

    // Colarete ondulado
    ctx.beginPath();
    for (let i = 0; i <= 240; i++) {
      const t = (i / 240) * Math.PI * 2;
      const r = R * (0.4 + 0.025 * Math.sin(t * 23) + 0.012 * Math.sin(t * 7));
      const px = cx + Math.cos(t) * r;
      const py = cy + Math.sin(t) * r;
      if (i === 0) ctx.moveTo(px, py);
      else ctx.lineTo(px, py);
    }
    ctx.strokeStyle = colorWithAlpha(theme.iris[0], 0.35);
    ctx.lineWidth = R * 0.014;
    ctx.stroke();

    // Brilho interno perto da pupila
    const pglow = ctx.createRadialGradient(cx, cy, 0, cx, cy, R * 0.32);
    pglow.addColorStop(0, colorWithAlpha(theme.iris[0], 0.55));
    pglow.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = pglow;
    ctx.beginPath();
    ctx.arc(cx, cy, R * 0.32, 0, Math.PI * 2);
    ctx.fill();

    // Anel límbico escuro
    const darkLimbal = shadeColor(fibers[2], 0.27);
    const lgrad = ctx.createRadialGradient(cx, cy, R * 0.8, cx, cy, R);
    lgrad.addColorStop(0, colorWithAlpha(darkLimbal, 0));
    lgrad.addColorStop(0.6, colorWithAlpha(darkLimbal, 0.6));
    lgrad.addColorStop(1, colorWithAlpha(darkLimbal, 0.97));
    ctx.fillStyle = lgrad;
    ctx.beginPath();
    ctx.arc(cx, cy, R, 0, Math.PI * 2);
    ctx.fill();

    ctx.restore();
  }

  // ================= FORMAS DO OLHO =================

  traceAlmond(ctx, center, a, b, openness) {
    const left = { x: center.x - a, y: center.y - b * 0.1 };
    const right = { x: center.x + a, y: center.y + b * 0.08 };
    const up = b * 1.36 * openness;
    const down = b * 1.28 * openness;

    ctx.moveTo(left.x, left.y);
    ctx.bezierCurveTo(
      center.x - a * 0.5, center.y + up,
      center.x + a * 0.45, center.y + up * 1.02,
      right.x, right.y
    );
    ctx.bezierCurveTo(
      center.x + a * 0.5, center.y - down,
      center.x - a * 0.45, center.y - down,
      left.x, left.y
    );
  }

  traceSlit(ctx, cx, cy, w, h) {
    const c = (w / 2) / 0.75;
    ctx.moveTo(cx, cy + h / 2);
    ctx.bezierCurveTo(cx + c, cy + h / 4, cx + c, cy - h / 4, cx, cy - h / 2);
    ctx.bezierCurveTo(cx - c, cy - h / 4, cx - c, cy + h / 4, cx, cy + h / 2);
  }

  // ================= LOOP DE ANIMAÇÃO =================

  start() {
    if (this.animId) return;
    const loop = (t) => {
      this.step(t);
      this.animId = requestAnimationFrame(loop);
    };
    this.animId = requestAnimationFrame(loop);
  }

  stop() {
    if (this.animId) {
      cancelAnimationFrame(this.animId);
      this.animId = null;
    }
  }

  step(t) {
    if (!this.texturesReady) return;
    const dt = Math.min(Math.max((t - this.lastStep) / 1000, 0), 0.05);
    this.lastStep = t;

    // Alvo para o olhar
    let desired;
    if (this.target) {
      desired = this.target;
      if (!this.hadTarget) this.startle = t;
      this.hadTarget = true;
      this.lastTargetTime = t;
    } else {
      this.hadTarget = false;
      if (t >= this.nextWander) {
        this.wander = {
          x: this.rng.range(-0.75, 0.75),
          y: this.rng.range(-0.45, 0.45)
        };
        this.nextWander = t + this.rng.range(1500, 4200);
      }
      desired = this.wander;
    }

    const gk = this.target ? 9 : 2.5;
    this.gaze.x += (desired.x - this.gaze.x) * (1 - Math.exp(-gk * dt));
    this.gaze.y += (desired.y - this.gaze.y) * (1 - Math.exp(-gk * dt));

    const angerK = (t - this.angerStart < 1600) ? 1 - (t - this.angerStart) / 1600 : 0;
    const startleK = (t - this.startle < 600) ? 1 - (t - this.startle) / 600 : 0;

    // Pupila
    let desiredPupil = this.target ? (0.16 - 0.08 * this.closeness) : 0.42;
    if (startleK > 0) desiredPupil = 0.05;
    if (angerK > 0) desiredPupil = 0.035;
    const pk = desiredPupil < this.pupilWidth ? 10 : 2.5;
    this.pupilWidth += (desiredPupil - this.pupilWidth) * (1 - Math.exp(-pk * dt));

    // Abertura das pálpebras
    let desiredOpen = 1.0;
    if (!this.target && (t - this.lastTargetTime > 20000)) desiredOpen = 0.6;
    if (startleK > 0) desiredOpen = 1.15;
    if (angerK > 0) desiredOpen = 0.65;
    const ok = desiredOpen > this.openness ? 5 : 2;
    this.openness += (desiredOpen - this.openness) * (1 - Math.exp(-ok * dt));

    // Piscadas
    let lid = 1.0;
    let membraneK = 0;
    if (!this.blinkStart && t >= this.nextBlink) {
      this.blinkStart = t;
      this.blinkMembrane = this.rng.next() < 0.4;
      this.nextBlink = t + this.rng.range(3200, 8500);
    }
    if (this.blinkStart) {
      const e = (t - this.blinkStart) / 1000;
      if (this.blinkMembrane) {
        membraneK = e < 0.7 ? Math.sin(Math.PI * e / 0.7) : 0;
        if (e >= 0.7) this.blinkStart = null;
      } else {
        if (e < 0.11) lid = 1 - e / 0.11;
        else if (e < 0.15) lid = 0;
        else if (e < 0.36) lid = (e - 0.15) / 0.21;
        if (e >= 0.36) this.blinkStart = null;
      }
    }

    const currentOpenness = Math.max(0, this.openness * Math.min(Math.max(lid, 0), 1));

    // Respiração
    const period = angerK > 0 ? 1.3 : (this.target ? 3.0 : 4.2);
    this.breathPhase = (this.breathPhase + dt / period) % 1;
    const bp = this.breathPhase;
    const breath = bp < 0.35 ? -Math.cos(Math.PI * bp / 0.35) : Math.cos(Math.PI * (bp - 0.35) / 0.65);
    const amp = 1 + 0.6 * angerK;
    const breathScale = 1.03 + 0.012 * breath * amp;
    const breathY = this.height * 0.012 * breath * amp;

    // RENDERIZAÇÃO
    const ctx = this.ctx;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = '#000000';
    ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    ctx.save();
    ctx.scale(this.scale, this.scale);

    // Transformação orgânica da respiração
    ctx.save();
    ctx.translate(this.center.x, this.center.y);
    ctx.scale(breathScale, breathScale);
    ctx.translate(-this.center.x, -this.center.y + breathY);

    // 1. Pele e Escamas
    ctx.drawImage(this.skinCanvas, 0, 0, this.width, this.height);

    // 2. Brilho místico ao redor do olho
    const glowRad = ctx.createRadialGradient(
      this.center.x, this.center.y, this.a * 0.2,
      this.center.x, this.center.y, this.a * 1.6
    );
    const glowOp = 0.5 + 0.2 * breath + 0.35 * angerK;
    glowRad.addColorStop(0, colorWithAlpha(this.theme.brilho, glowOp * 0.5));
    glowRad.addColorStop(0.45, colorWithAlpha(this.theme.brilho, glowOp * 0.15));
    glowRad.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = glowRad;
    ctx.fillRect(this.center.x - this.a * 1.6, this.center.y - this.a * 1.0, this.a * 3.2, this.a * 2.0);

    // 3. Olho recortado pelas pálpebras
    ctx.save();
    ctx.beginPath();
    this.traceAlmond(ctx, this.center, this.a, this.b, currentOpenness);
    ctx.clip();

    // 3.1 Esclera (fundo com veias)
    const eyeBox = {
      x: this.center.x - this.a,
      y: this.center.y - this.b * 1.4,
      w: this.a * 2,
      h: this.b * 2.8
    };
    ctx.drawImage(this.scleraCanvas, eyeBox.x, eyeBox.y, eyeBox.w, eyeBox.h);

    // 3.2 Íris posicionada no olhar
    const maxX = this.a - this.irisR * 0.72;
    const maxY = this.b * 0.32;
    const irisX = this.center.x + this.gaze.x * maxX;
    const irisY = this.center.y + this.gaze.y * maxY;

    // Compressão de perspectiva quando olha para os lados
    const irisW = this.irisR * 2 * (1 - 0.14 * Math.abs(this.gaze.x));
    const irisH = this.irisR * 2;

    ctx.drawImage(this.irisCanvas, irisX - irisW / 2, irisY - irisH / 2, irisW, irisH);

    // Brilho de fúria na íris se estiver com raiva
    if (angerK > 0 || startleK > 0) {
      const heatOp = Math.max(angerK, startleK * 0.5);
      const heatGrad = ctx.createRadialGradient(irisX, irisY, 0, irisX, irisY, this.irisR);
      heatGrad.addColorStop(0, colorWithAlpha(this.theme.iris[0], 0.9 * heatOp));
      heatGrad.addColorStop(0.33, colorWithAlpha(this.theme.iris[Math.floor(this.theme.iris.length / 3)], 0.55 * heatOp));
      heatGrad.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = heatGrad;
      ctx.fillRect(irisX - irisW / 2, irisY - irisH / 2, irisW, irisH);
    }

    // 3.3 Pupila vertical de fenda
    ctx.save();
    ctx.beginPath();
    this.traceSlit(ctx, irisX, irisY, this.irisR * this.pupilWidth * 1.4, this.irisR * 1.72);
    ctx.shadowColor = '#000000';
    ctx.shadowBlur = this.irisR * 0.06;
    ctx.fillStyle = '#040000';
    ctx.fill();
    ctx.restore();

    // 3.4 Membrana nictitante (terceira pálpebra translúcida)
    if (membraneK > 0.001) {
      const mw = eyeBox.w * membraneK;
      const memGrad = ctx.createLinearGradient(eyeBox.x, eyeBox.y, eyeBox.x + mw, eyeBox.y);
      memGrad.addColorStop(0, 'rgba(255, 200, 176, 0.15)');
      memGrad.addColorStop(0.85, 'rgba(217, 128, 106, 0.42)');
      memGrad.addColorStop(1, 'rgba(255, 224, 208, 0.6)');
      ctx.fillStyle = memGrad;
      ctx.fillRect(eyeBox.x, eyeBox.y, mw, eyeBox.h);
    }

    // 3.5 Sombras das pálpebras superior e inferior
    const upShadow = ctx.createLinearGradient(0, eyeBox.y, 0, eyeBox.y + eyeBox.h * 0.45);
    upShadow.addColorStop(0, 'rgba(0,0,0,0.88)');
    upShadow.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = upShadow;
    ctx.fillRect(eyeBox.x, eyeBox.y, eyeBox.w, eyeBox.h * 0.45);

    const lowShadow = ctx.createLinearGradient(0, eyeBox.y + eyeBox.h, 0, eyeBox.y + eyeBox.h * 0.7);
    lowShadow.addColorStop(0, 'rgba(0,0,0,0.6)');
    lowShadow.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = lowShadow;
    ctx.fillRect(eyeBox.x, eyeBox.y + eyeBox.h * 0.7, eyeBox.w, eyeBox.h * 0.3);

    // 3.6 Brilhos especulares do globo ocular vítreo
    const h1 = ctx.createRadialGradient(
      this.center.x - this.a * 0.3, this.center.y - this.b * 0.1, 0,
      this.center.x - this.a * 0.3, this.center.y - this.b * 0.1, this.a * 0.25
    );
    h1.addColorStop(0, 'rgba(255,255,255,0.4)');
    h1.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = h1;
    ctx.fillRect(this.center.x - this.a * 0.55, this.center.y - this.b * 0.35, this.a * 0.5, this.b * 0.5);

    const h2 = ctx.createRadialGradient(
      this.center.x - this.a * 0.22, this.center.y - this.b * 0.15, 0,
      this.center.x - this.a * 0.22, this.center.y - this.b * 0.15, this.a * 0.05
    );
    h2.addColorStop(0, 'rgba(255,255,255,0.95)');
    h2.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = h2;
    ctx.fillRect(this.center.x - this.a * 0.28, this.center.y - this.b * 0.2, this.a * 0.12, this.b * 0.12);

    ctx.restore(); // fim do clip da amêndoa

    // 4. Borda externa e relevo da pálpebra
    ctx.beginPath();
    this.traceAlmond(ctx, this.center, this.a, this.b, currentOpenness);
    ctx.strokeStyle = '#050000';
    ctx.lineWidth = this.b * 0.07;
    ctx.stroke();

    ctx.beginPath();
    this.traceAlmond(ctx, this.center, this.a, this.b, currentOpenness);
    ctx.strokeStyle = shadeColor(this.theme.escamas, 0.43);
    ctx.lineWidth = this.b * 0.12;
    ctx.stroke();

    ctx.restore(); // fim da respiração
    ctx.restore(); // fim do scale
  }

  // Define posição do olhar em coordenadas normalizadas (-1 a 1)
  setLookTarget(normX, normY, closeness = 0) {
    this.target = {
      x: Math.min(Math.max(normX, -1), 1),
      y: Math.min(Math.max(normY, -1), 1)
    };
    this.closeness = Math.min(Math.max(closeness, 0), 1);
  }

  clearLookTarget() {
    this.target = null;
  }
}

window.CreatureEyeEngine = CreatureEyeEngine;
