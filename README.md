# eatvenLike · 小店经营

竖屏小店经营游戏，Godot 4.7。主场景 `presentation/shop/shop_play.tscn`，按跨店记录（`game/app/profile.gd`）和关卡表（`content/campaign/campaign.tres`）进店：北方城先是煎饼果子摊，结店后去奶茶店。

所有店跑同一套规则代码和同一套界面代码，店与店之间只有数据和美术不同（规格：Notion《通用店铺规则规格｜定稿 v1.0》）：

- **规则层** `game/rules/`：`ShopRules` 管机器、菜谱工序、订单履约、员工调度、经济、阶段任务、加成栈、事件总线、奇遇；`ShopView` 给界面出快照（目标、机器面板、瓶颈提示）；`ShopSave` 每家店一个存档文件。代码里不出现任何店铺、机器、菜品的名字（`tests/test_shop_rules.gd` 的干净检查会扫）。
- **店铺数据** `content/shops/<店>/shop.tres`：机器和工序积木类型、菜谱、履约规则、调度打分、全部数值、阶段、任务、员工、文案、引导步骤。在 Godot 里直接编辑；数据格式定义在 `content/rules/`。
- **表现层** `presentation/shop/`：通用店铺场景、插槽式 HUD（`hud/default_hud.gd` 注册页签、面板页、小部件）、引导播放器、调参面板。每家店只提供一个美术场景（`presentation/shops/<店>/`），场景里放美术和按名字约定的锚点（`Anchors/Stations/<机器>`、`Queue`、`Seats`……）。

**加一家店**：写一份 `shop.tres`、做一个带锚点的美术场景、在关卡表里加一行，不改代码。`tests/fixtures/noodle/` 是一家只用数据写成的测试面馆（不上线），`tests/test_noodle_shop.gd` 证明它从开张一路开到完店。挪了美术、改了走位以后跑 `tools/sync_shop_layouts.gd` 把锚点写回店铺数据。

`tests/baselines/` 里存着每家店的机器人操作序列和整店结果，`replay_rules.gd` 在规则层上重放对照（±5%）。奶茶店仍用 main `73b0ae3` 旧模拟录下的基准和界面数据；煎饼摊改过数值，基准 `pancake_rules.json` 由 `record_rules.gd` 在通用规则上重录。改了某家店的数值，就用 `godot --headless --path . -s tests/baselines/record_rules.gd` 重录它的基准。

## 运行和验证

```sh
# 首次打开或添加全局脚本后导入资源
godot --headless --path . --import
# 规则、数据、存档、美术与字体回归
godot --headless --path . -s tests/run_all.gd
# 界面点按回归（奶茶店、煎饼摊、引导、HUD 扩展）
godot --headless --path . -s tests/render_shop_tea.gd
# 启动游戏
godot --path .
```

兔子帧完整性、界面和实际渲染检查见 [验证说明](docs/qa/README.md)。清理前版本的流程排查和问题证据见 [2026-11-01 报告](docs/qa/2026-11-01-playthrough/report.md)，当前主线行为以现有实现和回归结果为准。

## 目录

| 路径 | 用途 |
| --- | --- |
| `game/rules/` | 通用规则层：ShopRules、ShopView、ShopSave、加成栈、事件总线、寻路 |
| `game/app/` | 跨店记录（Profile）、原子文件写入与数值序列化 |
| `content/rules/` | 店铺数据格式（Spec* 资源定义） |
| `content/shops/`、`content/campaign/` | 每家店的数据、关卡表 |
| `presentation/shop/` | 通用店铺场景、HUD、引导、调参面板、员工拖放 |
| `presentation/shops/<店>/` | 每家店的美术场景和锚点 |
| `presentation/reference/shop_art.tscn` | 奶茶店的可编辑分层美术（被 `presentation/shops/tea/tea_art.tscn` 引用） |
| `presentation/characters/`、`presentation/*_walk_frames/` | 角色库、角色预览和帧动画 |
| `art/` | 正在使用的美术、动画、图标和字体 |
| `tests/` | 规则、数据、存档、界面点按和渲染回归；`tests/baselines/` 旧模拟基准；`tests/fixtures/noodle/` 测试面馆 |
| `tools/` | 走位同步、字体裁剪和 Web 导出后处理 |
| `docs/` | 美术需求、验证记录与清理说明 |

2026-11-01 已将面包店/灰盒旧版、未接入的骨骼动画试验、PSD、生图源文件和历史验证产物归档到仓库外；详见 [清理与恢复说明](docs/cleanup-2026-11-01.md)。旧版入口已移除。

Web 构建和主线自动发布说明见 [Web 部署](docs/web-deployment.md)。
