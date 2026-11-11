export function dishPrice(dish, g) {
  return dish.p * g.pg ** (dish.L - 1) * g.starMult ** Math.floor(dish.L / g.starEvery);
}
export function upgradeCost(dish, g) { return 4 * dish.p * g.cg ** (dish.L - 1); }
export function capacityCost(state, g, kind) {
  const keys = { machine: ['rM', 'kM'], staff: ['rS', 'kS'], lure: ['rL', 'kL'] };
  if (!keys[kind]) throw new TypeError('Unknown capacity purchase');
  const [ratio, count] = keys[kind];
  const ruler = state.dishes.reduce((sum, dish) => sum + upgradeCost(dish, g), 0) / state.dishes.length;
  return g[ratio] * ruler * (1 + g.volGrow) ** state[count];
}
export function validateScenario(s) {
  for (const key of ['newVisits', 'returnAtQualityOne', 'baseQuality', 'overloadPenalty', 'postsPerDish', 'charm', 'perCharm'])
    if (!Number.isFinite(s?.[key]) || s[key] < 0) throw new RangeError(`Invalid scenario: ${key}`);
  if (s.baseQuality > 1) throw new RangeError('baseQuality must be within 0..1');
}
export function demandDetails(state, g, scenario) {
  validateScenario(scenario);
  // Explicit hypothesis: active dishes proxy simultaneous posts, not actual dispatch.
  const posts = state.dishes.length * scenario.postsPerDish;
  const overload = state.staff > 0 ? Math.max(0, posts / state.staff - 1) : (posts > 0 ? Infinity : 0);
  const penalty = scenario.overloadPenalty === 0 ? 0 : scenario.overloadPenalty * overload;
  const quality = Math.max(0, Math.min(1, scenario.baseQuality - penalty));
  const attraction = scenario.newVisits * (1 + scenario.charm * scenario.perCharm) * (1 + g.capStep) ** state.kL;
  const returns = scenario.returnAtQualityOne * quality;
  if (![attraction, returns, attraction + returns].every(Number.isFinite))
    throw new RangeError('Demand parameters exceed numeric range');
  return { attraction, returns, quality, total: attraction + returns };
}
export function incomeState(state, g, scenario, multiplier = 1) {
  const demand = demandDetails(state, g, scenario);
  const labor = state.staff * g.perStaff * state.train;
  const flow = Math.min(demand.total, state.C, labor);
  const revenue = flow * multiplier * state.dishes.reduce((sum, d) => sum + d.w * dishPrice(d, g), 0);
  const bottleneck = flow === demand.total ? 'demand' : flow === state.C ? 'machine' : 'labor';
  return { ...demand, flow, revenue, labor, bottleneck };
}
