extends RefCounted
## Pure planning over shared finite stock. The current operation claim owns its
## committed batch; later arrivals remain available for a subsequent operation.
const Inventory := preload("res://game/rules/template/inventory.gd")
const Batch := preload("res://game/rules/template/batch_recipe.gd")

static func enabled(rule: Dictionary) -> bool:
	return rule.get("batch",{}).get("mode","") == "available"

static func plan(rule: Dictionary, runner: RefCounted, target: int, fetch: bool) -> Dictionary:
	var stock: RefCounted = runner.inventory
	var device: Dictionary = runner.machines.containers(rule.machine)
	var finite: Dictionary = stock.finite_inputs(device.input, rule.consumes)
	var projected: int = stock.projected_output(device.output, rule.produces, Inventory.SHARED)
	var output := Inventory._total(rule.produces)
	@warning_ignore("integer_division")
	var amount := mini(int(rule.batch.max),maxi(0,int(rule.stock_limit)-projected)/output)
	if fetch:
		if projected >= target and projected >= int(rule.policy.low): return {"definition":{},"error":""}
		var wanted := maxi(1,target-projected)
		@warning_ignore("integer_division")
		amount = mini(amount,wanted/output + (1 if wanted%output else 0))
	else:
		for item in finite:
			@warning_ignore("integer_division")
			amount = mini(amount,int(stock.quantity(device.input,item,-1,true))/int(finite[item]))
	var extra_space := output if device.input != device.output else maxi(0,output-Inventory._total(finite))
	if extra_space > 0:
		@warning_ignore("integer_division")
		amount = mini(amount,maxi(0,int(stock.remaining_capacity(device.output)))/extra_space)
	if amount < 1: return {"definition":{},"error":""}
	var result: Dictionary = rule.duplicate(true)
	result.consumes = Batch.scale(rule.consumes,amount).counts
	result.produces = Batch.scale(rule.produces,amount).counts
	return {"definition":result,"error":""}
