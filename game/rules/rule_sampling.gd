extends RefCounted
## Shared random arithmetic. Callers own eligibility, timing and the one RNG.

static func interval(pattern: String, mean: float, rng: RandomNumberGenerator) -> float:
	return mean if pattern == "fixed" else -log(1.0 - rng.randf() * 0.999) * mean

static func choose(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for item in weights: total += weights[item]
	var sample := rng.randf() * total
	var selected: String = weights.keys()[0] if not weights.is_empty() else ""
	for item in weights:
		sample -= weights[item]
		if sample <= 0:
			selected = item
			break
	return selected
