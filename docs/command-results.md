# Business command results

Use `ShopRules.command_status(command, arguments)` to check a command without changing state, and `execute_command(command, arguments)` to check and perform it once. Both return fresh `{code: String, params: Dictionary}` data. Only `code == "ok"` means success; displayed text never determines validity. Parameters are detached from live state.

```gdscript
var status := rules.command_status("unlock", {"id": "boil"})
if status.code == "insufficient_gold":
    print(status.params.required)
var result := rules.execute_command("deploy_worker", {"id": 2})
if result.code == "ok":
    print(result.params.post) # Resolved automatic post, possibly empty.
```

| Command | Required arguments | Optional arguments |
| --- | --- | --- |
| `unlock` | `id: String` | |
| `unlock_box` | `material: String` | |
| `upgrade` | `key: String` | |
| `buy_seat`, `send_flyers`, `hire` | | |
| `deploy_worker` | `id: int` | `post: String = ""` |
| `place_worker` | `id: int`, `post: String` | `point: Vector2 = Vector2.INF` |
| `recall_worker` | `id: int` | |
| `buy_connection` | `id: String` | |
| `answer_event` | `choice: int` | |

Unknown commands return `unknown_command`. Missing, additional, or incorrectly typed arguments return `invalid_argument` with `params.argument`; all command results include `params.command`. Placement accepts the exact `Vector2.INF` sentinel or finite coordinates. Negative worker IDs and event choices pass schema validation and receive the existing domain rejection. Empty post and the unzoned upgrade key `staff/` remain valid inputs.

Named codes and factories are in `game/rules/rule_command_result.gd`. Gold failures include `required`; stage dependencies include `stage`, the required stage index; station and box dependencies include `station` and `material`; machine level failures include `station` and `required_level`; staff capacity includes `count`; flyer timers include rounded-up `seconds`; worker failures include `id`. Connections have `unknown_connection` and `connection_already_built`, both with `id`. Original rejection precedence, automatic post choice, deployment no-op behavior, costs, and events are preserved. Invalid requests and domain rejections preserve saved bytes, RNG, event history, and live identities.

`content/ui/rule_command_text.gd` formats statuses with optional shop name resolution and per-code template overrides. It is neutral content shared by compatibility tools and UI. `connection_rows()` includes `status` alongside its temporary display-only `error`.

The existing String command methods, `*_error`, `role_room`, and `placement_error` are temporary compatibility adapters. They format canonical results; canonical checks and execution never invoke them. New callers should use command results and keep validity separate from localization.


`ShopView` adds `status` beside display-only `error` on unlock sections, track and material rows, seats, flyers, hiring and staff tracks. Flyer upgrades expose `upgrade_status` beside `upgrade_error`. Locked boxes use `station_required` to select `box_closed`; error wording never selects a material state. Station/staff buttons, world affordability frames, guides and scene commands consume codes. Existing numeric room and product guards still apply.

`ShopView.new(rules, message_formatter)` retains the Rules positional argument and accepts an optional Callable. The same `message_formatter` property can be assigned on an existing real-scene view. `command_message(status)` calls it with `(detached_status, shop)`, or defaults to the shared catalog. It may return translated, unrelated or empty failure text, or nonempty success text. None of those outputs controls availability, event consumption, drag validity or whether a command saves. UI success feedback continues to use the existing action-specific text.

Staff dragging checks and executes `place_worker` with canonical results. UI geometry failures use `ui_drop_rejected` and `params.reason` anchor tokens. Geometry labels, occupied-post hints and the detailed front-capacity hint remain presentation-owned and separate from validity. A rejected interaction preserves business state, events, pending cards and saved bytes; successful interactions execute and persist once. `tests/test_command_ui.gd` covers real section controls/read models; `tests/render_command_contracts.gd` exercises isolated production scenes with empty/translated formatters, adapter traps, fatal runtime errors and counted persistence.
