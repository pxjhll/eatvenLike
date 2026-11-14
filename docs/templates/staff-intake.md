# 新增员工接入表

## 身份与共享基础值

员工定义放 `content/characters/staff/<id>.tres`，使用SpecStaffKind。各店引用同一资源，不能各自复制一份基础属性。ID保持稳定，显示名、类型和介绍可编辑。

| 基准档 | walk | work | carry | 原共享参考 |
|---|---:|---:|---:|---|
| 均衡 | 112 | 1 | 2 | cat / gray_cat |
| 速度 | 104 | 1 | 2 | rabbit |
| 力量 | 88 | 1 | 3 | raccoon / bear |
| 操作 | 96 | 1.6 | 2 | fox |

不同员工可有明确的全局差异；不能为了某家店过关而给同一员工私设初始速度。实际值由全局基础值、培养和事件加成计算，原生场景密度只换算一次。

示例 `hamster.tres` 将已有仓鼠动画接入为员工，选择104/1/2。公共示例 `content/examples/onboarding/table.tres` 与 `self_pickup.tres` 直接引用它和全局squirrel，未增加角色控制分支，也未制作新人物图片。

## 动作与资源映射表

| 项目 | 仓鼠示例 | 新员工填写/检查 |
|---|---|---|
| 员工ID / 美术键 | hamster | 规则kind与资源注册键一致 |
| 全局属性 | content/characters/staff/hamster.tres | 按共享档选择并登记 |
| SpriteFrames | art/hamster_actions/hamster_actions_frames.tres | 只声明实际存在的clip |
| 帧场景 | presentation/characters/hamster.tscn | 使用现有方向/播放接口 |
| 头像 | character_library.portrait(hamster) | 来自真实帧/图片，不套用其他名册项 |
| walk | walk_right，方向按已有最近视角规则 | 校验前后左右及镜像 |
| idle | idle_back_right | 待机可用 |
| sit | sit_front_right | 顾客/坐姿用途可用 |
| work | 无独立clip，已有控制器保持idle | 若要求专门工作动画，先补齐真实资源再登记 |
| carry | 已有携物附件+走路 | 验证物品和数量，不把食物烘进人物 |
| 尺度 | 128员工 / 110顾客 | 不修改某店身高元数据 |

已有注册动画转为员工时只新增SpecStaffKind并接入店铺名册。全新造型还需在 `presentation/characters/character_library.gd` 的资源数据表注册名称、SpriteFrames/场景、头像和帧原生高度；这是视觉资源登记，不新增按店铺或员工ID分叉的业务控制逻辑。只有出现已有控制接口不能表达的能力时，才单独扩展公共能力及兼容测试。

## 店铺与验收

- 店铺的staff.kinds直接引用全局资源；starting/starting_posts、hire_pool/hire_order只安排可用性和岗位。
- 所有声明岗位都能走到Work/Post；carry容量满足声明的整单件数。
- 真场景检查头像、员工名称、走路、工作或明确的回退姿势、携物与朝向；不能把回退显示称为新工作动画。
- 真实接单/制作/交付至少一单；中途召回验证库存补偿及重新上岗；保存重开后继续。
- 同视口比较员工和顾客尺度，暂停及1/2/4倍速消费同一规则位置。

U07新增 `content/characters/staff/squirrel.tres`，使用112/1/2均衡档与已有松鼠视觉；两份公共示例直接引用同一个资源。员工ID、基础属性、头像/动作资源都是全局定义，正式校验会拒绝店铺内复制的员工资源。

公共样例入口：`tests/test_template_onboarding.gd`、`tests/render_template_authoring.gd` 与 `tools/validate_template_shops.gd`。同一松鼠员工在送桌/自取两组合里真实工作、拿取、取消和重新部署，并通过普通ShopSave续档。历史 `test_shop_onboarding` 保留旧协议断言；不作为新店制作入口。新示例不会自动加入正式关卡。
