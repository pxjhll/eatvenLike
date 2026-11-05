# E:/Work 动作接入（2026-11-05）

来源核对见 `art_src/work_actions_inventory.json`。本次按 PNG SHA256 核对现有来源和运行资源后，只归档新增的 385 张 256×256 透明 PNG、32 组动作。E 盘文件未修改。

| 角色 | 原有动作，本次跳过 | 本次新增 | 新增原帧 |
| --- | --- | --- | ---: |
| 小兔子 | 走路，5 视角，35 张 | 待机，5 视角 | 70 |
| 小灰猫 | 走路，5 视角，35 张 | 待机，5 视角 | 70 |
| 小熊 | 无（旧 bear 定义未连接当前帧动画及员工名册） | 走路、待机，各 5 视角 | 105 |
| 小松鼠 | 游戏中使用静态图，无帧动画 | 侧走、背侧待机、侧坐 | 35 |
| 小狗 | 无 | 侧走、背侧待机、侧坐、前侧坐 | 49 |
| 小羊 | 无 | 侧走、背侧走、背侧待机、侧坐、前侧坐 | 56 |

7z 与展开目录重复，不再解压复制；视频、GIF、1024px 原画不作为运行时帧。GIF 仅用来读取逐帧停留时长，TXT 原说明随帧归档。只移除与首帧可见像素完全相同的末帧，保留中间停顿和不同的末帧。

新资源位于 `art_src/{rabbit,gray_cat,bear,squirrel,dog,sheep}_actions/`，运行图集及 SpriteFrames 位于对应 `art/` 目录。所有来源 PNG 字节不变，保留统一画布；没有重绘、改色、缩放、逐帧裁切或重居中。兔子、灰猫的新资源直接引用旧走路图集及已经调好的速度，不重复归档走路帧。

角色预览仍从菜单或员工页进入，新增待机、坐姿选项及顾客角色。兔子、灰猫、小熊具备五个原始视角，左右镜像覆盖八向；顾客仅用已有视角，缺失方向选最近视角并镜像，预览界面明确提示原始视角数量。小狗侧走、侧坐和前侧坐原图朝左，以 SpriteFrames 的逐动作朝向元数据纠正镜像，不改原图。

店内员工移动时走路、停下时待机；由模拟时钟驱动，游戏暂停时冻结。小熊接在原五类员工后付费招募，复用已有力量型员工基础参数（移速 88、搬量 3、操作 1），未另改平衡。旧存档员工 id 与原身份保留；新动物不会覆盖占用 id 的重复员工。

顾客依次显示为松鼠、小狗、小羊和原仓鼠。进店/离店用走路，排队用待机，在堂食座位等单或吃饭时用坐姿并朝向桌面，取餐时恢复走路。原仓鼠保持已有静态表现。动作和顾客外观属于表现层，不修改订单或库存状态、路径、杯子尺寸、家具布局和座位规则。

重建：

```powershell
python tools/import_work_actions.py E:/Work
$batches = 'rabbit_actions','gray_cat_actions','bear_actions','squirrel_actions','dog_actions','sheep_actions'
foreach ($batch in $batches) {
    godot --headless --path . -s art_src/rabbit_walk_frames/build_atlas.gd -- --source=res://art_src/$batch/ --atlas
}
godot --headless --path . --editor --import
foreach ($batch in $batches) {
    godot --headless --path . -s art_src/rabbit_walk_frames/build_atlas.gd -- --source=res://art_src/$batch/
}
```

运行游戏不依赖 Python 或 E 盘。归档帧目录有 `.gdignore`，避免每张源帧重复导入。

验证入口：`test_work_action_atlases.gd` 核对全部 385 张来源哈希、图集像素、停留时长及旧走路复用；`test_work_actions.gd` 核对动作切换、暂停、镜像、小熊招募与旧 id 冲突；`render_work_actions.gd` 用真实店铺和嵌入预览检查顾客入座/取餐、各动作和方向，并在原生渲染下截图。临时截图位于 `.godot/work_actions_capture/`。

本地 Godot 4.6.3 验证：主回归 111 个用例、0 个失败；新增图集、动作与场景检查均为 0 failures，旧兔子和灰猫图集及游戏表现检查通过；兔子、灰猫和新增动作的真实窗口检查均为 0 failures。旧交互检查的招募夹具已适配当前 main 的“招募即上岗、需要空位”行为，滑块检查使用控件实际值验证帧进度。新动作检查已加入 CI。
