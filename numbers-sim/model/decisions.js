import { dishPrice, upgradeCost, capacityCost, incomeState } from './rules.js';

export function purchaseOptions(state, shop, g) {
  const last = state.dishes.at(-1), options = [];
  if (state.dishes.length < shop.dishes && last.L >= g.unlockAt)
    options.push({ kind: 'unlock', cost: 20 * dishPrice(last, g) });
  state.dishes.forEach((d, index) => {
    if (d.L < shop.cap) options.push({ kind: 'price', index, cost: upgradeCost(d, g) });
  });
  const progress = (state.dishes.length - 1 + last.L / shop.cap) / shop.dishes;
  const volCap = Math.ceil(shop.volMax * Math.min(1, progress + .1));
  for (const [kind, key] of [['machine', 'kM'], ['staff', 'kS'], ['lure', 'kL']])
    if (state[key] < volCap) options.push({ kind, cost: capacityCost(state, g, kind) });
  return options;
}
export function applyPurchase(state, action, shop, g) {
  const s = { ...state, dishes: state.dishes.map(d => ({ ...d })) };
  if (action.kind === 'price') s.dishes[action.index].L++;
  else if (action.kind === 'machine') { s.C *= 1 + g.capStep; s.kM++; }
  else if (action.kind === 'staff') {
    if (s.staff < shop.staffMax) s.staff++;
    else s.train *= 1 + g.capStep;
    s.kS++;
  } else if (action.kind === 'lure') s.kL++;
  else if (action.kind === 'unlock') {
    const p = dishPrice(s.dishes.at(-1), g) * g.newDishFactor;
    s.dishes.forEach(d => { d.w *= 1 - g.newShare; });
    s.dishes.push({ p, L: 1, w: g.newShare });
  } else throw new TypeError('Unknown purchase kind');
  return s;
}
export function choosePurchases(state, shop, g, scenario, multiplier, strategy, purchaseCount) {
  const options = purchaseOptions(state, shop, g);
  const unlock = options.find(o => o.kind === 'unlock');
  if (unlock) return [unlock];
  if (strategy === 'routine') {
    // A stated non-adaptive habit, not a claim about real player behaviour.
    const order = ['price', 'machine', 'staff', 'lure'];
    for (let step = 0; step < order.length; step++) {
      const kind = order[(purchaseCount + step) % order.length];
      const matches = options.filter(o => o.kind === kind);
      if (matches.length) return [matches.reduce((a, b) => a.cost <= b.cost ? a : b)];
    }
    return null;
  }
  const base = incomeState(state, g, scenario, multiplier).revenue;
  let best = null;
  const score = combo => {
    const trial = combo.reduce((s, o) => applyPurchase(s, o, shop, g), state);
    const gain = incomeState(trial, g, scenario, multiplier).revenue - base;
    const cost = combo.reduce((sum, o) => sum + o.cost, 0);
    if (gain <= 1e-12 * Math.max(1, base)) return;
    const payback = cost / gain;
    if (!best || payback < best.payback) best = { payback, combo };
  };
  options.forEach(o => score([o]));
  const capacity = options.filter(o => o.kind !== 'price');
  for (let i = 0; i < capacity.length; i++) for (let j = i + 1; j < capacity.length; j++) {
    score([capacity[i], capacity[j]]);
    for (let k = j + 1; k < capacity.length; k++) score([capacity[i], capacity[j], capacity[k]]);
  }
  return best?.combo ?? null;
}
