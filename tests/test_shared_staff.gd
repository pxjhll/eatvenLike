extends "res://tests/test_case.gd"

const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
const STIRFRY: SpecShop = preload("res://content/shops/stirfry/shop.tres")
const WorkerState := preload("res://game/rules/worker_state.gd")
const EXPECTED := {
	"cat": {"walk":112.0,"work":1.0,"carry":2.0},
	"raccoon": {"walk":88.0,"work":1.0,"carry":3.0},
	"fox": {"walk":96.0,"work":1.6,"carry":2.0},
	"rabbit": {"walk":104.0,"work":1.0,"carry":2.0},
	"gray_cat": {"walk":112.0,"work":1.0,"carry":2.0},
	"bear": {"walk":88.0,"work":1.0,"carry":3.0},
	"parrot": {"walk":112.0,"work":1.0,"carry":2.0},
}

func test_all_shops_reference_global_staff_definitions_including_retired_validation_kinds() -> void:
	for shop: SpecShop in [TEA, PANCAKE, STIRFRY]:
		var registered := []
		for kind in shop.staff.kinds:
			var id: String = kind.id
			check(id not in registered,shop.id+": exactly one registered definition for "+id)
			registered.append(id)
			check(id in ["rabbit","gray_cat","bear","fox","parrot"] or shop.staff.retired_kinds.has(id),shop.id+": inactive definitions exist only for old-save validation")
			var path := "res://content/characters/staff/%s.tres"%id
			if not ResourceLoader.exists(path):
				check(false,"Missing shared staff definition: "+id)
				continue
			var shared: SpecStaffKind = load(path)
			check_eq(shared.id,id,"Stable staff ID")
			if EXPECTED.has(id): check_eq(shared.stats,EXPECTED[id],id+" shared baseline")
			check(is_same(kind,shared),shop.id+": references global resource for "+id)
		for id in ["rabbit","gray_cat","bear","fox","parrot"]:
			check(id in registered,shop.id+": registers active staff "+id)
		for id in shop.staff.retired_kinds:
			check(id in registered,shop.id+": retains retired definition "+id)

func test_workers_own_independent_stats_from_shared_resource() -> void:
	var path := "res://content/characters/staff/rabbit.tres"
	if not ResourceLoader.exists(path):
		check(false,"Missing shared rabbit definition")
		return
	var shared: SpecStaffKind = load(path)
	var first := WorkerState.create(1,shared.id,shared.display_name,shared.stats,Vector2.ZERO)
	var second := WorkerState.create(2,shared.id,shared.display_name,shared.stats,Vector2.ONE)
	first.stats.walk = 999.0
	first.stats.extra = 7.0
	check_eq(shared.stats,EXPECTED.rabbit,"Runtime writes do not corrupt global definition")
	check_eq(second.stats,EXPECTED.rabbit,"Other worker remains independent")

func test_editable_shop_copy_owns_independent_shared_staff_definitions() -> void:
	if not TEA.has_method("copy_for_editing"):
		check(false,"Shop definitions require an explicit isolated editable-copy API")
		return
	var copy: SpecShop = TEA.call("copy_for_editing")
	check(not is_same(copy.staff,TEA.staff),"Copied shop owns staff settings")
	check(not is_same(copy.staff.kinds[0],TEA.staff.kinds[0]),"Deep copy must also copy external staff definitions")
	if is_same(copy.staff.kinds[0],TEA.staff.kinds[0]): return
	copy.staff.kinds[0].stats.walk = 999.0
	copy.staff.kinds[0].description = "copy only"
	var original_kind: SpecStaffKind = TEA.staff.kinds[0]
	check_eq(original_kind.stats,EXPECTED[original_kind.id],"Changing a copied shop cannot mutate the global kind")
	check(TEA.staff.kinds[0].description != "copy only","Shared metadata is also isolated")
