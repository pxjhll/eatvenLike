class_name SpecFlyer
extends Resource
## 发传单（§3.2）：免费，只有冷却。一波人数、冷却由传单升级轨的效果决定。

## wave_seconds > 0：一波人在这么多秒内均匀入场；否则每 gap 秒进一位
@export var wave_seconds: float = 0.0
@export var gap: float = 0.0
## 队满时：wait_outside（在店外等，有位置再进）/ lost（计流失）
@export var when_full: String = "wait_outside"
@export var track: SpecUpgradeTrack
