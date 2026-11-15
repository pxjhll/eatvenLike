extends "res://tests/test_case.gd"
const Inventory := preload("res://game/rules/template/inventory.gd")
const Machines := preload("res://game/rules/template/machines.gd")
const View := preload("res://game/rules/template/view_frame.gd")

func _inventory() -> RefCounted:
	var inventory := Inventory.new()
	check(inventory.has_method("reserve_actor_transfer"), "staff and customer carriers use the same public transfer capability")
	if not inventory.has_method("reserve_actor_transfer"): return null
	inventory.configure("pass", 8)
	inventory.configure("target", 8)
	inventory.configure("guest:1", 8)
	inventory.seed("pass", "meal", 4)
	return inventory

func test_customer_and_employee_identity_do_not_collide_and_share_transfer_effects() -> void:
	var inventory := _inventory()
	if inventory == null: return
	var staff: Dictionary = inventory.reserve_transfer(1,"pass","target","meal",2,2)
	var customer: Dictionary = inventory.reserve_actor_transfer("customer:1","pass","guest:1","meal",2,4)
	check_eq(customer.error,"","customer may carry while employee with the same numeric ID also works")
	check_eq(inventory.quantity("hand@customer:1","meal"),0,"customer reservation is not a pickup")
	inventory.pickup(staff.id)
	inventory.pickup(customer.id)
	check_eq(inventory.quantity("hand:1","meal"),2,"employee hand")
	check_eq(inventory.quantity("hand@customer:1","meal"),2,"customer hand")
	var frame: Dictionary = View.build(inventory,Machines.new(inventory))
	check_eq(frame.held[1].count,2,"staff presentation reads its own carrier")
	check_eq(frame.held["customer:1"].count,2,"customer presentation reads the same public projection")
	inventory.drop(customer.id)
	inventory.drop(staff.id)
	check_eq(inventory.quantity("guest:1","meal"),2,"customer completed the same drop operation")
	check_eq(inventory.quantity("target","meal"),2,"staff goods remain distinct")
	check_eq(inventory.audit(),[],"all carriers share one conservation ledger")

func test_customer_carrier_restore_preserves_ownership_and_cancel_returns_once() -> void:
	var inventory := _inventory()
	if inventory == null: return
	var task: Dictionary = inventory.reserve_actor_transfer("customer:1","pass","guest:1","meal",2,4,-1,71)
	inventory.pickup(task.id)
	var reopened := Inventory.new()
	check_eq(reopened.restore(inventory.snapshot()),"","restore customer hand with its own actor identity")
	check_eq(reopened.quantity("hand@customer:1","meal",71),2,"allocated meal ownership survives reopening")
	check_eq(reopened.cancel(task.id),"","customer cancels through the same compensation capability")
	check_eq(reopened.cancel(task.id),"","cancel is idempotent")
	check_eq(reopened.quantity("pass","meal",-1),4,"original source ownership and quantity restored")
	check_eq(reopened.audit(),[],"no carrier-specific inventory backend")

func test_invalid_carrier_and_direct_customer_hand_mutation_are_rejected() -> void:
	var inventory := _inventory()
	if inventory == null: return
	var before: Dictionary = inventory.snapshot()
	for actor in ["customer:0","customer:01","private_shop_actor:1"]:
		check(not inventory.reserve_actor_transfer(actor,"pass","guest:1","meal",1,2).error.is_empty(),"unsupported actor identity is explicit")
	check_eq(inventory.snapshot(),before,"invalid actors cannot reserve or mint goods")
	var task: Dictionary = inventory.reserve_actor_transfer("customer:1","pass","guest:1","meal",1,2)
	inventory.pickup(task.id)
	before = inventory.snapshot()
	check(not inventory.seed("hand@customer:1","meal",1).error.is_empty(),"customer hand cannot bypass pickup")
	check(not inventory.reserve_operation(0,"hand@customer:1",{"meal":1},{"meal":1}).error.is_empty(),"held stock is protected by the same lease")
	check_eq(inventory.snapshot(),before,"failed hand mutation is atomic")
