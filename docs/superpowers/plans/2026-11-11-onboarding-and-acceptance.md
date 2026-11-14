# T11 / T12 制作模板与统一验收 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans sequentially in this chat. 不创建worktree、其他聊天或代理。用户已明确授权继续T11和T12。

**Goal:** 用持久化示例证明已有能力可通过配置接入新店和员工，并用同一入口执行本地/CI验收、网页包检查与可复跑节奏报告。

**Architecture:** 复用ShopTemplate、已有主菜/例汤配方、共享动作和既有仓鼠动画；演示只新增SpecShop/SpecStaffKind/场景/独立campaign资源。制作文档将原画区域对应唯一资产、模块、站点和端口。验收清单为JSON，Python标准库运行器负责隔离环境、超时、日志、非零退出及摘要；GDScript节奏采样只读真实规则，不修改正式数值。

**Tech Stack:** Godot4.6.3 / GDScript / TRES / TSCN / Python3 standard library / PowerShell / existing CI Godot4.7.

**Spec:** docs/superpowers/specs/2026-11-11-modular-shop-system.md；任务总表T11/T12。

## Global Constraints

- 当前HEAD afa22d1，分支codex/tea-baseline-shared-staff；原有26项用户文件保持原哈希。
- 沿用三店motion1/action1；正式flow0、菜谱/价格/奖励/员工属性不改。不通过提速或涨价追平旧经济。
- 原奶茶5份冻结文件及原三店legacy定义不改；不修改PNG，不制作新美术或未确认FigCraft稿。
- 每次引擎调用显式隔离APPDATA/XDG_DATA_HOME；生命周期路径含session-lifecycle-userdata。中间工具和证据在_work。
- 本轮完成实现与验收，未经新指令不自动提交或推送。

## Task 1 — T11 可直接加载的示例与制作模板

**Files:** content/characters/staff/hamster.tres；tests/fixtures/onboarding/{shop.tres,art.tscn,campaign.tres}；tests/test_shop_onboarding.gd；tests/render_shop_onboarding.gd；docs/templates/{shop-intake.md,staff-intake.md}；docs/art/stirfry-module-map.md；docs/shop-onboarding.md。

- [x] 测试先断言独立demo资源、新员工与共享定义不存在；创建只需读资源即可启动的fixture，不用运行生成器才能进入。
- [x] 使用既有仓鼠动画作为新增员工示例，基础档104/1/2；新店引用全局cat和hamster，不新增角色控制分支。明确这是已有动画资源的新员工配置，不是新制作美术。
- [x] 使用T08模块场景、原主菜/例汤、多取餐点组合保存新店和独立campaign；不加入正式campaign、不把demo菜单变成正式菜单。
- [x] 测试Schema/SceneContract/完整空间、共享员工引用、真实接单生产销售、订单合送、取消/保存恢复；真实界面检查动画/头像、世界输入、暂停倍速和重开。
- [x] 写原画入场表、唯一资产/镜像复用表、固定组合边界、模块/站点/配方/端口映射、员工属性/动作/头像/资源声明模板；用第三店实际资产填写样例。

## Task 2 — T12 节奏统计与当前协议基线

**Files:** tools/shop_rhythm.gd；tests/test_shop_rhythm.gd；tests/baselines/shared_shop_rhythm.json；docs/qa/shared-shop-rhythm.md。

- [x] RED：报告入口及校验缺失；定义seed42/600秒/全工位/实际双员工的相同场景条件，禁止把三员工场景标为双员工。
- [x] 采样销量、订单、收入、流失、首单/销售间隔、每分钟轨迹、员工走路/操作/等待/空闲、阻塞原因、越界/超速与保存恢复。
- [x] 参数严格校验；默认只打印，不写基线。显式--output只写指定证据，--check比较当前协议基线，失败非零；不重录原奶茶或旧经济基线。
- [x] 实测生成新协议基线；记录旧/新条件差异与第三店瓶颈，报告边界为固定条件统计，不宣称已经完成新玩家关卡平衡。

## Task 3 — T12 本地/CI单一验收入口

**Files:** tests/shop_acceptance.json；tools/check_shops.py；tests/test_check_shops.py；.github/workflows/tests.yml；tools/validate_shops.gd；tests/run_all.gd；docs/qa/modular-shop-acceptance.md。

- [x] RED：清单/运行器缺失、漏生命周期、零退出但引擎报错、超时、非法参数与输出路径覆盖源文件等失败情形。
- [x] 清单收录当前CI的全部规则、原店、模块、运动/动作、迁移、生命周期、启动重试、命令、表现边界与动画入口；新增onboarding和节奏检查。
- [x] Python标准库运行器支持--engine、--profile headless/web、--only、--output；每项隔离userdata，保留日志、耗时/退出码与summary.json；不跳过已列失败，不把报错或超时计为通过。
- [x] web档运行源场景节点、导出包、24MiB限制和包内节点对照；路径使用参数数组；失败保留证据。
- [x] CI通过同一个清单执行，上传验收摘要；保留真实窗口QA。配置校验加入demo独立campaign，不改正式campaign。
- [x] 完整运行本地headless、web、真实demo/同视口窗口；检查原26文件、原5冻结文件、无PNG改动与git diff --check。更新总表T11/T12及适用限制。
