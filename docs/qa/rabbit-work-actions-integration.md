# 小兔子组装动作接入（2026-11-06）

来源：`E:/Work/小兔子组装动作/`。只读使用来源，45 张 256×256 RGBA PNG 按字节归档到 `art_src/rabbit_work_actions/`；原说明随帧保存，SHA256、GIF 帧停留时长和来源路径见 `source_manifest.json`。

| 片段 | 来源目录 | 原帧 / 保留帧 | 每轮时长 |
| --- | --- | ---: | ---: |
| `work_front` | 小兔子正面组装关键帧 | 17 / 17 | 4 秒 |
| `work_right` | 小兔子侧面组装关键帧 | 14 / 14 | 4 秒 |
| `work_back_right` | 小兔子背侧45组装关键帧 | 14 / 14 | 4 秒 |

正面 TXT 中的“GIF 按 01→14”与总览过时：实际 PNG 和 GIF 都是 17 帧，按文件和 GIF 记录导入，原说明不改写。三组末帧与首帧可见像素均不同，全部保留；不去掉中间停顿，不重绘、改色、缩放、逐帧裁切或重居中。视频、GIF 预览和 JPG 总览不作为运行时帧。

复用共享导入工具和 Godot 图集构建器；导入工具列数随实际帧数扩展，本批图集 17 列、3 行。运行文件位于 `art/rabbit_work_actions/`。组合 SpriteFrames 引用原兔子走路、待机图集及已调整的节奏，不重复归档旧动作。固定画布锚点保持 `(128, 244)`，可见高度基准保持 228，帧目录带 `.gdignore`。

兔子继续使用已有员工身份和动作播放器。制作 `work` 阶段，以及前台从原料制作柠檬水/柠檬茶的 `pickup` 阶段播放组装；普通取货、放货和等候播放待机，移动优先走路。工位朝向、缺失视角的最近视角和左侧镜像、模拟时钟暂停均沿用现有规则。未改订单、库存、员工参数、存档格式或布局。

菜单或员工页 → 角色预览 → 小兔子 → 组装，可查看三个原始视角及八方向映射，支持暂停、逐帧、进度和调速；界面显示实际原始视角数。

重建：

```powershell
python tools/import_rabbit_work_actions.py 'E:/Work/小兔子组装动作'
$godot = 'D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path . -s art_src/rabbit_walk_frames/build_atlas.gd -- --source=res://art_src/rabbit_work_actions/ --atlas
& $godot --headless --path . --editor --import
& $godot --headless --path . -s art_src/rabbit_walk_frames/build_atlas.gd -- --source=res://art_src/rabbit_work_actions/
```

运行游戏不依赖 E 盘或 Python。本地 Godot 4.6.3 验证：

- 45 张外部源 PNG、归档及 manifest 哈希逐一一致。
- `test_work_action_atlases.gd`：原 448 张加本批 45 张，共 493 张；图集像素、透明度、帧时长、旧图集复用，0 failures。
- `test_work_actions.gd`：制作/待机/走路切换、暂停、八方向最近视角与镜像、正面 17 帧及四秒周期，0 failures。
- `render_work_actions.gd`：真实店铺兔子煮茶生产与库存审计、嵌入预览、正面第 17 帧及逐帧首尾循环，无头及原生 Vulkan 窗口均 0 failures。已目视核对正面、侧面、背侧、左侧预览与兔子实际工位截图，位于 `.godot/work_actions_capture/rabbit-*.png`。
- `test_rabbit_frame_atlas.gd`、`test_rabbit_game_visuals.gd`、`test_gray_cat_atlas.gd`、`test_gray_cat_game.gd` 均 0 failures；兔子原生窗口 `render_rabbit_game_integration.gd` 的 HUD 输入、暂停、方向、逐帧、调速、招募、派遣、存档与小窗口检查均 0 failures。

主回归 `tests/run_all.gd`：111 个用例，0 个失败。只读代码审查未发现需修改问题。

图集、动作与真实店铺验证仍由现有 CI 入口执行。
