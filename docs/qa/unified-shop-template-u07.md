# U07：制作模板与门禁验收

日期：2026-11-13。基线 `a919374`；沿用 `D:/Tes/eatventure` 当前分支，未自动提交推送。原计划U07全部完成，不增加任务组。必需行为、窗口与导出验收通过；旧经济门槛的两次超时单独记录如下。

## 制作与运行边界

- 店铺/员工入场表与能力清单已更新。新店声明公共模板，不再按旧single/handoff/serve矩阵限制能力组合；显式配方无需重复填写旧SpecDish.steps。报价目录、购买阶段、能力与端口仍严格校验。
- `content/examples/onboarding/table.tres`、`self_pickup.tres` 是数据配置示例，共用现有模块灰盒。两者真实完成盖饭两支合流与例汤，分别送桌和顾客整单自取；未加私有执行器，也未加入正式关卡。
- 新增全局松鼠员工112/1/2，直接引用已有注册视觉，与仓鼠在两组合复用。制作校验拒绝店内复制员工资源，不能借相同ID隐藏局部基础属性。灰盒保留占位视觉，不能称为已制作完成的新店美术。
- `tools/check_template_boundary.py` 拦截旧执行器、遗漏公共调用、界面改账本、私有/内嵌脚本和漏配模板。共享schema/component使用明确白名单；变异测试验证名称伪装也不能放行。该门禁不是完整GDScript分析器，需同时运行真实调用证明。
- 真实ShopSession/ShopPlay推进六份配置，轨迹来自实际公共库存与动作提交，记录员工真实位置/端口。诊断有20000条上限、报告overflow，不含回调、不影响业务、不进存档；失败候选和幂等操作不生成新成功记录。
- 普通启动/保存缺runtime_template时拒绝，并保护旧档字节。实测召回再部署发现活动员工顺序可能不同于名册，现从唯一runner.actors恢复；异常嵌套数据原子拒绝，磁盘/现场续档及独立续跑通过专项。

## 统一验收入口

`tests/shop_acceptance.json` / `tools/check_shops.py`：headless覆盖规则、正式/历史场景、旧档、布局、界面及模板门禁；window使用真实OpenGL；web比较正式与示例源/导出场景节点；economy保留原节奏/完店门槛并单独报告。

CI继续使用有效的github.workspace隔离目录，运行headless+web；main推送另跑Xvfb窗口。旧经济步骤单独记录失败并上传报告，不阻断行为作业。Pages仍走同一headless+web清单，不宣称云端耗时或旧经济已通过。本轮只在本地Godot4.6.3执行，未运行远端Godot4.7 CI或浏览器WebGL。

全部Godot进程使用隔离APPDATA/XDG_DATA_HOME，生命周期路径含session-lifecycle-userdata，未读写真实玩家进度。截图使用高金币/全解锁/两员工，是动作/状态验收，不能替代开局体验、自然经济或最终时长。

## 已核查结果

日志和报告位于 `_work/unified_shop_template_20261112/`，以frozen及final记录为准：

| 项目 | 结果 | 证据 |
|---|---|---|
| 完整原生规则与全部headless作业 | 1,010项规则、38项作业，0失败 | u07-headless-frozen/summary.json、rules.log |
| 实际窗口六份配置 | 33,228项，0失败；六张720×1280截图逐张检查 | u07-window-frozen/summary.json、runtime-proof/ |
| Web包公共核心 | 490项，0失败 | u07-packed-core.log |
| Web包实际六份配置 | 33,221项，0失败 | u07-packed-runtime-final.log |
| Web包正式会话、完整展示 | 3,960项、23,806项，0失败 | u07-packed-official.log、u07-packed-displays.log |
| Web导出及源/包内节点 | 17,972,284字节；1,156个节点一致，含公共模块示例 | u07-web-frozen/summary.json |
| 旧节奏检查 | 原120秒限制超时 | u07-economy-frozen/shared_rhythm.log |
| 旧完店检查 | 原240秒限制超时 | u07-economy-frozen/shop_progression.log |
| 源码与保护文件 | 最终各报告source_drift为空、对应同一源码；41/41保护hash未变 | verify_u07_evidence.py、u07-commit-ready.json |

包内轨迹的第一次本地调用错误地传入了绝对报告路径，被测试本身的隔离路径检查拒绝；纠正调用入口后重跑通过，游戏源码未修改。初次结果及重跑均保留在u07-packed-summary.json和u07-packed-final-summary.json，不覆盖失败记录。

verify_u07_evidence.py核对最终原生/窗口/Web/包内报告与当前源码、实际公共调用及物理端口、6张截图尺寸/hash、保护文件、三家正式资源和经济基线未改，并记录全部自有改动hash。最终清单为u07-commit-ready.json；历史U05/U06及本轮中间失败/取消的记录均保留，不作为当前通过证据。

奶茶原冻结文件保留，历史参考轨迹继续由原测试校验；实际正式奶茶另检查真实接单、生产、拿取时点、堂食/外带、公共库存、显示和恢复。不能将新架构的销量或新测试数量当作与历史完整经营轨迹逐帧相同的证明。U07未改三家店任何生产资源、员工基础值、价格、速度、客流或目标。

| 设计验收项 | 可执行证据 |
|---|---|
| 公共预留/拿取/放下/加工/取消 | test_template_inventory、bundles、trace；真实六配置operations与物理端口proofs |
| 角色基础值、尺寸与实际速度 | test_shared_staff、authoring变异测试；实际窗口每帧位移/属性和全局高度/密度检查 |
| 线性/合流/共享批量源/前台出品/追加物品 | formal_tea、formal_pancake、stirfry_service及新onboarding两组合的实际事务 |
| 顾客/整单结算/一次性交付 | template_service及save/edges、official_events；实际普通会话及包内续档 |
| 库存UI/手持/显式展示 | scene_frame、template_displays；三店与示例截图，第三店装盘台不自动摆库存 |
| 无路/权限/空间/暂停/倍速 | 运动/动作/岗位专项、六配置真实位置检查及1/2/4倍速 |
| 三类旧档、迁移与恢复 | template_legacy_adoption保留U06的91份旧快照，session_state及磁盘会话继续回归 |
| 架构无绕过 | 6项静态变异测试、制作CLI、实际公共事务轨迹；导入检查不能代替真实调用 |
| 新店与新员工只配置接入 | 全局squirrel和两份无业务脚本示例、召回再部署、普通保存与独立续跑 |
| 奶茶蓝本保护 | test_tea_modularity_baseline与5份冻结文件hash；正式奶茶的实际生产/服务/显示专项另行验收 |

## 仍需单独验收的范围

两项旧经济检查均超时，未得到完整指标，不能判断原完店目标是否达标；保留原check参数和基线，没有为过关调数值。局内行为架构验收与未来经济/最终时长标定分开报告。新场景仍需按入场表完成资源、端口与组合验收；公共模板支持扩展不代表任意未来配置已验证。
