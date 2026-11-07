// Economic baseline from the supplied model. These are not new official values.
export const G0 = Object.freeze({ pg: 1.08, cg: 1.20, starEvery: 10, starMult: 2, starArr: .25,
  crossMult: 1.4, rM: 1.5, rS: 1.5, rL: 1.5, newDishFactor: 1, newShare: .45,
  flowStep: 1.25, capStep: .2, perStaff: .2, p0: 10, unlockAt: 10, volGrow: .2 });
export const CANDIDATE_B = Object.freeze({ rM: 1.2, rS: 1, rL: 1.2, crossMult: 1.3 });
export const SHOPS = Object.freeze([
  { id: 'tea', name: '奶茶店', type: '小店', dishes: 2, cap: 20, staff0: 1, staffMax: 3, volMax: 8, c0: .25, d0: .2 },
  { id: 'pancake', name: '煎饼果子店', type: '小店', dishes: 2, cap: 35, staff0: 2, staffMax: 5, volMax: 12, c0: .25, d0: .2 },
  { id: 'bakery', name: '面包店', type: '中店', dishes: 6, cap: 70, staff0: 2, staffMax: 8, volMax: 14, c0: .25, d0: .2 },
].map(Object.freeze));

// Experimental linear flow assumptions, not calibrated game formulas.
export const SCENARIOS = Object.freeze([
  ['low', '低回头率假设', .025], ['middle', '中回头率假设', .05], ['high', '高回头率假设', .1],
].map(([id, label, returnAtQualityOne]) => Object.freeze({
  id, label, newVisits: .15, returnAtQualityOne, baseQuality: .8,
  overloadPenalty: .1, postsPerDish: 1, charm: 0, perCharm: .1,
})));
export const LIMITATIONS = Object.freeze([
  '实验线性客流换算，系数与兼岗规则未校准；不代表正式公式。',
  '总产能/总人力近似，未模拟自动、人工、人机配合的工序阶段。',
  '未模拟配方、共用设备争抢、物流、库存、断料及顾客耐心。',
  '销量为连续流量估算；正式任务目标未配置时通关时间为 N/A。',
  '定时购买期间仍按在线生产；不是实际离线收益。',
]);
