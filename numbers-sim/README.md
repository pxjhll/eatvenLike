# 三店经济实验（PXJ-41）

本目录是独立策划工具。正式游戏参数不变；Notion 02、单店节奏页、03 第 5 节为规则来源。模型只能比较显式假设，不代替 Godot 实测。

## 运行

Node.js 22 或更新版本，无依赖：

```sh
cd numbers-sim
node --test tests/*.test.js
node report.js
node build-tuner.js --check
```

直接用浏览器打开 `economy-tuner.html` 即可运行，不需要服务器、账号、字体或 CDN。改动 `model/`、`ui.js`、模板后运行 `node build-tuner.js` 更新自包含 HTML。

报告：`../docs/numbers/PXJ-41-results.md`；可复现输入与全部 36 个场景结果：`results.json`。

## 文件职责

| 文件 | 职责 |
| --- | --- |
| `legacy/economy_model.cjs`、`legacy/economy-tuner.html` | 原上传内容，字节保留；含星级客流代理，只作基线 |
| `model/config.js` | 原经济参数、候选 B、三店配置、显式假设与限制 |
| `model/rules.js` | 售价、统一价格尺子、拉新/品质回头近似 |
| `model/completion.js` | 菜单＋销量任务；未配置返回 null |
| `model/decisions.js` | 纯函数购买评分与固定循环策略，不改真实状态 |
| `model/simulate.js` | 连续流量、购买事件、销量、升满/任务两种时间 |
| `report.js` | 六组旧基线、36 组新场景对照及报告 |
| `ui.js`、`tuner.template.html` | 调节器交互与版式 |
| `build-tuner.js` | 生成并检查自包含入口 |

## 任务输入

```js
import { G0, SHOPS, SCENARIOS } from './model/config.js';
import { simulateShop } from './model/simulate.js';

// 仅示范任务 API，30 不是正式目标。
const result = simulateShop(SHOPS[0], G0, SCENARIOS[1], {
  multiplier: 1,
  tasks: [{ dish: 0, target: 30 }, { dish: 1, target: 30 }],
  strategy: 'roi', // 或 routine
  every: 0,      // 秒；60/300/900 为在线定时购买
});
```

不传 tasks 时 `taskCompletionSeconds` 为 null。输入任务后仍继续记录升满时间，二者可以前后独立发生。销量使用连续流量，因此任务时间也是结构估算，不是逐件出餐仿真。

只支持已知菜索引的正整数销量任务；连续不缺货等目标需库存/工序模拟，本轮拒绝不支持的任务类型，不能假装已验收。

## 客流的实验假设

拉新 = newVisits × (1 + charm × perCharm) × (1 + capStep)^魅力投入次数。

品质 = clamp(baseQuality − overloadPenalty × max(0, 菜数 × postsPerDish / 员工数 − 1), 0, 1)。

回头 = returnAtQualityOne × 品质；客流 = 拉新 + 回头。这里不模拟真实顾客留存、回访延迟或详细派工。低/中/高回头率系数与兼岗惩罚都是未校准假设，不写回正式默认。

`d0`、`starArr`、`flowStep` 仅为原模型追溯保留，新模型不按升星/新菜直接提升客流。

## 当前结论边界

没有配方、共享工序、运输、库存、断料和阶段用人。因此不能用本工具证明“珍珠锅并联有效”或“共用封杯台成为瓶颈”。这些交给 PXJ-42 的实际产线验证。

`estimateOfflineIncome(在线每秒收入, 离开秒数, 上限秒数)` 只按冻结收入 × 1/10 估算，必须显式提供上限，不代表已完成离线系统。
