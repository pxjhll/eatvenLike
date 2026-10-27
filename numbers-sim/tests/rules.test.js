import test from 'node:test';
import assert from 'node:assert/strict';

const state = () => ({ dishes: [{ p: 10, L: 1, w: 1 }], C: 1, staff: 1, train: 1, kM: 0, kS: 0, kL: 0 });
const g = { pg: 1.08, cg: 1.2, starEvery: 10, starMult: 2, perStaff: 1, capStep: .2, rM: 1.5, rS: 1.5, rL: 1.5, volGrow: .2 };
const scenario = { newVisits: .15, returnAtQualityOne: .05, baseQuality: .8, overloadPenalty: .1, postsPerDish: 1, charm: 0, perCharm: .1 };

test('price crosses the star boundary at level 10 with no off-by-one', async () => {
  const { dishPrice } = await import('../model/rules.js');
  assert.equal(dishPrice({ p: 10, L: 1 }, g), 10);
  assert.ok(Math.abs(dishPrice({ p: 10, L: 10 }, g) - 10 * 1.08 ** 9 * 2) < 1e-9);
});
test('capacity prices follow average dish upgrade costs and their own ladder', async () => {
  const { capacityCost } = await import('../model/rules.js');
  const s = state(); s.dishes.push({ p: 20, L: 1, w: 0 }); s.kM = 2;
  assert.ok(Math.abs(capacityCost(s, g, 'machine') - 1.5 * 60 * 1.2 ** 2) < 1e-9);
});
test('demand separates attraction and quality returns, ignoring stars', async () => {
  const { demandDetails } = await import('../model/rules.js');
  const s = state(); const before = demandDetails(s, g, scenario);
  assert.equal(before.attraction, .15);
  assert.ok(Math.abs(before.returns - .04) < 1e-12);
  s.dishes[0].L = 20;
  assert.deepEqual(demandDetails(s, g, scenario), before);
});
test('charm changes attraction only, quality changes returns only', async () => {
  const { demandDetails, dishPrice } = await import('../model/rules.js');
  const s = state(); const a = demandDetails(s, g, scenario);
  const b = demandDetails(s, g, { ...scenario, charm: 2 });
  const c = demandDetails(s, g, { ...scenario, baseQuality: .4 });
  assert.ok(b.attraction > a.attraction); assert.equal(b.returns, a.returns);
  assert.equal(c.attraction, a.attraction); assert.ok(c.returns < a.returns);
  assert.equal(dishPrice(s.dishes[0], g), 10);
});
test('overload reduces return quality and hiring restores it', async () => {
  const { demandDetails } = await import('../model/rules.js');
  const s = state(); s.dishes.push({ p: 10, L: 1, w: 0 });
  const busy = demandDetails(s, g, scenario); s.staff = 2;
  const rested = demandDetails(s, g, scenario);
  assert.ok(Math.abs(busy.quality - .7) < 1e-12);
  assert.equal(rested.quality, .8); assert.ok(rested.total > busy.total);
});
test('invalid scenario coefficients are rejected instead of producing NaN', async () => {
  const { demandDetails } = await import('../model/rules.js');
  for (const patch of [{ newVisits: NaN }, { baseQuality: 2 }, { overloadPenalty: -1 }, { postsPerDish: Infinity }])
    assert.throws(() => demandDetails(state(), g, { ...scenario, ...patch }));
});
