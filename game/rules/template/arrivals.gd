extends RefCounted
## Public arrival clock and menu requests. Business service owns admission/loss;
## the outer session owns RNG state. Disabled templates never instantiate this.
const Inventory := preload("res://game/rules/template/inventory.gd")
const Contract := preload("res://game/rules/shop_content_contract.gd")
const Sampling := preload("res://game/rules/rule_sampling.gd")
const DEFAULTS := {"pattern":"fixed", "interval":10.0, "first_delay":2.0, "opening":0, "choices":[]}
var _definition: Dictionary
var _state: Dictionary

func _init(definition: Dictionary) -> void:
	_definition = definition.duplicate(true)
	_state = {"version":1, "signature":Contract._canonical(definition).sha256_text(),
		"open":false, "started":false, "left":float(definition.first_delay), "attempts":0}

static func compile(raw: Dictionary, menu: Dictionary, capacity: int = -1, selected_menu := false) -> Dictionary:
	if raw.is_empty(): return {"definition":{}, "error":""}
	if selected_menu and raw.has("interval"): return _error("stage menu selection owns arrival intervals")
	var result := DEFAULTS.duplicate(true)
	for key in raw:
		if not result.has(key): return _error("unsupported arrival parameter: " + str(key))
		result[key] = raw[key].duplicate(true) if raw[key] is Array or raw[key] is Dictionary else raw[key]
	if result.pattern not in ["fixed", "exponential"]: return _error("unsupported arrival pattern")
	for key in ["interval", "first_delay"]:
		if not (result[key] is int or result[key] is float) or not is_finite(float(result[key])) or result[key] < 0.0: return _error("invalid arrival duration")
		result[key] = float(result[key])
	if result.interval <= 0.0 or not result.opening is int or result.opening < 0: return _error("invalid arrival interval or opening wave")
	if not result.choices is Array or (result.choices.is_empty() and not selected_menu): return _error("missing arrival menu choices")
	if selected_menu and not result.choices.is_empty(): return _error("arrival choices conflict with dynamic menu selection")
	var total_weight := 0.0
	for choice in result.choices:
		if not choice is Dictionary or choice.size() != 2 or not choice.get("request") is Array or choice.request.is_empty(): return _error("invalid arrival menu choice")
		var weight: Variant = choice.get("weight")
		if not (weight is int or weight is float) or not is_finite(float(weight)) or weight <= 0.0: return _error("invalid arrival menu weight")
		choice.weight = float(weight)
		total_weight += float(weight)
		var count := 0
		for row in choice.request:
			if not Inventory._shape(row, {"dish":"", "qty":0}) or row.qty < 1 or not menu.has(row.dish): return _error("invalid arrival menu request")
			count += int(row.qty)
		if capacity > 0 and count > capacity: return _error("arrival order exceeds whole pickup capacity")
	if not is_finite(total_weight): return _error("invalid total arrival menu weight")
	return {"definition":result, "error":""}

func set_open(value: bool) -> int:
	_state.open = value
	if not value or _state.started: return 0
	_state.started = true
	_state.attempts += int(_definition.opening)
	return int(_definition.opening)

func advance(dt: float) -> String:
	if not is_finite(dt) or dt < 0.0: return "invalid arrival time"
	if _state.open: _state.left -= dt
	return ""

func due() -> bool:
	return _state.open and float(_state.left) <= 0.000001

func schedule_next(mean: float, rng: RandomNumberGenerator) -> String:
	if not due() or not is_finite(mean) or mean <= 0.0: return "invalid next arrival interval"
	_state.left += Sampling.interval(_definition.pattern, mean, rng)
	_state.attempts += 1
	return ""

func request(rng: RandomNumberGenerator) -> Array:
	var weights := {}
	for index in _definition.choices.size(): weights[str(index)] = float(_definition.choices[index].weight)
	var selected := int(Sampling.choose(weights, rng))
	return _definition.choices[selected].request.duplicate(true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func restore(data: Dictionary) -> String:
	if not Inventory._shape(data, {"version":0, "signature":"", "open":false, "started":false, "left":0.0, "attempts":0}): return "invalid arrival clock shape"
	if data.version != 1 or data.signature != _state.signature or not is_finite(data.left) or data.attempts < 0 or (data.open and not data.started): return "invalid arrival clock or sequence"
	if not data.started and (data.attempts != 0 or data.left != float(_definition.first_delay)): return "unopened arrival clock has advanced"
	if data.started and data.attempts < int(_definition.opening): return "arrival opening wave is missing"
	_state = data.duplicate(true)
	return ""

static func _error(message: String) -> Dictionary:
	return {"definition":{}, "error":message}
