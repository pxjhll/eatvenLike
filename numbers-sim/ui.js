import { G0, CANDIDATE_B, SHOPS, SCENARIOS, LIMITATIONS } from './model/config.js';
import { simulateShop } from './model/simulate.js';

const $ = id => document.getElementById(id);
const fields = [
  ['pg', '售价每级倍率', 1.02, 1.15, .01], ['cg', '升级费每级倍率', 1.05, 1.4, .01],
  ['starEvery', '每几级升星', 5, 25, 1], ['starMult', '每星售价倍率', 1.2, 3, .1],
  ['rM', '机器价格比例', .1, 5, .1], ['rS', '员工价格比例', .1, 5, .1],
  ['rL', '魅力投入价格比例', .1, 5, .1], ['crossMult', '跨店收入倍率', 1, 2.5, .05],
];
const assumptions = [
  ['newVisits', '基础拉新率（人/秒）', 0, 10, .01],
  ['returnAtQualityOne', '满品质回头流量（人/秒）', 0, 10, .005],
  ['baseQuality', '基础品质（0–1）', 0, 1, .05],
  ['overloadPenalty', '兼岗品质惩罚系数', 0, 1, .05],
  ['postsPerDish', '每菜岗位负荷代理', 0, 10, .5],
  ['charm', '初始魅力', 0, 100, 1], ['perCharm', '每点魅力拉新系数', 0, 10, .05],
];
function numericField([key, label, min, max, step], prefix, parent) {
  const wrap = document.createElement('label'); wrap.textContent = label;
  const input = document.createElement('input');
  Object.assign(input, { id: prefix + key, type: 'number', min, max, step, required: true });
  wrap.append(input); parent.append(wrap);
}
fields.forEach(f => numericField(f, 'g-', $('globals')));
assumptions.forEach(f => numericField(f, 'a-', $('assumptions')));
SCENARIOS.forEach(s => { const o = document.createElement('option'); o.value = s.id; o.textContent = s.label; $('scenario').append(o); });
$('scenario').value = 'middle';
LIMITATIONS.forEach(text => { const li = document.createElement('li'); li.textContent = text; $('limits').append(li); });
function fillGlobals() {
  const g = { ...G0, ...($('preset').value === 'candidateB' ? CANDIDATE_B : {}) };
  fields.forEach(([key]) => { $('g-' + key).value = g[key]; });
}
function fillScenario() {
  const scenario = SCENARIOS.find(s => s.id === $('scenario').value);
  assumptions.forEach(([key]) => { $('a-' + key).value = scenario[key]; });
}
fillGlobals(); fillScenario();
let latest = null;
const minutes = seconds => seconds === null ? 'N/A' : (seconds / 60).toFixed(2) + ' 分';
function readInputs() {
  if (!$('controls').reportValidity()) return null;
  const g = { ...G0 };
  fields.forEach(([key]) => { g[key] = $('g-' + key).valueAsNumber; });
  const scenario = { label: '当前实验假设（未校准）' };
  assumptions.forEach(([key]) => { scenario[key] = $('a-' + key).valueAsNumber; });
  const target = $('target').value === '' ? null : $('target').valueAsNumber;
  if (target !== null && (!Number.isInteger(target) || target <= 0)) throw new RangeError('假设销量目标必须为正整数，或留空表示未配置。');
  return { g, scenario, every: Number($('every').value), target, shops: SHOPS };
}
function render() {
  $('error').textContent = '';
  try {
    const input = readInputs(); if (!input) return;
    const rows = [];
    for (const strategy of ['roi', 'routine']) SHOPS.forEach((shop, i) => {
      const tasks = input.target === null ? null : Array.from({ length: shop.dishes }, (_, dish) => ({ dish, target: input.target }));
      const r = simulateShop(shop, input.g, input.scenario, { strategy, every: input.every, multiplier: input.g.crossMult ** i, tasks });
      rows.push({ shop: shop.name, strategy, ...r });
    });
    const tbody = $('rows'); tbody.replaceChildren();
    for (const r of rows) {
      const tr = document.createElement('tr');
      const share = ['price', 'machine', 'staff', 'lure'].map(k => (r.spendShares[k] * 100).toFixed(0) + '%').join(' / ');
      const cells = [r.shop, r.strategy === 'roi' ? '即时回本' : '固定循环', minutes(r.fullLevelSeconds),
        minutes(r.taskCompletionSeconds), r.unlocks.map(minutes).join(' / ') || '—',
        (r.gapMaxSeconds / 60).toFixed(2) + ' 分', share, r.stopReason];
      for (const text of cells) { const td = document.createElement('td'); td.textContent = text; tr.append(td); }
      tbody.append(tr);
    }
    $('task-note').textContent = input.target === null
      ? '任务目标未配置：通关时间全部为 N/A。满级时间只是结构指标。'
      : '当前使用“每菜售出 ' + input.target + ' 份”的假设任务，不是正式任务规格。';
    latest = { inputs: input, coverage: 'aggregate_capacity_not_physical_production', limitations: LIMITATIONS, rows };
    $('export').disabled = false;
  } catch (error) {
    $('rows').replaceChildren(); latest = null; $('export').disabled = true;
    $('error').textContent = error.message;
  }
}
$('controls').addEventListener('submit', e => { e.preventDefault(); render(); });
$('controls').addEventListener('input', () => {
  latest = null; $('export').disabled = true;
  $('task-note').textContent = '输入已改变，请运行对照；表中暂为上次运行结果。';
});
$('preset').addEventListener('change', () => { fillGlobals(); render(); });
$('scenario').addEventListener('change', () => { fillScenario(); render(); });
$('export').addEventListener('click', () => {
  if (!latest) return;
  const url = URL.createObjectURL(new Blob([JSON.stringify(latest, null, 2)], { type: 'application/json' }));
  const a = document.createElement('a'); a.href = url; a.download = 'economy-experiment.json'; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
render();
