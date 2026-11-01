extends RefCounted
## Minimal assertions shared by the current shop regression suites.

var failures: PackedStringArray = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [message, var_to_str(expected), var_to_str(actual)])


func cleanup() -> void:
	pass
