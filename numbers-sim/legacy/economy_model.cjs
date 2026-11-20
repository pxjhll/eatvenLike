function simShop(shop, G, M, every) {
  const d = [{ p: G.p0, L: 1, w: 1 }];
  let hired = [], train = 1; let C = shop.c0, D = shop.d0, staff = shop.staff0, kM = 0, kL = 0, kS = 0;
  let t = 0, gold = 60, buys = [], spend = { price: 0, machine: 0, staff: 0, lure: 0, unlock: 0 };
  let bott = { machine: 0, labor: 0, demand: 0 }, unlocks = [], curve = [];
  const price = x => x.p * Math.pow(G.pg, x.L - 1) * Math.pow(G.starMult, Math.floor(x.L / G.starEvery));
  const stars = () => d.reduce((s, x) => s + Math.floor(x.L / G.starEvery), 0);
  const demand = () => D * Math.pow(G.flowStep, d.length - 1) * (1 + G.starArr * stars() / d.length);
  const labor = () => staff * G.perStaff * train;
  const state = () => {
    const dm = demand(), lb = labor(), x = Math.min(dm, C, lb);
    const b = x === dm ? 'demand' : x === C ? 'machine' : 'labor';
    return { inc: M * x * d.reduce((s, y) => s + y.w * price(y), 0), b };
  };
  // 同一把尺子：产能项价格 = 比例 × 当前各菜升级费的平均值（随店内进度一起涨）× 自身小梯子
  const ruler = () => d.reduce((s, x) => s + 4 * x.p * Math.pow(G.cg, x.L - 1), 0) / d.length;
  const ladder = (r, k) => r * ruler() * Math.pow(1 + G.volGrow, k);
  // 产能项随店内进度逐步开放（像原作按站点等级开放），防止开局一口气买满
  const volCap = () => Math.ceil(shop.volMax * Math.min(1, (d.length - 1 + d[d.length - 1].L / shop.cap) / shop.dishes + 0.1));
  const opts = () => {
    const o = [];
    if (d.length < shop.dishes && d[d.length - 1].L >= G.unlockAt)
      o.push({ k: 'unlock', c: 20 * price(d[d.length - 1]) });
    d.forEach((x, i) => { if (x.L < shop.cap) o.push({ k: 'price', i, c: 4 * x.p * Math.pow(G.cg, x.L - 1) }); });
    if (kM < volCap()) o.push({ k: 'machine', c: ladder(G.rM, kM) });
    if (kS < volCap()) o.push({ k: 'staff', c: ladder(G.rS, kS) });
    if (kL < volCap()) o.push({ k: 'lure', c: ladder(G.rL, kL) });
    return o;
  };
  const apply = (o, s) => {
    if (o.k === 'price') d[o.i].L += s;
    else if (o.k === 'machine') { C *= s > 0 ? 1 + G.capStep : 1 / (1 + G.capStep); kM += s; }
    else if (o.k === 'staff') { if (s > 0) { if (staff < shop.staffMax) { staff += 1; hired.push(1); } else { train *= 1 + G.capStep; hired.push(0); } } else { if (hired.pop()) staff -= 1; else train /= 1 + G.capStep; } kS += s; }
    else if (o.k === 'lure') { D *= s > 0 ? 1 + G.capStep : 1 / (1 + G.capStep); kL += s; }
  };
  const pick = () => {
    const o = opts(); const u = o.find(x => x.k === 'unlock'); if (u) return [u];
    const base = state().inc; let best = null;
    const cap = o.filter(x => x.k !== 'price');
    const tryCombo = combo => {
      combo.forEach(x => apply(x, 1)); const g = state().inc - base; combo.forEach(x => apply(x, -1));
      const c = combo.reduce((s, x) => s + x.c, 0);
      if (g > 1e-12 && (!best || c / g < best.r)) best = { r: c / g, combo };
    };
    o.forEach(x => tryCombo([x]));
    for (let i = 0; i < cap.length; i++) for (let j = i + 1; j < cap.length; j++) {
      tryCombo([cap[i], cap[j]]);
      for (let k = j + 1; k < cap.length; k++) tryCombo([cap[i], cap[j], cap[k]]);
    }
    return best ? best.combo : null;
  };
  const done = () => d.length === shop.dishes && d.every(x => x.L >= shop.cap);
  let guard = 0;
  while (!done() && guard++ < 20000) {
    const combo = pick(); if (!combo) break;
    const cost = combo.reduce((s, x) => s + x.c, 0);
    const st = state();
    if (gold < cost) {
      let wait = (cost - gold) / st.inc;
      if (every) wait = Math.ceil((t + wait) / every - 1e-9) * every - t;
      gold += wait * st.inc; bott[st.b] += wait; t += wait;
      curve.push([t, st.inc]);
      if (t > 3600 * 48) break;
    }
    gold -= cost; buys.push(t);
    for (const x of combo) {
      spend[x.k] += x.c;
      if (x.k === 'unlock') { const p = price(d[d.length - 1]) * G.newDishFactor; d.forEach(y => y.w *= 1 - G.newShare); d.push({ p, L: 1, w: G.newShare }); unlocks.push(t); }
      else apply(x, 1);
    }
  }
  const gaps = buys.slice(1).map((b, i) => b - buys[i]);
  const tot = Object.values(spend).reduce((a, b) => a + b, 0);
  const bt = Object.values(bott).reduce((a, b) => a + b, 0) || 1;
  return { t, done: done(), unlocks, buys: buys.length, gapMax: Math.max(0, ...gaps),
    spend: Object.fromEntries(Object.entries(spend).map(([k, v]) => [k, v / tot])),
    bott: Object.fromEntries(Object.entries(bott).map(([k, v]) => [k, v / bt])), curve, staff };
}
const G0 = { pg: 1.08, cg: 1.20, starEvery: 10, starMult: 2, starArr: 0.25, crossMult: 1.4, rM: 1.5, rS: 1.5, rL: 1.5,
  newDishFactor: 1.0, newShare: 0.45, flowStep: 1.25, capStep: 0.2, perStaff: 0.2, p0: 10, unlockAt: 10, volGrow: 0.2 };
const SHOPS0 = [
  { name: '奶茶店', type: '小店', dishes: 2, cap: 20, staff0: 1, staffMax: 3, volMax: 8, c0: 0.25, d0: 0.2 },
  { name: '煎饼果子店', type: '小店', dishes: 2, cap: 35, staff0: 2, staffMax: 5, volMax: 12, c0: 0.25, d0: 0.2 },
  { name: '面包店', type: '中店', dishes: 6, cap: 70, staff0: 2, staffMax: 8, volMax: 14, c0: 0.25, d0: 0.2 },
];
if (typeof module !== 'undefined') module.exports = { simShop, G0, SHOPS0 };
