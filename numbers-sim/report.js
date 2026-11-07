import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { G0, CANDIDATE_B, SHOPS, SCENARIOS, LIMITATIONS } from './model/config.js';
import { simulateShop } from './model/simulate.js';
const require = createRequire(import.meta.url);
const legacy = require('./legacy/economy_model.cjs');

export function buildReport({ taskSpecs = {} } = {}) {
  const baseline = [], runs = [];
  for (const [preset, patch] of [['original', {}], ['candidateB', CANDIDATE_B]]) {
    const g = { ...G0, ...patch };
    SHOPS.forEach((shop, i) => {
      const result = legacy.simShop(shop, g, g.crossMult ** i, 0);
      baseline.push({ preset, shop: shop.id, fullLevelSeconds: result.done ? result.t : null,
        unlocks: result.unlocks, spendShares: result.spend, taskCompletionSeconds: null,
        coverage: 'legacy_star_demand_proxy' });
    });
    for (const scenario of SCENARIOS) for (const strategy of ['roi', 'routine']) {
      SHOPS.forEach((shop, i) => {
        const result = simulateShop(shop, g, scenario, { strategy, multiplier: g.crossMult ** i, tasks: taskSpecs[shop.id] ?? null });
        const { events, ...summary } = result;
        runs.push({ preset, shop: shop.id, shopName: shop.name, scenario: scenario.id,
          strategy, purchases: events.length, ...summary });
      });
    }
  }
  return { schemaVersion: 1, basisDate: '2026-10-25', task: 'PXJ-41',
    inputs: { globals: G0, candidateB: CANDIDATE_B, shops: SHOPS, scenarios: SCENARIOS, taskSpecs },
    limitations: [...LIMITATIONS], baseline, runs };
}

function time(seconds) { return seconds === null ? 'N/A' : (seconds / 60).toFixed(2); }
export function markdownReport(report) {
  const middle = report.runs.filter(r => r.scenario === 'middle');
  const lines = [
    '# PXJ-41 三店经济模型对齐与回归结果', '',
    '数据日期：2026-10-25。结论：旧基线已保留并复现；新模型可以做规则与假设比较，尚不能给出正式通关时长。', '',
    '## 旧基线回归（全部菜升满，分钟）', '',
    '| 配置 | 奶茶 | 煎饼 | 面包 |', '| --- | ---: | ---: | ---: |',
  ];
  for (const preset of ['original', 'candidateB'])
    lines.push(`| ${preset} | ${report.baseline.filter(r => r.preset === preset).map(r => time(r.fullLevelSeconds)).join(' | ')} |`);
  lines.push('', '这些数复现的是原模型，不代表已验证的游戏时长。legacy 下两个文件保留上传原文；新模型不修改它们。', '',
    '## 新模型：中回头率假设（全部菜升满，分钟）', '',
    '| 配置 | 购买策略 | 奶茶 | 煎饼 | 面包 |', '| --- | --- | ---: | ---: | ---: |');
  for (const preset of ['original', 'candidateB']) for (const strategy of ['roi', 'routine'])
    lines.push(`| ${preset} | ${strategy} | ${middle.filter(r => r.preset === preset && r.strategy === strategy).map(r => time(r.fullLevelSeconds)).join(' | ')} |`);
  lines.push('', '全部 36 组模拟（3 客流假设 × 2 配置 × 2 购买策略 × 3 家店）的原始输入和结果见 [results.json](../../numbers-sim/results.json)。时间上限为 48 小时；未完成项保留 null 和停止原因，不用截断时长冒充完成。', '',
    '## 新客流公式：明确属于实验假设', '',
    '- 拉新率 = newVisits × (1 + charm × perCharm) × (1 + capStep) 的魅力投入次数次方。',
    '- 忙碌程度 = max(0, 当前菜数 × postsPerDish / 员工数 − 1)。这只是兼岗负荷代理，并不等于实际派工。',
    '- 有效品质 = clamp(baseQuality − overloadPenalty × 忙碌程度, 0, 1)。',
    '- 回头流量 = returnAtQualityOne × 有效品质；总客流 = 拉新 + 回头。未模拟回访延迟或真实留存。',
    '- 新模型取消星级及新菜数直接加客流；升星仍只影响售价。增加魅力、改善品质才改变本轮客流近似。', '',
    '| 参数 | 本轮假设 |', '| --- | --- |',
    '| newVisits | 0.15 人/秒 |', '| returnAtQualityOne | 低/中/高：0.025 / 0.05 / 0.10 人/秒 |',
    '| baseQuality | 0.8 |', '| overloadPenalty | 0.1 |', '| postsPerDish | 1 |',
    '| charm / perCharm | 0 / 0.1 |', '',
    '上述系数均未经过 Godot 或真实玩家校准，不写回正式默认。d0、starArr、flowStep 只为旧模型追溯保留，不参与新模型客流。', '',
    '## 满级与通关分别报告', '',
    '- fullLevelSeconds：全部菜单解锁且全部菜升满的时刻。',
    '- taskCompletionSeconds：全部菜单解锁并满足所配置销量任务的时刻，可以早于或晚于满级。',
    Object.values(report.inputs.taskSpecs).some(spec => spec?.length)
      ? '- 假设任务已配置：对应店铺的任务完成时间见 results.json；其余店铺仍为 N/A。所有目标均属实验输入，不代表正式任务已定稿。'
      : '- 正式三店任务目标尚未提供，因此本报告全部任务通关时间为 N/A。输入假设任务后，可以验证任务路径，但必须继续标为假设。',
    '- 当前支持每菜累计销量任务；连续不缺货等任务需要实际库存/工序模拟，本轮不支持，不会默默判为完成。', '',
    '## 购买策略与边界', '',
    '- roi：新菜优先；其余比较即时收入增量的回本时间，可组合机器/员工/魅力投入。这是贪心策略，不是最短通关解。',
    '- routine：新菜优先，之后固定循环菜价/机器/员工/魅力，各类取当前最便宜项，不识别瓶颈。仅是对照习惯，不能等同于所有普通玩家。',
    '- 定时购买仍按全程在线产能累计。离线仅提供冻结在线收入 × 时长上限 × 1/10 的单独估算函数，不伪装成完整离线模拟。', '',
    '## 仍未覆盖', '', ...report.limitations.map(s => `- ${s}`), '',
    '## 对下一步的影响', '',
    '可支持 PXJ-42 用统一经济参数试做、对比原默认与候选 B、采集菜单/任务/资金数据。不能据此声称已证明共享封杯台、珍珠并联、断货或人机协作的实际收益。', '',
    '奶茶店正式实现前还须由 PXJ-32 明确生产线开放方式，并填写最小配方、用人类型、解锁与任务目标。PXJ-35 保持进行中；现有面包店和正式经济默认值未改。', '',
    '复现：在 numbers-sim 内运行 `node --test tests/*.test.js`、`node report.js`。', '',
  );
  return lines.join('\n');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const report = buildReport();
  writeFileSync(new URL('./results.json', import.meta.url), JSON.stringify(report, (_, v) => typeof v === 'number' ? Number(v.toPrecision(12)) : v, 2) + '\n');
  writeFileSync(new URL('../docs/numbers/PXJ-41-results.md', import.meta.url), markdownReport(report));
  console.log(`Wrote ${report.baseline.length} legacy baselines and ${report.runs.length} scenario comparisons.`);
  console.log(report.runs.filter(r => r.scenario === 'middle').map(r => `${r.preset}/${r.strategy}/${r.shop}: full=${time(r.fullLevelSeconds)} min; tasks=${time(r.taskCompletionSeconds)}; ${r.stopReason}`).join('\n'));
}
