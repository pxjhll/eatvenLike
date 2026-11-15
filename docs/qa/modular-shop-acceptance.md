# T11 / T12 制作模板与统一验收

日期：2026-11-11。工作分支 `codex/tea-baseline-shared-staff`，本阶段起点 `afa22d1`。

**PR #88 后续修复：** 本文末尾验收表是最初 T11/T12 的历史结果。无效 CI 和旧档锁店已修复；此前 T12 未做完店标定的缺口由 `shared-shop-progression.md` 补足，最新验证状态见 `pr88-remediation.md`。

## 新增店铺和员工的证明

`tests/fixtures/onboarding/shop.tres`、`art.tscn`、`campaign.tres` 是可直接加载的独立资源；无需生成器，也不加入正式campaign。使用已有模块、主菜与例汤工序、两处取餐口及serve/flow1整单交付。示例使用固定30秒客流，便于观察双员工完整流程，不复制旧原型的高压客流。它是制作灰盒，不是正式新菜单或美术关卡。

`content/characters/staff/hamster.tres` 把已有仓鼠动画配置为104/1/2员工，直接引用全局cat。公共角色控制器、行为逻辑和三店正式资源不变。仓鼠已有walk/idle/sit，没有独立work动画，操作时明确使用原idle回退。没有将回退姿势称为新动画，也没有生成新PNG。

三个规则测试检查持久化资源/完整空间、共享员工、真实制作与多物品交付、部分取餐后召回补偿、同岗位重新上岗、存档重开和精确续跑。真实界面测试检查头像、动画、模块世界输入、暂停与1/2/4倍速、实际合送及关闭重开。

制作入口表位于 `docs/templates/shop-intake.md` 与 `staff-intake.md`；第三店实际资源映射见 `docs/art/stirfry-module-map.md`。按原画区域→唯一资产→模块/工位→配方与策略→空间端口→运行验收逐项对应。全新美术仍需完成既有FigCraft确认流程。

## 单一验收清单

`tests/shop_acceptance.json` 列出本地和CI共用的33项headless入口及1项web入口。包含完整规则、五店配置、三店空间、旧经济基线、原店界面、共享运动/动作/合流/模块/尺度、迁移、生命周期、重试、命令、表现边界、音频、动画、新示例、共享节奏和空店完店检查。

`tools/check_shops.py` 使用Python3.10+标准库，按清单执行，逐项设置独立APPDATA/XDG_DATA_HOME（生命周期目录标记始终存在）。每项具有超时、日志和必须出现的完成标记。非零退出、引擎错误、失败计数、缺失完成标记或超时均失败；Windows超时终止该子进程树，Linux终止该独立进程组。运行前后检查源哈希，期间源代码/资源变化也不能报告通过。

```powershell
python tools/check_shops.py --engine $engine --profile headless --output _work/acceptance/headless
python tools/check_shops.py --engine $engine --profile web --output _work/acceptance/web
```

用`--list`查看入口，`--only session_lifecycle`等选择定位检查；筛选通过只代表所选项通过。输出只能位于工作区_work子目录，不写游戏源文件。默认生成唯一输出目录，包含逐项日志、退出码、耗时、命令和summary.json。

web档先记录源场景节点，导出真实PCK，按24MiB上限检查，并在包内加载场景核对节点身份。可传`--pack build/web/index.pck`检查已经导出的发布包，不重复导出。场景导出差异或无效包不能因导出进程返回0而通过。

CI、Pages构建调用同一清单；CI始终上传验收摘要，保留push时的真实窗口截图检查。Python运行器的六项契约测试使用真实子进程覆盖假通过、缺失完成标记、超时、环境隔离及非法路径/清单，不以mock代替进程结果。

## 节奏与兼容边界

当前共享协议基线见 `shared-shop-rhythm.md`。固定seed42、600秒、全开工位、真实双员工；记录销售间隔、首单、活动占比、流失、分钟轨迹、非法落脚、超速与保存恢复。旧协议原基线继续冻结，当前基线单独记录，不把新结果冒充旧行为等价。

初版T12只完成统一验收与可重复短测报告。用户随后明确要求恢复三店完店时长，现已调整单店数值并新增空店回放门槛，具体改动、种子和适用范围见 `shared-shop-progression.md`。全局员工基础属性不变；全新能力、全新角色造型的资源生产和任意运行中布局迁移仍需各自明确契约。

## 实际验收结果

本地Godot4.6.3、Python3.14；所有运行隔离用户数据。日志与源哈希在 `_work/shop_modularity/phase-g/`。

| 检查 | 结果 | 证据 |
|---|---|---|
| headless完整清单 | 32入口，0失败，运行期间源哈希无变化 | acceptance-headless/summary.json |
| 完整规则 | 487项，0失败 | acceptance-headless/rules.log |
| Python运行器契约 | 6项，通过 | acceptance-headless/runner_contract.log |
| 新店真实界面 | 25项，0失败 | acceptance-headless/shop_onboarding.log |
| 新店OpenGL窗口与截图 | 26项，0失败，无stderr | demo-window.log / onboarding.png |
| 既有生命周期/启动重试/命令/表现边界 | 全部0失败 | 对应清单日志 |
| 三店同视口尺度及全部既有动画/动作 | 全部通过 | actor_presentation等日志 |
| 配置/布局/旧经济 | 五店校验、三店布局、旧基线通过 | authoring / layout / legacy_economy日志 |
| 网页包与导出场景 | 15,721,580字节，节点逐字节相同，0失败 | acceptance-web/summary.json |
| 当前协议节奏 | 三店统计与独立基线一致、物理和恢复门槛通过 | acceptance-headless/shared_rhythm.log |

Pages构建脚本通过bash语法检查；修改后的远端Godot4.7 CI和实际Pages发布未在本轮触发。没有将本地4.6.3验证称为跨版本或线上发布成功。

最终核对：26项原有用户文件及5项奶茶冻结文件哈希保持一致；正式三店规则/资源、公共角色与业务控制器未改，PNG改动为0。导出生成的脚本UID属于配套元数据。git diff --check通过；完整源清单见verification.json。本轮未自动提交推送。
