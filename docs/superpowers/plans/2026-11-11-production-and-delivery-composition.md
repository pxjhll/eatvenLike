# T07 生产依赖与交付组合 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans sequentially. 不创建worktree、其他聊天或代理。

**Goal:** 提取既有材料依赖规则，验证线性/并行合流；通过T06原子动作组合实现多取餐点的整单交付，未启用的店铺保持原流程。

**Architecture:** ProductionPlan读取SpecStep.consumes/produces构建可校验的依赖图，沿用unit.done和goods账本。flow_version=1显式开启严格图与可选order交付批次；BundleDelivery预留订单现有实物，BundleActionContext只用move/pickup/transport/drop组合，最终事务一次提交整批送达和结账。没有第二份库存、生产脚本语言或正式新菜单。

**Tech Stack:** Godot4.6.3 / GDScript / Resource / Dictionary / PowerShell。

**Spec:** docs/superpowers/specs/2026-11-11-modular-shop-system.md。

## Global Constraints

- 从本轮已提交7eaab3c继续；工作目录D:/Tes/eatventure。本次不推送，也不自动提交T07。
- 保留26项用户文件和7项冻结数据。正式shop.tres、PNG、员工基础数值、价格、奖励不改。
- 所有运行用隔离APPDATA：_work/shop_modularity/phase-c/userdata/<runner>；证据留在_work。
- T07只增加能力和数据夹具；例汤/主菜为现有内容的测试组合，不扩充正式菜单或美术。
- 旧flow_version=0不新增状态字段，不改变旧serve的逐件送餐或顾客整单自取。
- 预留和携带始终对应原goods.id。无路、缺料、缺一份餐或容量不足时等待，不复制/丢弃物品或静默改回逐件送餐。
- 新执行器仍消费T05的规则位置与T06生命周期；表现不推进交付。

## 文件和接口

- 新增game/rules/production_plan.gd：compile(shop,dish_id)->Dictionary{nodes,order,producers,errors,signature}；work_steps/producer/blocked_inputs复用原语义。严格图拒绝缺输入、重复生产者、环、不能形成最终成品和工作产量不足。
- SpecFulfillment新增flow_version=0，delivery_batch="item"，delivery_points:Dictionary[String,String]={}。flow1仅serve；order批次要求seat_wait、动作1和运动1。逐菜取餐点只在order批次启用，值必须是已配置pickup工位；多pickup仅flow1允许。
- flow1允许按依赖解释工序而非依赖数组顺序；保存仍用原索引，并给新unit记录flow_version=1和recipe_signature。已有签名与当前图不符或未来流程版本时保护原文件。首次采用旧档必须保持原工序索引语义，缺签名的合法旧unit补当前签名，不重做工序。
- 新增game/rules/bundle_delivery.gd：candidates/claim/commit/cancel/validate_job。一个job持有一个订单待送单位的goods列表及原位置、capacity和bundle_version=1；预留整批前检查全部实物、归属、空闲和员工容量。
- 新增game/rules/bundle_action_context.gd：继承ActionContext；生成首站move→pickup→后续站transport→pickup→座位transport→整批drop。lease.scope="bundle"，只引用原job/goods，不保存对象。
- job基础字段沿用ServeFlow._job，kind="bundle"，增加order、goods:[{id,from}]、capacity、bundle_version。所有步骤和lease都可保存。worker.carry_count为已拿件数，carry_item为第一件的图示；账本中每件实物仍单独在hand:<员工>。
- 预留时冻结此次允许容量，之后临时加成到期不丢弃已携带物。容量不足不领取该整单；不拆分成多次交付。
- 最终drop先把全部goods移到seat、释放预留、清任务，提交每个unit的送达、整单支付和开吃事实，再广播各事件。取消将手中物品放回各自原位置，释放所有未取/已取预留。
- 新增game/rules/flow_validator.gd检查unit图签名与bundle引用、动作游标/目标/实物/预留一致性；ActionValidator按lease.scope分派。ShopSave先保护未来版本和变更图，再考虑旧档迁移备份。
- ShopView按flow1提供脱离的图/交付状态；普通角色仍使用carry_count显示数量，不新增正式图像或UI功能。

## Task 1：提取和验证生产图

- [x] 写tests/test_flow_composition.gd及独立专项入口，先用缺模块的存在性断言确认红灯。
- [x] 线性图和两路合流使用手工期望：两个独立节点都能就绪，合流只在两路完成后就绪。缺输入/重复生产者/环和输出不足需明确报错。
- [x] 实现ProductionPlan，把ServeFlow原producer/work_steps/依赖完成判断委托给它；flag0运算和迭代顺序不变。
- [x] 加flow配置、指纹默认值忽略和v1图校验；不重录奶茶基线。数据夹具使用现有资源深拷贝添加并行生产节点，正式资源不改。

## Task 2：整单实物与顺序交付

- [x] 新建tests/fixtures/flow_shop.gd：T05受控几何、T06动作1、现有主菜与例汤、两个pickup端口，员工测试容量2；仅测试资源副本。
- [x] 写真实规则红灯：两件实物依次拿起、到座位才整批交付；缺一份餐或容量1不能领取；两个员工不能重复预留同一订单。
- [x] 实现BundleDelivery和BundleActionContext；ServeFlow只按配置选择逐件或整单，生产依赖与原实物仍共用。按菜配置的取餐点也用于出餐搬运目标。
- [x] 验证半途取消、缺餐、阻路恢复、多个单位、不同取餐点、容量不足和加成到期。取消后每个ID只出现一次，已送订单只结账一次。

## Task 3：存档、表现和阶段出口

- [x] 每个pickup/transport/drop和阻路阶段独立保存续跑一致；事件回调看到整批已提交，不能只记一半。旧档补图签名，未来版本与改图档保留原文件，第一次替换有原字节备份。
- [x] 图和交付读模型可修改而不影响规则；真实角色显示两件数量且不改规则。将专项与表现入口加入CI。
- [x] 运行全量规则（奶茶冻结轨迹）、T05/T06显示、三店原UI、尺度和四店配置/空间检查，扫描错误和资源泄漏。
- [x] 更新docs/qa/production-and-delivery-composition.md、接入说明、总表、T08前置接口；核对用户文件/冻结哈希与git diff --check。

数据夹具只能用已实现能力和现有物品。新增条件由专门上下文承担，不扩充RuleActions为配方解释器。

## 完成记录

T07已在本地完成：20项专项、444项规则、47项真实角色交付显示通过；T05/T06、三店原UI、角色尺度与配置/布局回归通过。资源导入无错误，26项用户文件和7项冻结数据哈希不变。T06提交7eaab3c未推送，T07未提交；下一项T08。详见docs/qa/production-and-delivery-composition.md。
