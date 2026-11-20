import test from 'node:test';
import assert from 'node:assert/strict';

test('missing task definitions report N/A rather than automatic completion', async () => {
  const { evaluateTasks } = await import('../model/completion.js');
  assert.equal(evaluateTasks(null, [100], true, 1), null);
  assert.equal(evaluateTasks([], [100], true, 1), null);
});
test('menu completion and all sales tasks are both required', async () => {
  const { evaluateTasks } = await import('../model/completion.js');
  const spec = [{ dish: 0, target: 5 }, { dish: 1, target: 3 }];
  assert.equal(evaluateTasks(spec, [5, 3], false, 2).done, false);
  assert.equal(evaluateTasks(spec, [5, 2], true, 2).done, false);
  assert.equal(evaluateTasks(spec, [5, 3], true, 2).done, true);
});
test('unknown tasks and impossible dish indices are validation errors', async () => {
  const { evaluateTasks } = await import('../model/completion.js');
  for (const spec of [[{ dish: 2, target: 1 }], [{ dish: 0, target: 0 }], [{ dish: 0, target: 1, type: 'perfect_line' }]])
    assert.throws(() => evaluateTasks(spec, [1], true, 1));
});
test('task target time is interpolated from actual per-dish sales rates', async () => {
  const { secondsToTasks } = await import('../model/completion.js');
  assert.equal(secondsToTasks([{ dish: 0, target: 30 }], [10], [.5], true), 40);
  assert.equal(secondsToTasks([{ dish: 0, target: 30 }], [10], [0], true), Infinity);
  assert.equal(secondsToTasks([{ dish: 0, target: 30 }], [30], [0], false), Infinity);
});
