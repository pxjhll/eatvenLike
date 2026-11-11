# 共享员工定义

`content/characters/staff/<id>.tres`使用已有的`SpecStaffKind`类型，逐字段提取自奶茶店原定义。奶茶店通过`staff.kinds`按原顺序引用这些资源。

| ID | walk（逻辑单位/秒） | work | carry |
|---|---:|---:|---:|
| cat | 112 | 1 | 2 |
| raccoon | 88 | 1 | 3 |
| fox | 96 | 1.6 | 2 |
| rabbit | 104 | 1 | 2 |
| gray_cat | 112 | 1 | 2 |
| bear | 88 | 1 | 3 |

店铺继续配置招募顺序、价格、开局名册、部署和岗位，基础角色定义由共享资源提供。已有显示名称、角色说明和种类ID保持原值，本次不顺带改名。

共享Resource是定义，不能当作某个员工的运行状态修改。现有`WorkerState.create`为每个员工复制stats；升级和临时效果仍由加成栈计算，不写回共享Resource。

需要编辑一份店铺变体时，使用`SpecShop.copy_for_editing() -> Resource`，调用处可写`var variant: SpecShop = original.copy_for_editing()`。它调用`duplicate_deep(Resource.DEEP_DUPLICATE_ALL)`，连外部员工定义一并隔离。Godot默认的`duplicate(true)`保留外部Resource引用，不能用于修改共享员工属性的变体；现有数值刷新和存档兼容测试已改用显式复制入口。普通运行继续直接引用不可变共享定义，不为每个会话复制所有资源。

本阶段仅迁移奶茶店。煎饼摊、第三店及未在奶茶店出现的员工将在任务T09/T10中接入全局基准，其现有定义暂不改变。当前提取不意味着全项目的角色大小、运动和动作已经统一。

兼容验证由`tests/test_tea_modularity_baseline.gd`、`tests/test_shared_staff.gd`及`tests/test_content_save.gd`覆盖。基线与旧档样本来自重构前的9bc1b20；提取后原奶茶店的内容指纹和确定性轨迹应一致。
