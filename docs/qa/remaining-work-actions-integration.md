# E:/Work 剩余动作接入（2026-11-05）

只处理根目录待配置的 `小仓鼠/` 和 `小灰猫操作/`，跳过 `已经配置进游戏的/` 及重复的 7z。E 盘原文件及目录位置均未修改。

| 角色 | 新增片段 | 原帧 | 每轮时长 |
| --- | --- | ---: | --- |
| 仓鼠 | 侧面行走、背侧45待机、正侧坐姿待机 | 7 + 14 + 14 | 2秒、4秒、4秒 |
| 小灰猫 | 侧面操作、背侧操作 | 14 + 14 | 各4秒 |

共63张256×256透明PNG、5组动作。来源PNG按字节复制，保留SHA256、GIF帧停留时长和TXT原说明；不重绘、不改色、不缩放、不逐帧裁切。五组末帧均与首帧不同，全部保留。视频、GIF、JPG和1024px原画不作为运行时帧。

仓鼠使用固定画布锚点(128,243)、可见高度基准222；复用顾客原有身份及轮换顺序，进出店走路、排队待机、等单及用餐坐姿、取餐恢复走路。源坐姿仅有一个正侧视角，左右镜像朝向桌面。灰猫保持原锚点(128,247)和高度基准240，操作图集单独保存，组合SpriteFrames引用原有走路与待机图集及已调好的节奏。

员工人工制作阶段 `work` 播放操作；前台从原料制作柠檬水/柠檬茶的 `pickup` 阶段也播放操作，朝向左侧饮品台。普通取货、放货保持待机，移动优先播放走路；工位操作按机器朝向选侧面/背侧片段及镜像。动画随模拟时钟暂停。未改订单、库存、员工属性、招募、存档格式或家具布局。

菜单 → 角色预览，选择“仓鼠”或“小灰猫”，可查看所有新动作，支持八方向选择、暂停、逐帧、进度和调速。界面提示实际原始视角数及缺失方向的处理方式。

归档清单：`art_src/remaining_work_actions_inventory.json`。新来源目录和运行目录分别为 `art_src/{hamster_actions,gray_cat_work_actions}/` 与 `art/{hamster_actions,gray_cat_work_actions}/`。

重建：

```powershell
python tools/import_remaining_work_actions.py E:/Work
$godot = 'D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe'
$batches = 'hamster_actions','gray_cat_work_actions'
foreach ($batch in $batches) {
    & $godot --headless --path . -s art_src/rabbit_walk_frames/build_atlas.gd -- --source=res://art_src/$batch/ --atlas
}
& $godot --headless --path . --editor --import
foreach ($batch in $batches) {
    & $godot --headless --path . -s art_src/rabbit_walk_frames/build_atlas.gd -- --source=res://art_src/$batch/
}
```

本地Godot 4.6.3验证：

- 63张外部源PNG与归档哈希逐一匹配；`test_work_action_atlases.gd`校验前批385张加本批63张，共448张，像素、透明度、帧时长及旧图集复用均0失败，已加入CI。
- `test_work_actions.gd`：动作切换、站坐镜像、暂停、走路优先、普通搬运与前台制作区分、真实后厨生产及库存守恒，0失败。
- `render_work_actions.gd`：无头及原生Vulkan窗口均0失败，覆盖仓鼠进店/等单入座/取餐/离店和灰猫真实工位操作；已目视检查新动作和店内截图。截图位于 `.godot/work_actions_capture/`。
- 原兔子图集/游戏表现、灰猫图集/游戏逻辑回归均0失败。灰猫原生窗口交互回归0失败，包含八方向、暂停、逐帧、调速、招募派遣与360×640预览；测试点击改用控件实际全局尺寸和窗口缩放后的输入坐标。
- 主回归111用例0失败；店铺UI、经营交互回归均0失败。只读代码审查未发现需修复问题。

运行游戏不依赖E盘或Python。
