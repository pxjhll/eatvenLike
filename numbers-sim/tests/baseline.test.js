import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
const require = createRequire(import.meta.url);
const { simShop, G0, SHOPS0 } = require('../legacy/economy_model.cjs');

test('uploaded baseline and candidate retain all six reference times', () => {
  for (const [patch, expected] of [
    [{}, [20.87904659359576, 23.3033794218961, 35.75150047068257]],
    [{ rM: 1.2, rS: 1, rL: 1.2, crossMult: 1.3 }, [16.64779092866495, 21.307903645155086, 33.31109694580064]],
  ]) {
    const g = { ...G0, ...patch };
    SHOPS0.forEach((shop, i) => {
      const r = simShop(shop, g, g.crossMult ** i, 0);
      assert.equal(r.done, true);
      assert.ok(Math.abs(r.t / 60 - expected[i]) < 1e-8);
    });
  }
});

test('legacy HTML and standalone baseline use the same simulation', () => {
  const js = readFileSync(new URL('../legacy/economy_model.cjs', import.meta.url), 'utf8');
  const html = readFileSync(new URL('../legacy/economy-tuner.html', import.meta.url), 'utf8');
  assert.equal(html.slice(html.indexOf('function simShop'), html.indexOf('const G0')).trim(), js.slice(0, js.indexOf('const G0')).trim());
});
