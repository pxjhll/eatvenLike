extends "res://tests/test_case.gd"

const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const WorkerState := preload("res://game/rules/worker_state.gd")
const EXPECTED := {
	"cat": {"walk":112.0,"work":1.0,"carry":2.0},
	"raccoon": {"walk":88.0,"work":1.0,"carry":3.0},
	"fox": {"walk":96.0,"work":1.6,"carry":2.0},
	"rabbit": {"walk":104.0,"work":1.0,"carry":2.0},
	"gray_cat": {"walk":112.0,"work":1.0,"carry":2.0},
	"bear": {"walk":88.0,"work":1.0,"carry":3.0},
}

func test_tea_uses_six_shared_original_staff_definitions() -> void:
	check_eq(TEA.staff.kinds.size(), EXPECTED.size(), "Original recruitment kinds retained")
	for id in EXPECTED:
		var path := "res://content/characters/staff/%s.tres"%id
		if not ResourceLoader.exists(path):
			check(false,"Missing shared staff definition: "+id)
			continue
		var shared: SpecStaffKind = load(path)
		check_eq(shared.id, id, "Stable staff ID")
		check_eq(shared.stats, EXPECTED[id], id+" tea baseline")
		var matches := TEA.staff.kinds.filter(func(k: SpecStaffKind) -> bool: return k.id == id)
		check_eq(matches.size(),1,"Exactly one recruitment entry: "+id)
		if matches.size() == 1:
			check(is_same(matches[0],shared),"Tea references global resource: "+id)

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
	check_eq(TEA.staff.kinds[0].stats,EXPECTED.cat,"Changing a copied shop cannot mutate the global kind")
	check(TEA.staff.kinds[0].description != "copy only","Shared metadata is also isolated")
