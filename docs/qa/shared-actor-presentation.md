# T04 共享角色尺度与表现验收

日期：2026-11-11。接续已推送的A阶段提交`9fd08aa`，工作分支`codex/tea-baseline-shared-staff`。

## 本次完成

新增`content/characters/actor_presentation.tres`作为全局角色表现配置：参考宽720、员工逻辑高128、顾客110、顾客基础视图走速170、横屏最低逻辑可见高1100。

三家店保留原生美术坐标和原PNG尺寸。原生宽度除以720得到场景单位倍率；角色根节点整体使用该倍率，身体、气泡、携带物、阴影、选择标记随角色一起变化，相机换算抵消原生像素密度。UI仍按既有720宽适配。

奶茶、煎饼摊和面馆夹具的场景角色大小/速度覆盖已移除，场景契约会拒绝重新添加这些字段。第三店原来没有这些字段，直接使用公共配置。堂食角色、世界物品、拖拽影子、命中框和抓取偏移采用同一单位倍率；放置物和手持物按同一长边尺寸换算。

当前适配沿用已有竖屏满宽模型：原生画布宽度表示素材坐标密度，逻辑参考店宽为720。真正增加横向逻辑空间需要独立相机能力，不用修改某一家店的角色大小来实现。

## 验证结果

本地引擎Godot4.6.3，所有会话使用隔离APPDATA。

| 检查 | 结果 | 工作区日志 |
|---|---|---|
| 全量规则 | 386用例，0失败 | phase-b/full.log |
| 新表现配置、场景契约、原奶茶轨迹 | 11用例，0失败 | phase-b/t04-green.log |
| 正式场景三店×两种窗口 | 76检查，0失败 | phase-b/t04-real-scenes-fixed.log |
| 同上含6张实拍 | 82检查，0失败 | phase-b/capture.log |
| 奶茶界面 | 84检查，0失败 | phase-b/tea-gui.log |
| 煎饼摊界面 | 88检查，0失败 | phase-b/pancake-gui.log |
| 第三店界面 | 33检查，0失败 | phase-b/stirfry-gui.log |
| 生产三店及面馆夹具 | 4店通过 | phase-b/authoring.log |
| 原空间导出 | 奶茶、煎饼摊一致；第三店仍无Nav | phase-b/layout.log |

上述日志都在`_work/shop_modularity/`下。完整规则与GUI日志没有运行错误或退出资源泄漏。跨店表现检查已加入现有CI；远端Godot4.7 CI尚未运行。

## 实拍测量

同一只兔子分别通过员工和顾客工厂创建，根节点位置使用对应场景单位。测量包含AnimatedSprite2D的当前帧矩形，不把透明边距误认为角色实际墨迹高度；逻辑高度仍是128/110。

| 窗口 | 奶茶/煎饼/小炒员工兔子帧矩形高 | 三店顾客兔子帧矩形高 |
|---|---:|---:|
| 720×1280 | 三者均143.7193px | 三者均123.5088px |
| 1280×720 | 三者均94.0708px | 三者均80.8421px |

完整测量：`_work/shop_modularity/phase-b/actor-measurements.json`。六张图是正式场景中的员工/顾客参考兔子，不是新增营业员工或正式游戏资产。

重新按A阶段已打开的奶茶店、固定12秒、相同窗口和渲染方式采样，720×1280和1280×720两张图与改造前原图逐像素相同。原图未覆盖；对比记录在`phase-b/tea-reference-comparison.json`，新图在`phase-b/tea-reference/`。

## 边界

本阶段没有改员工基础stats、菜谱、收益、库存、导航或规则运动状态。其他店的员工初始属性和第三店穿物问题仍按后续T05/T09/T10处理；顾客视图已使用统一逻辑速度，但权威抵达状态归T05统一，不能把本阶段报告为完整行为系统已完成。

A阶段原奶茶内容指纹、完整状态/事件轨迹与合成旧档继续通过。其他店shop.tres保持原样，现有用户改动保留。T04按用户指令单独提交，本次不推送；与已经发布的A阶段分开交付。

## 重复验证

```powershell
$env:APPDATA = 'D:/Tes/eatventure/_work/shop_modularity/phase-b/session-lifecycle-userdata/recheck'
$engine = 'D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe'
& $engine --headless --path 'D:/Tes/eatventure' -s tests/run_all.gd
& $engine --headless --path 'D:/Tes/eatventure' -s tests/render_actor_presentation.gd
& $engine --headless --path 'D:/Tes/eatventure' -s tools/validate_shops.gd
```

实拍时移除`--headless`，传`--rendering-method gl_compatibility --audio-driver Dummy`并在脚本参数后加`-- --capture`；后台运行需隐藏窗口。所有图片与数据留在_work，不进入Git。
