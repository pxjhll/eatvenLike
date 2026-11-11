extends "res://tests/test_case.gd"

const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const BASELINE := "res://tests/baselines/tea_modularity.json"
const CAPTURE := "res://tests/baselines/capture_tea_modularity.gd"
const EXPECTED := {
	"cat": {"walk":112.0,"work":1.0,"carry":2.0},
	"raccoon": {"walk":88.0,"work":1.0,"carry":3.0},
	"fox": {"walk":96.0,"work":1.6,"carry":2.0},
	"rabbit": {"walk":104.0,"work":1.0,"carry":2.0},
	"gray_cat": {"walk":112.0,"work":1.0,"carry":2.0},
	"bear": {"walk":88.0,"work":1.0,"carry":3.0},
}

func test_tea_trace_matches_frozen_baseline() -> void:
	if not FileAccess.file_exists(BASELINE):
		check(false, "Freeze the original tea trace before changing production")
		return
	if not ResourceLoader.exists(CAPTURE):
		check(false, "Missing tea trace capture")
		return
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	var actual: Dictionary = load(CAPTURE).capture()
	check(actual.sold > 0, "Trace includes sales")
	check(actual.walking_samples > 0, "Trace includes worker movement")
	check_eq(actual.snapshots.size(), 60, "Ten-minute trace samples every ten seconds")
	check(actual.events.any(func(e: Dictionary) -> bool: return e.name == "sale"), "Trace records actual sale events")
	check_eq(actual, expected, "Complete original tea trajectory")

func test_tea_literal_character_baseline() -> void:
	check_eq(TEA.staff.kinds.size(), EXPECTED.size(), "Six original employee kinds")
	for kind in TEA.staff.kinds:
		check(EXPECTED.has(kind.id), "Known baseline kind: " + kind.id)
		if EXPECTED.has(kind.id): check_eq(kind.stats, EXPECTED[kind.id], kind.id + " original stats")
	var art: Node2D = load(TEA.scene_path).instantiate()
	var anchors := art.get_node("Anchors")
	check_eq(anchors.get_meta("staff_height",128.0), 128.0, "Original employee height")
	check_eq(anchors.get_meta("customer_height",110.0), 110.0, "Original customer height")
	check_eq(anchors.get_meta("customer_speed",170.0), 170.0, "Original customer speed")
	art.free()
