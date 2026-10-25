import test from 'node:test';
import assert from 'node:assert/strict';
import { G0, SHOPS, SCENARIOS } from '../model/config.js';
const shop = { ...SHOPS[0], dishes: 1, cap: 1, c0: 1, staff0: 1, staffMax: 1, volMax: 0 };
const scenario = { ...SCENARIOS[0], newVisits: 1, returnAtQualityOne: 0, baseQuality: 1, overloadPenalty: 0 };

test('a full-price menu with no task specification is not reported as a completed shop', async () => {
  const { simulateShop } = await import('../model/simulate.js');
  const r = simulateShop(shop, G0, scenario);
  assert.equal(r.fullLevelSeconds, 0); assert.equal(r.taskCompletionSeconds, null);
  assert.equal(r.tasks, null); assert.equal(r.stopReason, 'reference_complete');
});
test('sales tasks can finish after max level with exact continuous flow timing', async () => {
  const { simulateShop } = await import('../model/simulate.js');
  const r = simulateShop(shop, G0, scenario, { tasks: [{ dish: 0, target: 2 }] });
  assert.equal(r.fullLevelSeconds, 0); assert.equal(r.taskCompletionSeconds, 10);
  assert.ok(Math.abs(r.sales[0] - 2) < 1e-9); assert.equal(r.tasks.done, true);
});
test('tasks may finish before full level and both times remain available', async () => {
  const { simulateShop } = await import('../model/simulate.js');
  const r = simulateShop({ ...shop, cap: 3 }, G0, scenario, { tasks: [{ dish: 0, target: 1 }] });
  assert.equal(r.taskCompletionSeconds, 5); assert.ok(r.fullLevelSeconds > 5);
});
test('missing dishes prevent menu completion despite old-dish sales targets being met', async () => {
  const { simulateShop } = await import('../model/simulate.js');
  const r = simulateShop({ ...shop, dishes: 2, cap: 1 }, G0, scenario, { tasks: [{ dish: 0, target: 1 }] });
  assert.equal(r.taskCompletionSeconds, null); assert.equal(r.fullLevelSeconds, null);
  assert.equal(r.stopReason, 'no_actions');
});
test('zero income ends as stalled rather than infinity or false completion', async () => {
  const { simulateShop } = await import('../model/simulate.js');
  const r = simulateShop({ ...shop, cap: 3 }, G0, { ...scenario, newVisits: 0 }, { initialGold: 0 });
  assert.equal(r.stopReason, 'zero_income'); assert.equal(r.fullLevelSeconds, null);
  assert.ok(Number.isFinite(r.elapsedSeconds));
});
test('available starting cash can hire out of zero production before waiting', async () => {
  const { simulateShop } = await import('../model/simulate.js');
  const r = simulateShop({ ...shop, cap: 2, staff0: 0, staffMax: 1, volMax: 1 }, G0, scenario, { initialGold: 60 });
  assert.notEqual(r.fullLevelSeconds, null);
  assert.equal(r.events[0].time, 0);
  assert.ok(r.events[0].kinds.includes('staff'));
});
test('time horizon is respected even when the next purchase would take much longer', async () => {
  const { simulateShop } = await import('../model/simulate.js');
  const r = simulateShop({ ...shop, cap: 3 }, G0, scenario, { initialGold: 0, maxSeconds: 1 });
  assert.equal(r.elapsedSeconds, 1); assert.equal(r.stopReason, 'time_limit');
  assert.equal(r.fullLevelSeconds, null);
});
test('periodic purchasing remains online and only happens at permitted times', async () => {
  const { simulateShop } = await import('../model/simulate.js');
  const r = simulateShop({ ...shop, cap: 3 }, G0, scenario, { every: 60, initialGold: 0 });
  assert.equal(r.fullLevelSeconds, 60); assert.ok(r.events.every(e => e.time % 60 === 0));
  assert.equal(r.productionMode, 'online');
});
test('both strategies run deterministically without mutating configuration', async () => {
  const { simulateShop } = await import('../model/simulate.js');
  const before = JSON.stringify({ G0, SHOPS, SCENARIOS });
  for (const strategy of ['roi', 'routine']) {
    const opts = { strategy, maxSeconds: 3600 };
    const a = simulateShop(SHOPS[0], G0, SCENARIOS[1], opts);
    assert.deepEqual(a, simulateShop(SHOPS[0], G0, SCENARIOS[1], opts));
    assert.ok(a.events.length > 0);
  }
  assert.equal(JSON.stringify({ G0, SHOPS, SCENARIOS }), before);
});
test('unsupported strategies, infinite horizons and negative purchase intervals are rejected', async () => {
  const { simulateShop } = await import('../model/simulate.js');
  for (const opts of [{ strategy: 'magic' }, { every: -1 }, { maxSeconds: Infinity }])
    assert.throws(() => simulateShop(shop, G0, scenario, opts));
});
test('reachable tasks keep accumulating sales when no purchase has positive ROI', async () => {
  const { simulateShop } = await import('../model/simulate.js');
  const r = simulateShop({ ...SHOPS[0], dishes: 1, cap: 3, volMax: 0 },
    { ...G0, pg: 1, starMult: 1 }, SCENARIOS[1], { tasks: [{ dish: 0, target: 1 }] });
  assert.ok(Math.abs(r.taskCompletionSeconds - 1 / .19) < 1e-9);
  assert.equal(r.fullLevelSeconds, null);
  assert.equal(r.stopReason, 'tasks_complete_without_full_level');
});
test('overflow-producing finite inputs are rejected before a result can contain Infinity', async () => {
  const { simulateShop } = await import('../model/simulate.js');
  assert.throws(() => simulateShop(SHOPS[0], { ...G0, pg: 1e308 }, SCENARIOS[1]), /numeric range/);
  assert.throws(() => simulateShop(SHOPS[0], G0, { ...SCENARIOS[1], newVisits: 1e308, charm: 1e308 }), /numeric range/);
});
test('offline estimate is one tenth of frozen online revenue and uses an explicit cap', async () => {
  const { estimateOfflineIncome } = await import('../model/simulate.js');
  assert.equal(estimateOfflineIncome(10, 100, 60), 60);
  assert.equal(estimateOfflineIncome(10, 100, 0), 0);
  assert.throws(() => estimateOfflineIncome(10, 100));
});
