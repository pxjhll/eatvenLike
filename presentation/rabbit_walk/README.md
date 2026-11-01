# 独立角色骨骼动画预览

**历史试作说明：** 本目录是最初恢复的旧骨骼素材。用户要求改为当前帧动画兔子后，新的有效预览迁至 `presentation/rabbit_skeleton/preview.tscn`；请查看那一版本的美术、动作与同步原帧对照。

当前版本在 `codex/rabbit-frame-gameplay` 工作目录中选择性恢复自旧骨骼分支 `codex/rabbit-animation-viewer`（`f2edb7c`），并完善为独立预览。没有修改游戏入口、员工显示逻辑或现有帧动画资源。

打开 **`animation_viewer.tscn`**，在 Godot 4.6 中按 **F6** 运行当前场景。

- 左侧选择走路或站立，下面显示当前方向的上传原图。
- 左侧「物品」提供无、杯子、工具三种模式。杯子固定在角色局部位置，按方向调整偏移与前后遮挡，保持直立；工具示例是挂到实际手部 Grip 节点的勺子，会随手部移动、旋转和镜像。
- 中央大图与右下游戏尺寸预览同步。游戏尺寸采用约128像素人物高度，杯子位置和大小是本预览的独立配置，接入游戏时再对齐实际角色尺寸。
- 右侧八方向按钮切换正面、斜前、侧面、斜后与背面，三组左右方向使用镜像。
- 切换方向保持当前进度、暂停状态、速度与柔性设置。
- 底部控制播放、回到开头、上一帧/下一帧（1/30 秒）、速度、循环和时间轴。
- 右侧可切换骨骼、柔性耳朵和网格，并调整显示大小。
- 快捷键：**Space** 播放/暂停，**左右方向键** 切换角度。

五套可编辑资源：`rabbit_front.tscn`、`rabbit_front_right.tscn`、`rabbit_side.tscn`、`rabbit_back_right.tscn`、`rabbit_back.tscn`。`directional_rabbit.gd` 按需缓存视角，负责切换与镜像，原生场景保存实际网格、权重并引用独立动作库。

`art/rabbit_walk/motions/` 保存每个视角的 `AnimationLibrary` 和独立的 `*_walk.tres` 动作资源。同视角角色实例共用这些资源，播放时间和物品选择各自独立。当前已验证兔子实例之间共享动作；不同体型角色仍需统一骨架和适配，尚未制作第二种角色皮肤。

`prop_attachment.gd` 独立管理两类物品；它只用于此骨骼预览，不改变游戏已有的杯子坐标。预览专用字体为 `art/rabbit_walk/preview_font.ttf`，来自旧骨骼提交，与现有游戏字体同源、同许可，许可见 `art/ui/font_license.txt`。

原来的 `walk_preview.tscn` 仍保留为侧面绑定对照：

- 左：上传原图的右侧面，保持原始像素供核对。
- 中：侧面走路与小尺寸效果。
- 右：同一动画的水平镜像，叠加真实骨骼位置。
- 操作：暂停、速度、时间轴、镜像、柔性耳朵开关；快捷键 Space / M / F。

## 可编辑角色

`rabbit_side.tscn` 是独立的原生资源，不依赖预览脚本。包含：

- 一个 `Skeleton2D`，17 个 `Bone2D`，所有骨骼均保存静置姿态。
- 九个带 UV、显式三角面及归一化权重的 `Polygon2D`。
- `AnimationPlayer` 中的 `RESET` 与 `walk`；走路周期 0.8 秒。
- 近、远耳各三节骨骼，耳根、中段与耳尖错相运动；手臂各两节。
- 身体/胸部混合权重；头部、脚掌与尾巴主要按刚性部件处理。

直接编辑 `AnimationPlayer` 的 `walk`，或选择 `Skin/EarNear` / `Skin/EarFar` 在 Polygon2D 的 UV 编辑器内查看网格和权重。所有动作轨道驱动骨骼，未使用逐帧兔子贴图或外部动画插件。

柔性指**骨骼权重驱动的连续网格弯曲**，属于制作好的循环动作；本版没有实时弹簧、布料或物理模拟。柔性开关保留耳根运动，将中段和耳尖关节归零，方便对比整片旋转与分段弯曲。

侧面脚掌支撑期间相对角色以每秒70单位后移；游戏接入时需结合角色缩放同步移动和播放速度。其他视角有各自的投影步幅，不能直接照搬此侧面数值。主预览原地播放供检查姿势；旧侧面对照场景还保留移动地面刻线。

## 美术来源与当前限制

用户提供的八方向图保存于 `art_src/rabbit_walk/reference.png`。内置 imagegen 以第二只右侧面兔子为参照，拆分并补绘了九部件，之后单独修正身体上画死的手臂。生成的透明部件图集保存于 `art_src/rabbit_walk/parts_atlas.png`；原生 Godot `Image.get_region()` 负责无损裁出 `art/rabbit_walk/` 中的九张 PNG。

新增四方向的透明图集保存于 `art_src/rabbit_walk/views/`，提示词是该目录的 `prompts.json`，实际裁剪边界是 `crops.json`。原生 `BitMap` 识别透明图集的九个部件边界，`Image.get_region()` 导出各方向独立 PNG；`build_view_rigs.gd` 在共享原生绑定/动画构建器上生成其余四套骨骼。

补绘部件用于验证动画方案，与当前序列帧存在耳形、表情和身体比例差异。走路为旧版程序制作的原生骨骼动作，不是35张序列帧的精确转换。「站立」是RESET静态姿势，没有呼吸或工作动作。五套方向覆盖八朝向；本版仅供预览，用户确认后再接入员工玩法。侧面拆图提示词记录在 `art_src/rabbit_walk/generation_prompts.md`。

## 重建与验证

从项目根目录执行，`godot` 可替换为本机 Godot 4.6 可执行文件路径：

```powershell
godot --headless --path . -s art_src/rabbit_walk/build_rig.gd -- --parts
godot --headless --path . -s art_src/rabbit_walk/build_view_rigs.gd -- --parts
godot --headless --editor --path . --import
godot --headless --path . -s art_src/rabbit_walk/build_rig.gd
godot --headless --path . -s art_src/rabbit_walk/build_view_rigs.gd
godot --headless --path . -s tests/test_rabbit_walk.gd
godot --headless --path . -s tests/test_rabbit_directions.gd
godot --headless --path . -s tests/test_skeletal_character_preview.gd
godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/render_skeletal_character_preview.gd
godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/render_rabbit_walk.gd
godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/render_rabbit_viewer.gd
```

重建脚本会覆盖对应方向的 PNG、生成的 `rabbit_*.tscn`、`motions/*.tres`。如果在编辑器手工调整过绑定或动画，请先保留该版本再重建。重建后的场景继续引用外部动作库。

本轮结果与实际GPU截图见 `docs/qa/skeletal-character-preview.md`。以下旧验证记录描述 `f2edb7c` 的历史交付，不代表本轮重新生成了所有历史截图或更改了游戏字体。

骨骼测试覆盖支撑脚接地、交替抬脚、所有关节的循环闭合、耳尖独立弯曲及权重完整性。渲染脚本以真实鼠标输入检查预览控件，并比较相同姿态下柔性/刚性耳朵的实际 GPU 图像；截图在 `docs/qa/rabbit-walk.png`，32 帧序列在忽略目录 `.godot/rabbit_walk_frames/`。

`docs/qa/rabbit-walk.gif` 来自这组实际 Godot 渲染帧，通过 FFmpeg 编码循环。帧率为 40 fps；GIF 的 10ms 时间精度使总长约 0.81 秒。

新版界面截图是 `docs/qa/rabbit-animation-viewer.png`，八方向同一时刻对照是 `docs/qa/rabbit-eight-directions.png`，切换方向的实际引擎动图是 `docs/qa/rabbit-angle-viewer.gif`。128 帧序列保存于忽略目录 `.godot/rabbit_viewer_frames/`，以 20 fps 编码，展示每个方向的一个完整走路周期。

本次验证环境：Godot **4.6.3**，Windows，NVIDIA RTX 3060，OpenGL Compatibility 渲染。独立预览使用项目当前默认 Mobile 渲染时也可启动；完整的自动渲染断言以 Compatibility 为准。

新增文案按现有 `art_src/graybox/subset_font.py` 流程，从原版 WenQuanYi Micro Hei 字体重新裁剪到 `art/ui/graybox_font.ttf`；未更换字体设计。原有 122 个回归用例全部通过。原有故意触发的存档失败警告及退出时资源清理警告仍存在。
