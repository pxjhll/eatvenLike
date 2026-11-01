# 小灰猫走路帧动画

源目录 `E:/Work/小灰猫走路/`，原素材保持不变。35张256×256透明PNG已逐字节复制到 `art_src/gray_cat_walk_frames/frames/`，运行时无需E盘目录。

- 图集：`gray_cat_walk_atlas.png`，1792×1280，7列×5行。
- 原生动画：`gray_cat_walk_frames.tres`，供AnimatedSprite2D使用。
- 可实例化角色：`presentation/gray_cat_walk_frames/gray_cat_walk.tscn`。
- 独立预览：`presentation/gray_cat_walk_frames/preview.tscn`，F6运行；支持原尺寸/半尺寸、八方向、暂停、逐帧、进度和调速。
- 游戏预览：菜单 → 角色预览 → 小灰猫；员工页可直接查看所选角色。

| 图集行 | 视角/动画 | 原周期 | 游戏周期（1倍速） |
|---|---|---|---|
| 0 | 正面 `walk_front` | 0.96秒 | 约0.565秒 |
| 1 | 右前45° `walk_front_right` | 0.92秒 | 约0.565秒 |
| 2 | 右侧 `walk_right` | 0.79秒 | 0.80秒 |
| 3 | 右后45° `walk_back_right` | 0.75秒 | 0.80秒 |
| 4 | 背面 `walk_back` | 0.71秒 | 0.80秒 |

按用户截图确定的观感调整：正面三向在0.65秒基础上加速1.15倍，周期为0.65/1.15≈0.565217秒；侧面与背向保持0.80秒一轮。`art_src/gray_cat_walk_frames/playback.json`保存运行时节奏，构建器通过原生动画速度调整，保持每帧相对停留比例、原PNG和来源时长记录；重新导入源文件或重建图集也会保留调速。预览和店内使用同一个SpriteFrames资源。

八方向同屏对照：运行 `presentation/gray_cat_walk_frames/direction_compare.tscn`。所有朝向同时原生播放，底部分别微调正面三向和侧背五向速度；滑块仅影响这个对比窗口，重置恢复当前游戏资源的约0.565/0.80秒基准。选定的1.15倍已写入游戏资源，新开预览以1.00倍显示这个新基准，避免重复加速。

每组01与07是不同步态，保留全部七帧并直接07→01循环，不追加闭环首帧。说明文件记录视频的重复终点已省略。仅使用PNG原像素；GIF仅用于读取各帧时长，未使用GIF的浅蓝背景或调色板重建PNG。

左右镜像得到左前/左侧/左后，共八向。固定画布锚点(128,247)，不逐帧裁剪、重心对齐或重绘；保留原始动作起伏。店内按可见高度基准240等比显示为约128高，移动时播放，停止保持当前朝向首帧，动画跟随模拟时间。当前只有走路素材。

重建（Python导入工具需Pillow，游戏运行无需Python）：

```powershell
python tools/import_gray_cat_frames.py 'E:/Work/小灰猫走路'
godot --headless --path . -s art_src/rabbit_walk_frames/build_atlas.gd -- --source=res://art_src/gray_cat_walk_frames/ --atlas
godot --headless --editor --path . --import
godot --headless --path . -s art_src/rabbit_walk_frames/build_atlas.gd -- --source=res://art_src/gray_cat_walk_frames/
```

共享构建器默认仍重建兔子；`--source`切换到小灰猫来源清单。清单包含每张PNG的SHA256、透明边界、原帧时长及首尾核查记录。
