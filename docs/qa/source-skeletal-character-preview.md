# 新版帧素材骨骼预览 — 2026-10-30

入口：`presentation/rabbit_skeleton/preview.tscn`。本次交付仅为独立预览，游戏和帧动画入口保持原状。

## 来源与范围

- 角色美术采用 `complete_atlases/` 中五张完整部件图集。右前图集逐字节使用用户提供的PNG（SHA256 `7cb88cf990529f129329ced9df83b8192344159eafaaa8359c4e0ff4387437e6`），其他四方向以内置imagegen参考当前新版帧图与认可的部件图补绘。提示词和原图保存在同目录。
- 每个方向导出九个带完整轮廓的独立部件，运行时只引用 `art/rabbit_skeleton/complete/`；完整头部不挖表情窗口，当前不切换原帧眼睛贴片。原始35张PNG只用于动作测量与左侧对照。
- 七个姿势通过原图数值拟合生成真实Bone2D位置和旋转轨道，不采用比例变化，并保留各方向0.79/0.96/1.00/0.88/0.75秒周期和不等帧时长。
- 按用户最新要求，完整部件Sprite2D直接挂到Bone2D下，固定等比绑定尺寸，动作只平移和旋转；整图Surface及硬切部件均不参与显示。少量拼接接缝保留给用户微调。
- 杯子按角色局部固定位置显示；勺子跟随实际手部Grip节点。参数只属于预览，没有接入员工玩法。

## 验证

环境：Godot 4.6.3，Windows，NVIDIA RTX 3060。自动GPU检查使用OpenGL Compatibility；实际预览启动使用项目的Mobile渲染设置。

- `tests/test_source_skeletal_rabbit.gd`：0失败。覆盖五个来源方向、七个姿势、原始周期、用户认可图集哈希、完整部件资源路径和元数据、实际骨骼Sprite绑定、走路过程中宽高恒定且无剪切、完整头部保持、固定杯子、工具挂点、镜像与不等周期转向相位。
- `tests/render_source_skeletal_rabbit.gd`：0失败。真实鼠标输入检查播放、方向、骨骼显示、共享动作、尺寸同步、固定物品与工具；验证从1秒动作90%处转向0.79秒动作后保持0.711秒位置和播放状态，左向对照同步镜像。
- `tests/test_rabbit_frame_atlas.gd`、`tests/test_rabbit_game_visuals.gd`：均0失败，原有帧动画资源、35张源帧像素与游戏显示行为保留。
- `tests/run_all.gd`：130用例，0失败。现有故意触发的存档失败警告、Canvas/ObjectDB资源清理提示仍存在。
- 独立代码复核发现并修复时间轴范围变更导致暂停/进度跳变、原帧对照未镜像两处问题，均有实际输入回归覆盖。

## 实际渲染产物

- `source-skeletal-preview.png`：新版兔子独立预览。
- `source-skeletal-cup.png`：固定位置杯子。
- `source-skeletal-tool.png`：跟随手部的勺子。
- `source-skeletal-35-pose-comparison.png`：五行七组，每组左为原帧、右为原生骨骼拟合。
- `source-skeletal-preview.gif`：96帧实际Godot渲染，依次演示无物品、杯子、工具；GIF只用于展示，运行时使用原生骨骼。

初期恢复的旧版试作还保存在 `presentation/rabbit_walk/` 等目录；本次有效入口是 `presentation/rabbit_skeleton/preview.tscn`，不引用旧兔子的美术或走路曲线。
