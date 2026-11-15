# T04 共享角色尺度与表现 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans sequentially. 不创建新聊天、worktree或代理。

**Goal:** 奶茶店保持原表现；三家店在相同窗口下使用相同角色逻辑尺寸和一致的显示大小。

**Architecture:** 共享Resource定义奶茶基准和相机换算。现有场景坐标保留，原生画布宽度除以720得到场景单位倍率；角色根节点整体应用倍率，身体、手持物、气泡和影子一起变化。相机缩放抵消该倍率，规则层状态和现有图片像素尺寸不变。

**Tech Stack:** Godot 4.6.3/GDScript/Resource/TSCN。

**Spec:** `docs/superpowers/specs/2026-11-11-modular-shop-system.md`。

## Global Constraints

- 从A阶段提交9fd08aa继续，当前工作目录D:/Tes/eatventure，保留已有用户改动。
- 奶茶基准：员工128、顾客110、顾客基础走速170、参考宽720、横屏最少可见逻辑高度1100。
- 本任务只统一表现与视图运动单位，不改变员工初始stats、菜谱、经营数值、规则运动状态或导航。T05统一抵达事实，T09/T10迁移其他店的员工基准。
- 原PNG、工位和桌椅坐标不改；三个生产场景与面馆夹具只移除角色大小/速度的独立覆盖项。
- 使用当前已有的满宽适配：画布宽度作为原生素材坐标密度，换算到参考逻辑宽720；不引入横向相机或新的大地图机制。
- 所有Godot运行设置隔离APPDATA到_work/shop_modularity/phase-b/session-lifecycle-userdata/<runner>。
- A阶段基线和旧档不能重录；奶茶规则轨迹与内容指纹必须继续一致。

## Files and interfaces

- Create `content/characters/actor_presentation.gd`、`actor_presentation.tres`：共享基准；`scene_units(world_size:Vector2)->float`，`fit(view_size:Vector2,world_size:Vector2,ui_width:float=720)->Dictionary`，`validate()->PackedStringArray`。
- `fit`输出`unit_scale/world_factor/ui_factor`；坏参数返回空字典。`world_factor = min(view.x/720,view.y/1100)/unit_scale`，`ui_factor`保持既有UI宽度适配。
- Modify `presentation/shop/shop_play.gd`：角色工厂、客户视图速度、相机适配与世界物品使用共享单位。角色本地高度为128/110，根scale为unit_scale。
- Modify `presentation/shop/shop_actor.gd`：默认员工高度取共享Resource，保留显式高度参数供预览和角色类型使用；手持物基准继续沿用全局CUP_HEIGHT52。
- Modify `presentation/shop/shop_dining.gd`：顾客根scale、步行视图速度和杯子/坐姿显示偏移按同一单位换算。
- Modify `presentation/shop/staff_drag.gd`：人物命中框和从卡片拖出的抓取偏移按角色单位换算，拖拽影子复用角色工厂。
- Modify `presentation/shop/shop_scene_contract.gd`：验证共享配置；拒绝场景customer_height/staff_height/customer_speed覆盖。
- Modify `presentation/shops/{tea,pancake}/*_art.tscn`、`tests/fixtures/noodle/shop_scene.tscn`：移除旧覆盖；第三店本来没有覆盖项。
- Create `tests/test_actor_presentation.gd`、`tests/render_actor_presentation.gd`；register rule suite in `tests/run_all.gd`。更新docs/shop-onboarding.md及验收记录。

## Steps

- [x] 写断言：共享Resource存在，基准值正确；三种原生尺寸在720×1280、1280×720、480×800下得到一致屏幕角色高度；无效参数安全拒绝。
- [x] 写场景契约断言：即使角色覆盖值正数且有限，也必须拒绝，路径明确。运行红灯，不能因解析错误失败。
- [x] 实现共享Resource和纯换算。它不引用ShopRules、角色节点或场景，避免资源依赖环。
- [x] 接入相机与角色工厂，角色整体缩放；世界杯子/放置物与手持物保持同一尺度；所有顾客视图分支消费同一个换算速度。
- [x] 更新堂食与拖拽命中，移除生产场景和面馆夹具旧覆盖，更新新增店铺说明。
- [x] 添加正式场景采样入口：三个店、两种窗口、同一只兔子，比较身体包围盒大小与逻辑高度；核对堂食工厂和拖拽影子使用同一倍率。
- [x] 运行专项、奶茶原轨迹、三店真实界面、4店契约及布局只读检查；运行完整规则套件并扫描运行错误和退出泄漏。
- [x] 生成实际画面与数据对比，记录本阶段有意变化及后续速度/导航迁移边界，更新T04状态。T04改动与A阶段提交分开交付。

## Acceptance

同视口、同角色的屏幕包围盒尺寸误差不超过0.5像素；逻辑角色高度一致；手持物和世界物品尺度一致。奶茶原轨迹、指纹和存档夹具继续通过，其他店不出现启动、点击、拖拽、存读档或退出错误。场景不能覆盖全局角色基准。第三店穿物、员工360走速等问题仍由后续任务处理，本任务不宣称整个公共行为系统完成。

## 执行结果

T04完成：386规则用例、82项实拍检查、三店界面84/88/33项、4店契约与两店空间导出通过。奶茶两种窗口原始实拍逐像素相同，三店参考兔子帧矩形尺寸一致。详情见docs/qa/shared-actor-presentation.md。A阶段9fd08aa已推送；T04按用户指令单独提交，本次不推送。
