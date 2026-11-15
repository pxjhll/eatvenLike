extends SceneTree
const TestSession := preload("res://tests/shop_test_session.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const Hint := preload("res://game/rules/template/staff_operation_hint.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL ",message)
func _run() -> void:
	root.size = Vector2i(720,1280)
	var rules := ShopRules.new(TEA,42)
	rules.gold = 1000000
	for id in ["lemonade","boil","seal","mix","press","topping"]: rules.unlock(id)
	for id in ["tea_leaf","milk"]: rules.unlock_box(id)
	for unused in 2:
		rules.hire()
		for worker in rules.roster:
			if not worker.deployed: rules.deploy_worker(worker.id)
	rules.runtime.set_service_open(false)
	rules.runtime.arrive([{"dish":"black_tea","qty":1}])
	for tick in 600:
		rules.step(0.1)
		if not Hint.candidates(rules.runtime).is_empty(): break
	_check(not Hint.candidates(rules.runtime).is_empty(),"actual shortage available")
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = TestSession.make(TEA,"user://operation-hint-ui-%d.json"%OS.get_process_id(),rules)
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	scene.guide.enabled = false
	scene.guide.refresh(0)
	scene.ui.popups.clear()
	scene.view.observe_bottlenecks()
	rules.clock += ShopView.HINT_AFTER
	scene.view.observe_bottlenecks()
	scene._toast_left = 0
	scene._refresh(0)
	var buttons: Array = scene.ui.find_children("BottleneckHint","",true,false)
	_check(buttons.size()==1,"existing HUD strip is reused")
	if buttons.size()==1:
		var button: Button = buttons[0]
		_check(button.visible,"hint appears")
		_check(button.text.contains("流动员工"),"short advice keeps mobile staff")
		_check(is_zero_approx(scene._toast_left),"no automatic toast")
		var before := rules.to_dict()
		button._go()
		_check(scene.ui.page=="staff","tap opens staff page")
		_check(scene._toast.text.contains("保留流动"),"tap explains tradeoff")
		_check(rules.to_dict()==before,"tap never moves staff or changes rules")
	scene.free()
	print("OPERATION HINT UI: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
