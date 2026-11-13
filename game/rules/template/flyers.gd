extends RefCounted
## Optional campaign cadence/cooldown only. Service owns admission/loss and the
## outer rules own modifiers/RNG; this component never creates a customer.
const Inventory := preload("res://game/rules/template/inventory.gd")
const MAX_COUNT := 9007199254740991
var _definition: Dictionary
var _state := {"version":1,"pending":0,"elapsed":0.0,"cooldown":0.0,"wave_left":0.0,"first":false}

func _init(definition: Dictionary) -> void:
	_definition = definition.duplicate(true)

static func compile(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return _error("invalid flyer capability")
	if raw.is_empty(): return {"definition":{},"error":""}
	var pattern: Variant = raw.get("pattern","gap")
	if pattern not in ["gap","spread"]: return _error("unsupported flyer pattern")
	var allowed := ["pattern","count","cooldown","when_full"]
	allowed.append_array(["gap","first_delay"] if pattern=="gap" else ["seconds"])
	for key in raw:
		if key not in allowed: return _error("unused or unsupported flyer parameter: "+str(key))
	var result := {"pattern":pattern,"count":raw.get("count",4),"cooldown":raw.get("cooldown",120.0),"when_full":raw.get("when_full","wait_outside")}
	if not result.count is int or result.count<1 or result.count>MAX_COUNT or result.when_full not in ["lost","wait_outside"]: return _error("invalid flyer count or full-queue policy")
	if not _seconds(result.cooldown): return _error("invalid flyer cooldown")
	result.cooldown = float(result.cooldown)
	var field := "gap" if pattern=="gap" else "seconds"
	if not _seconds(raw.get(field)) or raw[field]<=0.0: return _error("flyer cadence must be positive")
	result[field] = float(raw[field])
	if pattern=="gap":
		if not _seconds(raw.get("first_delay",0.0)): return _error("invalid first flyer delay")
		result.first_delay = float(raw.get("first_delay",0.0))
	return {"definition":result,"error":""}

func values(mods: RefCounted) -> Dictionary:
	var count: float = mods.value("flyer_customers",float(_definition.count))
	var cooldown: float = mods.value("flyer_cooldown",float(_definition.cooldown))
	if not is_finite(count) or count<1.0 or count>float(MAX_COUNT) or count!=floorf(count): return {"error":"effective flyer count must be a positive bounded whole number"}
	if not is_finite(cooldown) or cooldown<0.0: return {"error":"invalid effective flyer cooldown"}
	return {"error":"","count":int(count),"cooldown":cooldown}

func send(open: bool, mods: RefCounted) -> String:
	if not open: return "service closed"
	var effective := values(mods)
	if not effective.error.is_empty(): return effective.error
	if _state.wave_left>0.0: return "flyer wave active"
	if _state.cooldown>0.0: return "flyer cooldown"
	if _state.pending>MAX_COUNT-int(effective.count): return "pending flyer count exceeds supported range"
	_state.pending += int(effective.count)
	_state.elapsed = 0.0
	_state.first = _definition.pattern=="gap"
	_state.cooldown = float(effective.cooldown)
	_state.wave_left = float(_definition.seconds) if _definition.pattern=="spread" else 0.0
	return ""

func enqueue(count: int) -> String:
	if count<1 or count>MAX_COUNT or _state.pending>MAX_COUNT-count: return "pending flyer count exceeds supported range"
	_state.pending += count
	_state.elapsed = 0.0
	_state.first = _definition.pattern=="gap"
	if _definition.pattern=="spread": _state.wave_left = float(_definition.seconds)
	return ""

func advance(dt: float, open: bool) -> String:
	if not is_finite(dt) or dt<0.0: return "invalid flyer time"
	var elapsed: float = _state.elapsed+dt if open and _state.pending>0 else _state.elapsed
	if not is_finite(elapsed): return "flyer elapsed time overflow"
	_state.elapsed = elapsed
	_state.cooldown = maxf(0.0,float(_state.cooldown)-dt)
	_state.wave_left = maxf(0.0,float(_state.wave_left)-dt)
	if _state.cooldown<0.00000001: _state.cooldown = 0.0
	if _state.wave_left<0.00000001: _state.wave_left = 0.0
	return ""

func due(mods: RefCounted) -> bool:
	if _state.pending<1: return false
	var delay: float
	if _definition.pattern=="gap": delay = _definition.first_delay if _state.first else _definition.gap
	else: delay = float(_definition.seconds)/float(values(mods).count)
	return float(_state.elapsed)+0.00000001>=delay

func waits_outside() -> bool:
	return _definition.when_full=="wait_outside"

func consume() -> void:
	_state.pending -= 1
	_state.elapsed = 0.0
	_state.first = false

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func restore(data: Variant, refresh_numeric := false) -> String:
	if not Inventory._shape(data,{"version":0,"pending":0,"elapsed":0.0,"cooldown":0.0,"wave_left":0.0,"first":false}) or data.version!=1: return "invalid flyer state shape"
	if data.pending<0 or data.pending>MAX_COUNT: return "invalid pending flyer count"
	for key in ["elapsed","cooldown","wave_left"]:
		if not is_finite(data[key]) or data[key]<0.0: return "invalid flyer clock"
	if data.pending==0 and (data.elapsed!=0.0 or data.first): return "empty flyer queue has a cadence"
	if _definition.pattern=="gap" and data.wave_left!=0.0: return "gap flyer has an unrelated spread clock"
	if _definition.pattern=="spread" and (data.first or (not refresh_numeric and data.wave_left>float(_definition.seconds))): return "invalid spread wave progress"
	_state = data.duplicate(true)
	# A numeric revision may shorten the remaining campaign window, but never
	# discards queued customers, elapsed cadence or the committed cooldown.
	if refresh_numeric and _definition.pattern=="spread": _state.wave_left = minf(float(_state.wave_left),float(_definition.seconds))
	return ""

static func _seconds(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value>=0.0

static func _error(message: String) -> Dictionary:
	return {"definition":{},"error":message}
