extends RefCounted
## Optional bounded diagnostics. No callbacks, business decisions or saved data.
const LIMIT := 20000
var _events: Array = []
var _overflow := false
func record(operation: String, facts: Dictionary = {}) -> void:
	if _events.size()>=LIMIT: _overflow = true; return
	_events.append({"operation":operation,"facts":facts.duplicate(true)})
func take() -> Dictionary:
	var result := {"events":_events,"overflow":_overflow}
	_events = []; _overflow = false
	return result
