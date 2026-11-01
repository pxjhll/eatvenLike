# 新版帧素材对应的骨骼预览

入口：`preview.tscn`，在 Godot 4.6.3 中打开后按 F6。它是独立预览；游戏仍使用原来的帧动画。

## 素材和动作来源

当前角色美术使用**完整部件图集**。右前视角直接采用用户提供的3×3拆件图，文件哈希为 `7cb88cf990529f129329ced9df83b8192344159eafaaa8359c4e0ff4387437e6`；其他四个视角通过内置imagegen，参考对应的新版兔子帧图和用户认可的部件图补齐。原图及完整提示词保存在 `art_src/rabbit_skeleton/complete_atlases/`。

每张图集包含完整的头、两只耳、躯干、两只手、两只脚和尾巴，补全遮挡区域与闭合轮廓。导出器按透明背景中的独立完整部件提取PNG，不再从组装好的角色上沿水平线或区域硬切。运行时只引用 `art/rabbit_skeleton/complete/<方向>/`；`complete_manifest.json` 保存图集来源、哈希、部件边界和绑定位置。

动作由 `fit_source_motion.py` 测量各方向七张原帧的部件变化，导出 `source_fit.json`；Godot只采用其中的位置和旋转，忽略比例拟合，不给骨骼添加缩放动作。原始周期和不等帧时长保持：正面0.79秒、右前0.96秒、侧面1.00秒、右后0.88秒、背面0.75秒。左右镜像覆盖八方向，转向保持归一化相位。

骨骼是对原动作的近似拟合，并非逐像素复刻每张帧。完整部件的补绘与原帧存在少量比例、颜色和轮廓差异；预览左侧播放同步原帧，便于评估动作差异。原始35张帧图只作为动作参考，原帧动画流程保持原状。

## 绑定和显示

每套场景保存17根Bone2D。每个完整部件是对应骨骼下面名为 `Visual` 的独立Sprite2D。高分辨率部件在绑定时使用固定的等比显示尺寸；动作只平移、旋转骨骼，不动态缩放、不剪切、不做整图蒙皮。头部完整保留，不再挖出矩形表情区域；当前采用部件图中的睁眼表情，尚未添加新的完整闭眼头部变体。

正常拼接后仍有的少量接缝留给用户微调，不用蒙皮拉伸掩盖。修图入口为 `art/rabbit_skeleton/complete/<方向>/` 内的独立PNG；替换同名图片即可更新显示。调整图片画布大小或关节位置时，应同时修改场景里的Sprite位置或导出器的绑定配置。先保留编辑版本再运行重建工具，避免覆盖手工修改。

动作位于 `art/rabbit_skeleton/motions/`，同方向实例共享AnimationLibrary和Animation，播放时间与物品选择各自独立。游戏尺寸预览约128像素高。站立显示基准姿势，没有额外制作呼吸或工作动作。

## 物品与操作

- 杯子使用固定角色局部坐标，按朝向调整位置和遮挡，保持直立，不跟随摆臂。此处为预览参数，接入游戏后再对齐游戏实际杯子尺寸。
- 工具示例为勺子，跟随实际手部Grip节点的位置、角度与镜像。
- 支持八方向、走路/站立、播放/暂停、1/30秒步进、速度、时间轴、循环、骨骼显示、耳朵动作开关和显示缩放。Space播放/暂停，左右键切换方向。
- 预览专用字体来自旧试作的同源字体子集，许可沿用 `art/ui/font_license.txt`；现有游戏字体不变。

## 重建

### 可编辑拆件工程

- `art_src/rabbit_skeleton/photoshop/rabbit_parts_smartobjects.psd`：五个视角、45个独立嵌入式智能对象。
- `art_src/rabbit_skeleton/photoshop/rabbit_parts_with_bones.psd`：在每个视角组顶部加入可开关的骨骼参考层，共50个智能对象；参考图来自当前Godot骨架的静止姿势。
- 同目录提供对应的 `.pcraft` 工程，可以用PhotoCraft编辑。
- `bone_references/` 保存五个方向的透明骨架参考图、骨架叠加预览和关节坐标清单。

PSD和PhotoCraft工程属于美术源文件。修改智能对象后，需要重新导出对应部件PNG到 `art/rabbit_skeleton/complete/<方向>/`，Godot才会更新显示。

### 生成命令

在项目根目录执行。`godot`替换为本机Godot可执行文件；数值拟合需要Python、numpy、scipy、Pillow。

```powershell
godot --headless --path . -s art_src/rabbit_skeleton/build_native.gd -- --parts
godot --headless --editor --path . --import
godot --headless --path . -s art_src/rabbit_skeleton/build_native.gd
godot --headless --path . -s tests/test_source_skeletal_rabbit.gd
godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/render_source_skeletal_rabbit.gd
```

重建会覆盖本流程生成的完整部件PNG、动作和场景，编辑器手动调整后应先保留版本。`source_fit.json` 已保存当前动作测量结果；数值拟合脚本仅用于重新测量原始帧，不用于制作或替换完整部件美术。QA与对照图见 `docs/qa/source-skeletal-character-preview.md`。
