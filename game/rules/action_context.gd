extends RefCounted
## Runtime-only boundary. Implementations own reservations and business effects;
## they must never be stored in worker.action. reserve is atomic; commit must
## finish its validated transaction, including releasing a terminal lease.

func reserve(_worker: Dictionary, _steps: Array) -> Dictionary:
	return {"error":"action context is not configured","lease":{}}

func ready(_worker: Dictionary, _step: Dictionary) -> String:
	return "action context is not configured"

func enter(_worker: Dictionary, _step: Dictionary) -> void:
	pass

func advance(_worker: Dictionary, _step: Dictionary, _dt: float) -> bool:
	return false

func commit(_worker: Dictionary, _step: Dictionary) -> void:
	pass

func cancel(_worker: Dictionary, _lease: Dictionary) -> void:
	pass
