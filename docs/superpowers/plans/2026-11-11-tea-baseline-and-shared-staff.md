# 奶茶基线与共享员工定义 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking. 当前按顺序执行，不启动子代理或新聊天。

**Goal:** 冻结奶茶店已认可行为，将其六种员工定义移入共享资源，证明行为和存档未改变，为后续跨店统一提供可信基线。

**Architecture:** 沿用SpecStaffKind和现有规则对象，不增加运行框架。六个共享Resource逐字段复制奶茶现有定义，奶茶仅改变资源引用；先保存确定性基线，再做资源提取，最后验证旧档加载、继续和重新保存。

**Tech Stack:** Godot 4.6.3本地 / GDScript / TRES / PowerShell；仓库现有CI配置使用Godot 4.7。

**Spec:** `docs/superpowers/specs/2026-11-11-modular-shop-system.md`。

## Global Constraints

- 工作目录D:/Tes/eatventure；任务基线记录为9bc1b20，执行时必须重新检查HEAD，不自动切回旧提交。
- 保留当前全部用户改动。只改本计划列出的文件；不在此阶段统一煎饼摊/第三店速度、尺寸、流水线或经济。
- 制作中间文件、日志、原图和存档样本在_work/shop_modularity/phase-a/，不提交源稿和真实玩家数据。
- 每次启动Godot显式设置隔离APPDATA，位于D:/Tes/eatventure/_work/shop_modularity/phase-a/session-lifecycle-userdata/<runner>。
- 仅已有六种奶茶员工进入本阶段共享资源；dog/sheep等扩展员工的全局能力档在后续接入任务登记，本阶段不回退、不删除、不更改它们。
- 不创建worktree、新聊天或子代理；不自动提交或推送。执行交付时报告精确文件范围和验证结果。
- 保存旧基线后不能为使新实现通过而重录基线。预期变化需要另立迁移任务并说明原因。

## 测试运行约定

```powershell
$env:APPDATA = 'D:/Tes/eatventure/_work/shop_modularity/phase-a/session-lifecycle-userdata/rules'
& 'D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe' --headless --path 'D:/Tes/eatventure' -s tests/run_all.gd
if ($LASTEXITCODE -ne 0) { throw 'Rule suite failed' }
```

将新的断言类登记到tests/run_all.gd。失败必须来自有意义的断言，不能把解析错误当红灯；使用现有error_counter捕获运行错误。每次失败保留原始日志；稳定通过后不重复运行不变的全套。

## T01：冻结奶茶规则、角色和表现基线

**Files**

- Create: `tests/baselines/capture_tea_modularity.gd`（确定性规则轨迹采集、只在显式参数下写基线）。
- Create: `tests/baselines/tea_modularity.json`（仅初始冻结写入）。
- Create: `tests/test_tea_modularity_baseline.gd`（基准属性、轨迹、基线非空断言）。
- Modify: `tests/run_all.gd`（注册断言类）。
- Create: `docs/qa/tea-modularity-baseline.md`（命令、来源提交、场景参数、证据位置）。
- Create: `tests/fixtures/tea_modularity/{unopened,active,continuations}.json`（改造前合成测试档与续跑摘要，供CI读取；不是玩家存档）。
- Evidence only: `_work/shop_modularity/phase-a/`中的窗口截图、旧档、资源与日志hash。
- 执行细化：可移植测试必须带上改造前合成档夹具；截图与完整日志仍只留_work。原界面测试没有截图参数，使用工作区采集器实例化相同正式场景与TestSession来记录尺寸，不扩展游戏UI。

**Interfaces**

- Consumes: `ShopRules.new(spec)`、`unlock(id)`、`unlock_box(id)`、`hire()`、`deploy_worker(id)`、`step(dt)`、`to_dict()`、`rules.events.on("*", listener)`，现有奶茶测试打开全工位的方法。
- Produces: `capture_tea_modularity.gd`的`static func capture() -> Dictionary`；返回`{sample_seconds:10, duration:600, snapshots:Array, events:Array, sold:int, walking_samples:int, content:Dictionary}`。
- 每个snapshot包含`clock`和`state_sha256`，从`var_to_bytes(rules.to_dict()).hex_encode().sha256_text()`取得；事件记录`clock`、`name`、`data_sha256`，后者从事件data的同样字节序列计算。基线只包含JSON无损支持的值，不把Vector2/Resource等写成字符串后拿来与原类型比较。采集代码不写玩家目录。

- [x] 写基线断言：先要求基线文件存在，再验证它与重新采集结果相同；加入sold>0、walking_samples>0，拒绝空转样本。

```gdscript
extends "res://tests/test_case.gd"
const Capture := preload("res://tests/baselines/capture_tea_modularity.gd")
func test_tea_trace_matches_frozen_baseline() -> void:
    var path := "res://tests/baselines/tea_modularity.json"
    if not FileAccess.file_exists(path):
        check(false, "Freeze the pre-refactor tea baseline before editing production")
        return
    var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
    var actual: Dictionary = Capture.capture()
    check(actual.sold > 0, "The trace includes sales")
    check(actual.walking_samples > 0, "The trace includes worker movement")
    check_eq(actual, expected, "Tea behavior stays identical")
```

- [x] 实现采集器。按现有`tests/test_tea_rules.gd::_opened()`的明确操作顺序打开lemonade、boil、seal、mix、press、topping以及tea_leaf/milk箱；topping升级3次，招募2人，派遣名册中未部署员工，开始前预算20000。保留原resource的random_seed。
- [x] 固定步进600秒，每10秒采一次完整状态hash；监听全部非tick业务事件。动作时间、RNG、预留、岗位与库存进入to_dict的完整hash，不人为挑选“看起来没变”的字段。
- [x] 运行红灯，确认仅因基线文件缺失失败；此时不得修改生产代码或店铺资源。
- [x] 以当前原实现运行采集器并写一次基线。入口支持`--write-baseline`与`--check`，默认只检查；写前存在文件则拒绝覆盖。用相同输入重跑，确认确定性一致和非空行为。
- [x] 加入字面基准测试：六种员工walk/work/carry符合已确认表；原场景metadata读取结果为员工128、顾客110、速度170；从当前适配规则记录720x1280与1280x720下奶茶截图和角色屏幕包围盒。截图通过现有真实界面测试入口产生，不写真实APPDATA。
- [x] 改造前记录奶茶内容指纹、资源和测试脚本hash；保存一份未开店档、一份营业中有订单/搬运的档，以及按原实现继续60秒的状态/事件摘要。副本必须来自隔离会话。
- [x] 运行现有规则测试及`tests/render_shop_tea.gd`，记录退出码和运行错误。把环境与证据位置写入qa说明，随后封存旧基线。

**验收出口：** 可以用一条检查命令证明旧奶茶运行轨迹一致；既有销售、移动、业务事件和两种窗口尺寸证据，不接受只冻结参数表。

## T02：提取六种共享SpecStaffKind资源，仅迁移奶茶引用

**Files**

- Create: `content/characters/staff/cat.tres`、`raccoon.tres`、`fox.tres`、`rabbit.tres`、`gray_cat.tres`、`bear.tres`。
- Modify: `content/shops/tea/shop.tres`（六个sub_resource替换为ext_resource引用）。
- Modify: `content/rules/spec_shop.gd`与`tests/test_content_rules.gd`（执行中确认必须提供外部定义的可编辑深复制边界，见下文契约）。
- Create: `tests/test_shared_staff.gd`；Modify: `tests/run_all.gd`。
- Create: `docs/shared-staff-definitions.md`（共享来源、允许变化与后续迁移范围）。

**Interfaces**

- Consumes: 现有`content/rules/spec_staff_kind.gd`，保留`id/display_name/stats/role/description`全部字段语义。
- Produces: 每个`res://content/characters/staff/<id>.tres`加载为SpecStaffKind，奶茶staff.kinds按原顺序引用这些资源。
- 不添加新Resource类型或导出字段，不改变内容指纹算法；现有`_new_worker`复制stats的行为继续沿用。
- 执行发现并纳入T02的复制契约：Godot的`duplicate(true)`保留外部员工Resource。新增`SpecShop.copy_for_editing() -> Resource`，调用`duplicate_deep(Resource.DEEP_DUPLICATE_ALL)`；迁移`tests/test_content_rules.gd`与`tests/test_content_save.gd`中编辑店铺变体的复制入口。运行时员工复制仍用既有WorkerState。共享定义隔离测试先失败再通过，不弱化旧存档测试。
- 本地4.6.3中自类型返回的深复制方法导致依赖脚本退出时滞留，最小对照移除方法后消失；返回原生Resource类型后真实界面退出清洁。保留外部进程日志作为生命周期验证，业务内容指纹不变。

- [x] 写资源存在、种类与字面属性测试；写奶茶引用同一Resource的断言，运行红灯确认缺失共享资源。

```gdscript
func test_tea_uses_shared_rabbit() -> void:
    var path := "res://content/characters/staff/rabbit.tres"
    if not ResourceLoader.exists(path):
        check(false, "Missing shared rabbit definition")
        return
    var rabbit: SpecStaffKind = load(path)
    check_eq(rabbit.stats, {"carry":2.0,"walk":104.0,"work":1.0}, "Tea rabbit baseline")
    var tea: SpecShop = load("res://content/shops/tea/shop.tres")
    var existing := tea.staff.kinds.filter(func(k: SpecStaffKind) -> bool: return k.id == "rabbit")
    check_eq(existing.size(), 1, "One rabbit kind")
    if existing.size() == 1:
        check(is_same(existing[0],rabbit), "Tea references the shared definition")
```

- [x] 将奶茶六个原定义逐字段提取，保留当前display_name、role和description，包括已有英文名称；这一任务不顺带重命名。

```ini
[gd_resource type="Resource" script_class="SpecStaffKind" load_steps=2 format=3]
[ext_resource type="Script" path="res://content/rules/spec_staff_kind.gd" id="staff"]
[resource]
script = ExtResource("staff")
id = "rabbit"
display_name = "小兔子"
stats = Dictionary[String, float]({"carry": 2.0, "walk": 104.0, "work": 1.0})
role = "速度型"
description = "擅长快速搬运"
```

- [x] 在tea/shop.tres顶部添加六个共享资源引用，将原kinds列表按原顺序替换，删除被替代的六个sub_resource；不编辑其他经营内容。
- [x] 加入全部六种的字面表断言以及两个员工实例stats独立的断言：改一个员工的运行stats不能修改共享资源或其他员工。沿用WorkerState.create的既有复制机制，不新加缓存。
- [x] 检查提取前后奶茶gameplay/structure指纹与T01完全相同，确定性轨迹与原基线一致。若变化，先定位遗漏字段或资源顺序，不重录基线。
- [x] 运行现有奶茶GUI和工人状态/配置校验相关测试。文档说明其他店还未迁移，最终全局约束在T09/T10接入后启用。

**验收出口：** 奶茶六种员工只有一个正式定义来源，规则行为和内容指纹不变；没有因共享Resource产生运行状态串改。

## T03：验证旧奶茶档兼容，并交付A阶段

**Files**

- Modify: `tests/test_content_save.gd`或`tests/test_content_rules.gd`（加入共享资源重构的真实存档用例）。
- Modify only if a reproduced gap exists: `game/rules/shop_save.gd`、`game/rules/shop_rules.gd`中的已有内容刷新边界。
- Update: `docs/qa/tea-modularity-baseline.md`与本计划状态。

**Interfaces**

- Consumes: T01隔离旧档和继续轨迹、T02共享定义、`ShopSave`已有版本2内容指纹与备份、`ShopRules.load_dict(data,refresh_content)`。
- Produces: 旧档读取、继续60秒和重存后的兼容证据，以及后续校准任务可复用的存档回归入口。

- [x] 添加真实ShopSave读取T01旧档、正常继续、重新保存、重新打开的用例；核对角色ID、岗位、招募名册、金币、订单、升级与续跑状态/事件。仅以字典load代替文件层读取不算完成。
- [x] 增加独立的数值刷新用例：深复制SpecShop，改变复制资源上的基础stats，用`load_dict(old_state,true)`确认基础值更新而进度与加成保留；这个用例不得修改共享已加载Resource。

```gdscript
func test_worker_base_refresh_preserves_progress() -> void:
    var original: SpecShop = load("res://content/shops/tea/shop.tres")
    var old := ShopRules.new(original)
    old.unlock("lemonade")
    old.run(12.0)
    var state := old.to_dict()
    var updated: SpecShop = original.copy_for_editing()
    updated.staff.kinds[0].stats.walk = 113.0
    var resumed := ShopRules.new(updated)
    check_eq(resumed.load_dict(state,true), "", "Refresh is supported")
    check_eq(resumed.roster[0].stats.walk, 113.0, "Current base replaces saved base")
    check_eq(resumed.gold, old.gold, "Gold survives")
    check_eq(resumed.stage_index, old.stage_index, "Stage survives")
    check_eq(resumed.levels, old.levels, "Upgrades survive")
```

- [x] 先在现有机制上运行测试。若已通过，保留新增覆盖，不为制造红灯修改生产代码；若暴露缺口，记录失败、修复最小边界并重跑受影响组。
- [x] 执行最终规则套件、奶茶真实界面、`tools/validate_shops.gd`与`tools/sync_shop_layouts.gd -- --check`。校验仅检查，不写回其他店布局。既有未提交内容导致失败时单独报告与隔离，不覆盖用户改动。
- [x] 最终核对旧基线未被覆盖、奶茶fingerprint未变化、煎饼摊与第三店数据未改、_work证据未加入提交范围。更新T01–T03状态和实际结果，说明A阶段尚未完成跨店统一。

**验收出口：** A阶段可独立审阅与集成；旧奶茶的运行与存档稳定，并为B阶段公共表现和移动改造提供可重复的基线。

## 执行结果（2026-11-11）

T01、T02、T03均完成。最终382规则用例、奶茶84、煎饼88、第三店33项界面检查通过，且进程退出清洁；4店契约及两店空间导出一致。奶茶轨迹/内容指纹与原基线一致，合成旧档及续跑保持兼容。复制隔离与Godot4.6生命周期边界见docs/qa/tea-modularity-baseline.md。未提交或推送。
