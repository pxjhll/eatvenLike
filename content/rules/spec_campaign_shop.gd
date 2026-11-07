class_name SpecCampaignShop
extends Resource
## 关卡表里的一家店：引用自己的 shop.tres，目标时长供机器人校准对照（规则层不读）。

@export var id: String = ""
@export var display_name: String = ""
## 店铺数据路径；空 = 还没做
@export_file("*.tres") var shop_path: String = ""
@export var target_minutes: float = 0.0
