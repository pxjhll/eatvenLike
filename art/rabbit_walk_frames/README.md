# 小兔子走路帧动画图集

源素材：`E:/Work/小兔子走路/`。五个方向各七张透明 PNG，原文件夹保持不变。

## 文件与用法

- `rabbit_walk_atlas.png`：**1792×1280**，7列×5行，每格 **256×256**，RGBA 透明背景。
- `rabbit_walk_frames.tres`：原生 `SpriteFrames` 资源，拖到 `AnimatedSprite2D.sprite_frames` 即可播放。
- `res://presentation/rabbit_walk_frames/rabbit_walk.tscn`：可直接实例化的角色，仅使用 `AnimatedSprite2D` 与方向控制脚本。
- `res://presentation/rabbit_walk_frames/preview.tscn`：在 Godot 4.6 中 F6 运行，检查原尺寸/50%尺寸、八方向、暂停、逐帧、速度和时间轴。快捷键 Space 播放/暂停，左右方向键切换朝向。

图集从上到下：

| 行（从0计） | 动画名 | 视角 | 原始周期 |
|---|---|---|---|
| 0 | `walk_front` | 正面 | 0.79秒 |
| 1 | `walk_front_right` | 右前45° | 0.96秒 |
| 2 | `walk_right` | 右侧 | 1.00秒 |
| 3 | `walk_back_right` | 右后45° | 0.88秒 |
| 4 | `walk_back` | 背面 | 0.75秒 |

每行动画的帧序均为01→02→03→04→05→06→07，然后循环回01。

帧区域计算：`Rect2(帧索引 * 256, 行索引 * 256, 256, 256)`，索引从0开始。AtlasTexture 开启 `filter_clip`；贴图使用无损导入，关闭 mipmaps。每格原有透明留白保留，不进行逐帧紧裁、拉伸、重绘或重新居中。

## 首尾帧核查结果

**本批保留全部35张。** 五组01与07的可见像素均不相同，脚部支撑、手臂位置或眨眼状态仍有区别，07是独立步态样本。四组附带说明另有记录：重复的视频闭环终点在提帧时已省略。说明仅作为来源参考，判断同时核对了实际PNG和步态。

未再添加一个重复的01，也未机械删除每组07。对未来输入，构建工具仅会移除与首帧可见像素完全相同的末帧，忽略全透明像素中的隐藏RGB；内部重复帧可用于停留，保持原样。近似但不相同的收尾姿态需要继续人工核查。

`SpriteFrames` 所有片段均开启循环。基准速度是10 FPS，各帧相对时长保留原GIF节奏，因此周期以表中时间为准；七帧并非全都等时长。

## 八方向与尺寸

角色脚本的方向索引：0正面、1右前、2右侧、3右后、4背面、5左后、6左侧、7左前。后三个方向共享右侧对应片段并使用 `flip_h`，不复制图集。

`set_direction(index)` 保留归一化动作进度与暂停状态；`set_speed(value)` 调整播放倍率；`pause()` / `play()` 控制播放，`seek_phase(0.0...1.0)` 用于时间轴。

画布基准锚点为 `(128,244)`，原生 Sprite 设置 `centered=false`、`offset=(-128,-244)`，角色根节点作为脚底参考位置。保留原始帧内的上下起伏和小幅横移。

**256×256是画布大小。** 原图中含耳朵的角色可见高度约211～229像素；50%预览的画布是128×128，人物可见高度约106～115像素。当前没有为填满画布而放大、逐帧对齐或改变不同视角的原始比例。

## 源文件与重建

本地副本和SHA256、帧时长、透明边界、首尾核查记录位于 `art_src/rabbit_walk_frames/`。35张源PNG与外部原文件字节一致；源帧目录使用 `.gdignore`，不会重复导入为运行时贴图。运行时角色只依赖本图集、SpriteFrames和角色脚本，不需要E盘源目录。

在项目根目录执行：

```powershell
godot --headless --path . -s art_src/rabbit_walk_frames/build_atlas.gd -- --atlas
godot --headless --editor --path . --import
godot --headless --path . -s art_src/rabbit_walk_frames/build_atlas.gd
godot --headless --path . -s tests/test_rabbit_frame_atlas.gd
godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/render_rabbit_frame_atlas.gd
```

构建脚本覆盖本目录生成的PNG和TRES；手工修改过导出资源时请先保留修改。

原图已有的后斜视角细白边、少量脚部颜色变化也被原样保留，图集打包没有擅自重绘或去噪。以后需要清理时应处理源帧后再重建。
