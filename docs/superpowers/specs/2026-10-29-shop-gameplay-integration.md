# 美术店铺经营与员工存档闭环

用户已批准：优先迁入已有经营能力，并打通员工拥有、派遣、岗位和保存。本轮直接实施，不实现自由建造与随机抽卡。

## 规则边界

- 默认美术场景成为有进度的店铺。保留当前手工煮茶/加料、真实搬运、封口和即时拖放；原 TeaPlaytestSim 保持可注入的无进度生产沙盒，以运行已有生产/拖拽回归。
- 经营配置复用 `content/tea/tea.tres`：50 开局金币，10 金币解锁柠檬茶；营业额 300 后可支付 240 解锁奶茶线；营业额 1500 后可支付 300 解锁加料。设备等级、配料等级、售价、任务目标、口味解锁等级读取原 Resource。
- 固定家具位置不变，锁定设备弱化并显示可点击的价格/条件牌；点设备弹出真实解锁/升级面板。柜台保持开放；展示柜兼作柠檬茶取杯区，不添加新家具。
- 当前物理批次仍按 3 份茶汤对应 3 杯生产，保留已验证的当前流程节拍；不替换为旧版抽象传送带模拟。原料柜茶叶/牛奶升级应影响真实补给或加工效率。
- 奶茶成品保留真实口味，从加料或原味分流到封口、货架、配送；不能在销售时凭空换口味。顾客仅点当前已解锁饮品；口味升级实际影响售价。
- 经营任务显示真实销量/等级与完成进度，不新增未确认的任务奖励或换店规则。
- 员工收藏独立于店内上岗。初始小猫已拥有并派出；普通招募沿用当前 35/60 金币，获得的浣熊/狐狸进入待派遣名册；当前店内最多 3 位。岗位与能力保留，收回员工会归还在途货物和预留。
- 培养可作用于待派遣或店内员工；已拥有员工不因重开店铺丢失，等级保留。员工来源记录为初始、招募或调用方奖励来源，为后续渠道提供接口；不新增随机抽卡规则。
- 新经营存档独立于旧版 `save.json`，不覆盖或迁移旧版库存/名册。持久化全部真实店铺状态、名册、派出关系、岗位、培养、物流、机器中途进度、订单与随机状态；读档不中途复制或丢货。自动存档、手动存档、退出保存和恢复后连续经营均可验证。
- 既有 UI 命中/滚动/遮挡/触摸约束继续有效。所有测试使用注入的模拟或独立测试存档，不写玩家真实存档。

## 接口

`TeaShopSim`（`game/tea_playtest/tea_shop_sim.gd`，继承现有模拟）提供：

- `roster: Array` 为拥有的员工字典；`workers: Array` 仅为已派出的同一字典引用，`worker_by_id(id)` 返回名册记录。
- `all_workers() -> Array`, `deploy_worker(id) -> String`, `recall_worker(id) -> String`, `acquire_staff(art, source) -> String`, `hire() -> bool`, `hire_cost() -> int`, `train(id) -> bool`, `train_cost(id) -> int`。
- `station_info(id) -> Dictionary` 包含 name、unlocked、level、description、unlock_cost、unlock_error、upgrade_cost、upgrade_error、materials（每项 id/name/level/upgrade_cost/upgrade_error）。所有错误供 UI 原样展示。
- `unlock_station(id) -> String`, `upgrade_station(id) -> String`, `upgrade_material(station, material) -> String`，验证失败不扣款。
- `task_rows() -> Array`（name/current/target/complete），`current_goal() -> String`，`dish_name(id) -> String`, `station_unlocked(id) -> bool`。
- `shelf_stock: Dictionary` 与货架总数一致；订单包含 dish；杯子/运单使用实际饮品 id；`revenue`, `stage_index`。
- `to_dict() -> Dictionary`, `load_dict(state) -> String`，完整保存运行状态，失败不部分应用；`reset_shop() -> void` 保留名册和培养。

`TeaShopSave`（`game/tea_playtest/tea_shop_save.gd`）提供：

- `_init(path = "user://tea_shop.json")`、`load_game() -> RefCounted`、`save_game(sim, speed = 1.0) -> Error`、`loaded_speed: float`、`last_error: String`。
- 使用 SaveService 的原子替换；状态可使用无对象的 Godot Variant 二进制 base64 封装以无损保留 Vector2/PackedVector2Array 和数值类型，带明确格式版本。旧版 save.json 不访问。

## 验证

新开店至柠檬茶收入、支付开线、设备/配料升级、各口味库存与点单、真实经营任务；名册与派出分离、忙碌收回守恒；中途存档读回逐步运行一致；主界面原生输入与三种窗口尺寸；已有 99 用例继续通过。
