class_name SpecCity
extends Resource
## 城市（§3.14）：主题章节。城市机制 = 打开规则层某些参数或扩展的开关，进入后每家店继承。

@export var id: String = ""
@export var display_name: String = ""
## 地方风味
@export var theme: String = ""
@export var mechanics: Array[String] = []
@export var shops: Array[SpecCampaignShop] = []
## 这座城新加的一排永久加成（预留）
@export var perks: Array[SpecPerk] = []
## 这座城的奇遇（含店长回访，预留）
@export var events: Array[SpecEvent] = []
