import { incomeState, validateScenario } from './rules.js';
import { evaluateTasks, secondsToTasks } from './completion.js';
import { applyPurchase, choosePurchases } from './decisions.js';

function validateInputs(shop, g, opts) {
  for (const key of ['dishes', 'cap', 'staff0', 'staffMax', 'volMax'])
    if (!Number.isInteger(shop[key]) || shop[key] < 0) throw new RangeError(`Invalid shop ${key}`);
  if (shop.dishes < 1 || shop.cap < 1 || shop.staffMax < shop.staff0) throw new RangeError('Invalid shop limits');
  if (![shop.c0, shop.d0].every(x => Number.isFinite(x) && x >= 0)) throw new RangeError('Invalid capacities');
  for (const key of ['pg', 'cg', 'starMult', 'starEvery', 'p0', 'perStaff', 'unlockAt', 'newDishFactor'])
    if (!Number.isFinite(g[key]) || g[key] <= 0) throw new RangeError(`Invalid global ${key}`);
  for (const key of ['rM', 'rS', 'rL', 'capStep', 'volGrow'])
    if (!Number.isFinite(g[key]) || g[key] < 0) throw new RangeError(`Invalid global ${key}`);
  if (!(g.newShare > 0 && g.newShare < 1)) throw new RangeError('newShare must be between zero and one');
  if (!['roi', 'routine'].includes(opts.strategy)) throw new RangeError('Unknown strategy');
  for (const key of ['every', 'initialGold'])
    if (!Number.isFinite(opts[key]) || opts[key] < 0) throw new RangeError(`Invalid ${key}`);
  if (!Number.isFinite(opts.maxSeconds) || opts.maxSeconds <= 0) throw new RangeError('Invalid horizon');
  const baseStep = g.pg ** (g.unlockAt - 1) * g.starMult ** Math.floor(g.unlockAt / g.starEvery) * g.newDishFactor;
  const maxBase = g.p0 * Math.max(1, baseStep) ** (shop.dishes - 1);
  const maxPrice = maxBase * Math.max(1, g.pg) ** (shop.cap - 1) * Math.max(1, g.starMult) ** Math.floor(shop.cap / g.starEvery);
  const maxUpgrade = 4 * maxBase * Math.max(1, g.cg) ** (shop.cap - 1);
  const maxCost = maxUpgrade * Math.max(1, g.rM, g.rS, g.rL) * (1 + g.volGrow) ** shop.volMax;
  const maxFlow = Math.max(1, shop.c0, (shop.staffMax + shop.volMax) * g.perStaff) * (1 + g.capStep) ** shop.volMax;
  const bounds = [maxBase, maxPrice, maxCost * (shop.dishes * shop.cap + 3 * shop.volMax), maxPrice * maxFlow * opts.multiplier * opts.maxSeconds];
  if (!bounds.every(Number.isFinite)) throw new RangeError('Economic parameters exceed numeric range');
}

export function estimateOfflineIncome(onlinePerSecond, secondsAway, capSeconds) {
  if (![onlinePerSecond, secondsAway, capSeconds].every(x => Number.isFinite(x) && x >= 0))
    throw new RangeError('Offline estimate requires an explicit nonnegative duration cap');
  return onlinePerSecond * Math.min(secondsAway, capSeconds) / 10;
}

export function simulateShop(shop, g, scenario, options = {}) {
  const opts = { strategy: 'roi', every: 0, initialGold: 60, maxSeconds: 172800, multiplier: 1, tasks: null, ...options };
  validateInputs(shop, g, opts); validateScenario(scenario);
  if (!Number.isFinite(opts.multiplier) || opts.multiplier <= 0) throw new RangeError('Invalid income multiplier');
  const configured = evaluateTasks(opts.tasks, [], false, shop.dishes) !== null;
  let state = { dishes: [{ p: g.p0, L: 1, w: 1 }], C: shop.c0, staff: shop.staff0, train: 1, kM: 0, kS: 0, kL: 0 };
  let t = 0, gold = opts.initialGold, fullLevelSeconds = null, taskCompletionSeconds = null;
  const sales = Array(shop.dishes).fill(0), unlocks = [], events = [];
  const spend = { price: 0, machine: 0, staff: 0, lure: 0, unlock: 0 };
  const bottleneckSeconds = { machine: 0, labor: 0, demand: 0 };
  const menuComplete = () => state.dishes.length === shop.dishes;
  const full = () => menuComplete() && state.dishes.every(d => d.L >= shop.cap);
  const observe = () => {
    if (full() && fullLevelSeconds === null) fullLevelSeconds = t;
    if (configured && taskCompletionSeconds === null && evaluateTasks(opts.tasks, sales, menuComplete(), shop.dishes).done)
      taskCompletionSeconds = t;
  };
  const advance = (seconds, stats) => {
    const rates = sales.map((_, i) => stats.flow * (state.dishes[i]?.w ?? 0));
    const remaining = secondsToTasks(opts.tasks, sales, rates, menuComplete());
    if (configured && taskCompletionSeconds === null && remaining <= seconds + 1e-9)
      taskCompletionSeconds = t + Math.min(seconds, remaining);
    rates.forEach((rate, i) => { sales[i] += seconds * rate; });
    gold += seconds * stats.revenue;
    bottleneckSeconds[stats.bottleneck] += seconds;
    t += seconds;
  };
  let stopReason = 'event_limit';
  for (let iteration = 0; iteration < 20000; iteration++) {
    observe();
    if (full() && (!configured || taskCompletionSeconds !== null)) {
      stopReason = configured ? 'tasks_and_reference_complete' : 'reference_complete'; break;
    }
    const stats = incomeState(state, g, scenario, opts.multiplier);
    if (!Number.isFinite(stats.revenue)) { stopReason = 'non_finite'; break; }
    if (t >= opts.maxSeconds) { stopReason = 'time_limit'; break; }
    if (full()) {
      if (stats.revenue <= 0) { stopReason = 'zero_income'; break; }
      const rates = sales.map((_, i) => stats.flow * (state.dishes[i]?.w ?? 0));
      const remaining = secondsToTasks(opts.tasks, sales, rates, menuComplete());
      if (!Number.isFinite(remaining)) { stopReason = 'unreachable_tasks'; break; }
      advance(Math.min(remaining, opts.maxSeconds - t), stats);
      continue;
    }
    const combo = choosePurchases(state, shop, g, scenario, opts.multiplier, opts.strategy, events.length);
    if (!combo) {
      if (configured && taskCompletionSeconds === null && menuComplete() && stats.revenue > 0) {
        const rates = sales.map((_, i) => stats.flow * (state.dishes[i]?.w ?? 0));
        const remaining = secondsToTasks(opts.tasks, sales, rates, true);
        if (Number.isFinite(remaining)) {
          advance(Math.min(remaining, opts.maxSeconds - t), stats);
          stopReason = taskCompletionSeconds === null ? 'time_limit' : 'tasks_complete_without_full_level';
          break;
        }
      }
      stopReason = stats.revenue <= 0 ? 'zero_income' : 'no_actions'; break;
    }
    const cost = combo.reduce((sum, o) => sum + o.cost, 0);
    if (!Number.isFinite(cost)) { stopReason = 'non_finite'; break; }
    if (gold < cost) {
      if (stats.revenue <= 0) { stopReason = 'zero_income'; break; }
      let wait = (cost - gold) / stats.revenue;
      if (opts.every) wait = Math.max(wait, Math.ceil((t + wait) / opts.every - 1e-12) * opts.every - t);
      const available = opts.maxSeconds - t;
      advance(Math.min(wait, available), stats);
      if (wait > available) { stopReason = 'time_limit'; break; }
    }
    gold = Math.max(0, gold - cost);
    for (const action of combo) {
      spend[action.kind] += action.cost;
      state = applyPurchase(state, action, shop, g);
      if (action.kind === 'unlock') unlocks.push(t);
    }
    events.push({ time: t, kinds: combo.map(o => o.kind), cost });
  }
  observe();
  const totalSpend = Object.values(spend).reduce((a, b) => a + b, 0);
  const last = incomeState(state, g, scenario, opts.multiplier);
  const gaps = events.map((event, i) => event.time - (events[i - 1]?.time ?? 0));
  return {
    elapsedSeconds: t, fullLevelSeconds, taskCompletionSeconds,
    tasks: evaluateTasks(opts.tasks, sales, menuComplete(), shop.dishes), menuComplete: menuComplete(),
    stopReason, sales, unlocks, events, spend, totalSpend,
    spendShares: Object.fromEntries(Object.entries(spend).map(([k, v]) => [k, totalSpend > 0 ? v / totalSpend : 0])),
    bottleneckSeconds, gapMaxSeconds: Math.max(0, ...gaps),
    gold, finalRevenuePerSecond: last.revenue, finalDemand: { attraction: last.attraction, returns: last.returns, quality: last.quality },
    levels: state.dishes.map(d => d.L), productionMode: 'online', strategy: opts.strategy,
    coverage: 'aggregate_capacity_not_physical_production',
  };
}
