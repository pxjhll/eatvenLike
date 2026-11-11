import test from 'node:test';
import assert from 'node:assert/strict';
test('comparison preserves six legacy results and labels all 36 new scenario runs', async () => {
  const { buildReport } = await import('../report.js');
  const r = buildReport();
  assert.equal(r.baseline.length, 6); assert.equal(r.runs.length, 36);
  for (const row of r.runs) {
    assert.equal(row.taskCompletionSeconds, null); assert.equal(row.tasks, null);
    assert.equal(row.coverage, 'aggregate_capacity_not_physical_production');
    assert.ok(Number.isFinite(row.elapsedSeconds));
    assert.ok(row.elapsedSeconds <= 172800);
  }
  assert.ok(r.limitations.length >= 4);
});
test('comparison accepts an explicit hypothetical task set without changing defaults', async () => {
  const { buildReport } = await import('../report.js');
  const r = buildReport({ taskSpecs: { tea: [{ dish: 0, target: 1 }, { dish: 1, target: 1 }] } });
  assert.ok(r.runs.filter(x => x.shop === 'tea').every(x => x.tasks !== null));
  assert.ok(r.runs.filter(x => x.shop !== 'tea').every(x => x.tasks === null));
});
test('a report with configured tasks does not falsely say every task time is N/A', async () => {
  const { buildReport, markdownReport } = await import('../report.js');
  const r = buildReport({ taskSpecs: { tea: [{ dish: 0, target: 1 }] } });
  const md = markdownReport(r);
  assert.ok(!md.includes('本报告全部任务通关时间为 N/A'));
  assert.ok(md.includes('假设任务已配置'));
});
