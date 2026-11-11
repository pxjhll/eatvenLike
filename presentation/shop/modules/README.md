# 可编辑店铺模块

这里提供制作阶段的可复用灰盒。正式美术可替换Visual子树；模块根、本地Anchors和Nav负责空间，不配置角色数值、配方或经济规则。

## 制作一间店

1. 在Godot中打开ShopTemplate.tscn，另存为新店的美术场景。保留Anchors、Anchors/Nav和Sortables；角色父链保持单位变换。
2. 在Sortables下实例化station.tscn、counter.tscn、table.tscn、entrance_queue.tscn、space.tscn。一个场景只保留一套全局入口/队列绑定和必要空间区域。
3. 为每个实例设置唯一module_id。工位/柜台的station_id必须引用SpecShop.stations中的稳定ID；桌椅设置seat_group、first_seat、table_index、seats_per_table和seat_purpose。
4. 需要调整内部结构时打开实例的Editable Children。以模块根的平移摆放家具；修改本地Nav端口和Footprints贴合美术。允许缩放Visual中的图像，模块根与空间父链只支持平移。
5. space的Nav/Areas和Nav/Access编辑总体可走区域和角色权限。区域是像素AnchorRect，平移后必须按cell整格对齐；Footprints是实际像素矩形，可以不对齐网格。
6. 编辑SpecShop的设备、配方、解锁和员工引用；scene_path指向刚保存的场景。不按场景复制基础角色值。
7. 用sync工具显式导出这间店的layout，再运行check与配置校验。场景和数据不一致会阻止运行；运行时不静默改坐标。

默认将家具模块直接放在Sortables下，模块原点是排序脚点。若额外添加分组Node2D，应开启分组的y_sort_enabled，让内部家具继续与角色按脚点排序；不要将一整组家具当作单个排序物件。

```powershell
$env:APPDATA = 'D:/Tes/eatventure/_work/shop_modularity/phase-d/userdata/authoring'
$engine = 'D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe'
& $engine --headless --path 'D:/Tes/eatventure' -s tools/sync_shop_layouts.gd -- --shop=res://content/shops/your_shop/shop.tres
& $engine --headless --path 'D:/Tes/eatventure' -s tools/sync_shop_layouts.gd -- --check --shop=res://content/shops/your_shop/shop.tres
```

示例路径需替换成实际店铺。省略目标时仍处理正式campaign；制作新店时使用--shop，避免处理其他店。--campaign可指定独立关卡表；它与--shop互斥，空目标和未知参数会报错。已知校验错误出现时，不写任何候选店铺；磁盘保存错误仍逐文件报告，不承诺跨文件磁盘事务。

## 本地节点与导出

| 模块 | 本地节点 | 对应原锚点/规则字段 |
|---|---|---|
| station、counter | Anchors/Station/Tap、Frame、Post、PostPoint、Badge、Buffer、Put | Stations/<station_id>/同名节点 |
| station、counter | Anchors/Drop | Drops/<module_id>，默认post为station_id |
| station、counter | Nav/Work、Nav/Post | layout.points[station_id]、posts[station_id] |
| counter | Anchors/Counter/Sale、Pickup、Dining | Counter/同名节点 |
| table | Anchors/Table | Tables/<seat_group>/<table_index> |
| table | Anchors/Seats/0… | Seats/<seat_group>/<first_seat+n>，坐姿表现点 |
| table | Nav/Seats/0… | points[<group>/<n>]和customer_points[seat:<group>/<n>]；wait用途使用wait:前缀 |
| entrance | Anchors/Entrance、Exit、Queue/0… | 原入口、出口、队列锚点；Queue同时导出customer_queue |
| entrance、space | Nav/Customers/entrance、exit、pickup | customer_points中的对应端口 |
| space | Anchors下的全局锚点 | 原路径，如Chips/Seats |
| 任意模块 | Nav/Points/<name>、Posts/<name> | 全局命名员工点和岗位点 |
| 任意模块 | Nav/Footprints/0… | obstacles及对应解锁station引用 |
| 任意模块 | Nav/Areas/0…、Access/<profile>/0… | areas和actor_areas |

Tap/Frame/Post/Drop/Footprints/Areas/Access的矩形使用AnchorRect，位置是左上角。普通端口使用Node2D。固定组合美术不用为了模块化拆成每颗食材或每块建筑零件。

seats_per_table默认2，同时向现有餐盘显示导出per_table。first_seat必须是该容量的整数倍，table_index=first_seat/seats_per_table；组内所有桌子容量必须一致。本地座位从0连续编号，坐姿点和Nav接近点一一对应。可配置三座等变体，不改角色控制代码。Seats组的额外元数据可以在本地Anchors/Seats上设置；同组元数据冲突会拒绝。

工位Visual随已有station解锁显示。灰盒桌子预先摆放，Visual/Seats中的单把椅子按已购数量显示；整套家具占地始终预留。当前没有按购座数量动态撤销占地的语法，不能把隐藏的椅子空间当作开放通道。需要整桌随购买撤销碰撞的正式场景，应在迁移任务中明确扩展，不套用station ID绕过校验。

## 根空间与校验

Anchors.metadata/module_version=1显式启用模块投影，根位置为原点。Anchors/Nav需要nav="grid"、cell、grid_size、motion_version=1、motion_units；出生点spawn_point默认counter，aliases默认空。motion_units必须等于world_size.x/720。模板使用720×1200、cell40、18×30格和home出生点。

根Nav沿用旧Areas/Obstacles/Points/Posts，新增Access和Customers/Points。模块区域与根区域相加，完整导出清除旧layout中的同类数据，避免留下已删除模块的端口。aliases、spawn_point、版本、密度、权限、顾客端口和队列与原员工字段一起比较。

同名实物端口只允许一个所有者；多个模块可以向同一个只读组提供不同子节点。所有模块和空间坐标父链要求有限平移；占地和区域须在网格内。脚底半径沿用12逻辑单位。导出校验所有占地打开时员工从出生点到各端口、顾客从入口到各端口/队列的可达性；这提供保守的全部建成布局检查，不模拟经济阶段或角色之间的避让。

旧场景不声明module_version时仍读原Anchors/Nav。带模块却没有版本、未知版本、重复ID、错误设备/座位引用、错元数据、不可达端口都会报错。ShopAnchors读取虚拟路径但引用原本地节点；不复制第二套锚点，不修改场景，不在表现层移动真实角色。

## 可执行样板

tests/fixtures/module_shop.gd使用已有主菜、例汤和员工配置的副本组装完整样板。它覆盖多点整单交付，不新增正式菜单；所有保存、截图和中间资源使用隔离用户目录或_work。

```powershell
& $engine --headless --path 'D:/Tes/eatventure' -s tests/run_all.gd
& $engine --headless --path 'D:/Tes/eatventure' -s tests/render_scene_modules.gd
```

本轮不更改正式三店布局，也不把制作时移动模块解释为运行中搬迁旧档角色。T09继续用这些端口和模块迁移第三店。正式美术仍先遵守docs/art/scene-art-production-rules.md，核对已有资产并在FigCraft确认。
