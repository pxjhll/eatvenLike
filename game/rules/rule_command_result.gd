extends RefCounted
## Stable business outcomes. Every factory returns detached caller-owned data.

const OK := "ok"
const UNKNOWN_COMMAND := "unknown_command"
const INVALID_ARGUMENT := "invalid_argument"
const SESSION_UNAVAILABLE := "session_unavailable"
const UNKNOWN_STATION := "unknown_station"
const STATION_ALREADY_UNLOCKED := "station_already_unlocked"
const STATION_NOT_UNLOCKABLE := "station_not_unlockable"
const SHOP_NOT_OPEN := "shop_not_open"
const STAGE_REQUIRED := "stage_required"
const INSUFFICIENT_GOLD := "insufficient_gold"
const UNKNOWN_BOX := "unknown_box"
const BOX_ALREADY_UNLOCKED := "box_already_unlocked"
const STATION_REQUIRED := "station_required"
const BOX_REQUIRED := "box_required"
const STATION_LEVEL_REQUIRED := "station_level_required"
const NO_UPGRADE := "no_upgrade"
const MAX_LEVEL := "max_level"
const SEATS_FULL := "seats_full"
const SEAT_STAGE_REQUIRED := "seat_stage_required"
const FLYER_ACTIVE := "flyer_active"
const FLYER_COOLDOWN := "flyer_cooldown"
const HIRE_EXHAUSTED := "hire_exhausted"
const STAFF_FULL := "staff_full"
const FRONT_FULL := "front_full"
const KITCHEN_FULL := "kitchen_full"
const UNKNOWN_WORKER := "unknown_worker"
const NOT_SEATABLE := "not_seatable"
const POST_OCCUPIED := "post_occupied"
const REASSIGNMENT_DISABLED := "reassignment_disabled"
const INVALID_POST := "invalid_post"
const POSITION_UNREACHABLE := "position_unreachable"
const WORKER_ALREADY_WAITING := "worker_already_waiting"
const EVENT_MISSING := "event_missing"
const INVALID_EVENT_CHOICE := "invalid_event_choice"
const UNKNOWN_CONNECTION := "unknown_connection"
const CONNECTION_ALREADY_BUILT := "connection_already_built"
const UI_DROP_REJECTED := "ui_drop_rejected"

const SCHEMAS := {
	"set_paused": {"paused": TYPE_BOOL}, "set_tuning": {"key": TYPE_STRING, "value": TYPE_FLOAT, "snap": TYPE_BOOL},
	"unlock": {"id": TYPE_STRING}, "unlock_box": {"material": TYPE_STRING}, "upgrade": {"key": TYPE_STRING},
	"buy_seat": {}, "send_flyers": {}, "hire": {}, "deploy_worker": {"id": TYPE_INT, "post": TYPE_STRING},
	"place_worker": {"id": TYPE_INT, "post": TYPE_STRING, "point": TYPE_VECTOR2},
	"recall_worker": {"id": TYPE_INT}, "buy_connection": {"id": TYPE_STRING}, "answer_event": {"choice": TYPE_INT},
}

static func is_ok(status: Dictionary) -> bool:
	return status.get("code") == OK

static func success(params: Dictionary = {}) -> Dictionary:
	return failure(OK, params)

static func failure(code: String, params: Dictionary = {}) -> Dictionary:
	return {"code": code, "params": params.duplicate(true)}

static func validate(command: String, arguments: Dictionary) -> Dictionary:
	if not SCHEMAS.has(command): return failure(UNKNOWN_COMMAND, {"command": command})
	var schema: Dictionary = SCHEMAS[command]
	for argument in arguments:
		if not schema.has(argument): return failure(INVALID_ARGUMENT, {"command": command, "argument": str(argument)})
	for argument in schema:
		var optional: bool = (command == "deploy_worker" and argument == "post") or (command == "place_worker" and argument == "point") or (command == "set_tuning" and argument == "snap")
		if not arguments.has(argument):
			if optional: continue
			return failure(INVALID_ARGUMENT, {"command": command, "argument": argument})
		if command == "set_tuning" and argument == "value":
			if typeof(arguments[argument]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(arguments[argument])):
				return failure(INVALID_ARGUMENT, {"command": command, "argument": argument})
		elif typeof(arguments[argument]) != schema[argument]: return failure(INVALID_ARGUMENT, {"command": command, "argument": argument})
	if command == "place_worker" and arguments.has("point"):
		var point: Vector2 = arguments.point
		if point != Vector2.INF and not point.is_finite(): return failure(INVALID_ARGUMENT, {"command": command, "argument": "point"})
	return success({"command": command})
