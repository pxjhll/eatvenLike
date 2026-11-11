# Adding a shop

A shop needs rule data, a campaign entry and an independent art scene. `ShopRules` remains a pure simulation; normal application sessions and the authoring CLI enforce the configuration boundary. Supported fulfillment/dispatch settings and reserved fields are listed in [shop-capabilities.md](shop-capabilities.md).

## Data and campaign

1. Create a `SpecShop` resource containing its items, dishes, stations, stages, staff, layout, goals, fulfillment, dispatch and auxiliary rules. Keep IDs stable and unique within each collection, and resolve references inside the shop.
2. Set `scene_path` to a `PackedScene` whose root is `Node2D`. Set a shop-specific `save_file`.
3. Add a `SpecCampaignShop` with the same shop ID and its resource path to the desired campaign. Empty paths remain unimplemented entries and are skipped by navigation.
4. Validate before opening the shop. Errors are dictionaries with `code`, `path` and `message`; for example, `fulfillment.arrival` identifies an unsupported arrival policy. `ShopSpecValidator.summary(errors)` produces the startup/CLI message.

The production `Profile` defaults to the production campaign. A separate campaign can be supplied with `Profile.new(profile_path, campaign)`. Reopening that profile requires passing the same campaign. Use `profile.available_shops()` and `profile.next_shop(id)` for instance navigation; `Profile.shops()` intentionally retains the default production list. `ShopSession.shop_for(profile, target_id)` resolves an entry from the instance campaign.

## Shared movement protocol

New movement-capable layouts opt in with `layout.motion_version = 1`. Version 0 retains legacy behavior during staged migration. Use `tests/fixtures/movement_shop.gd` as an executable, data-only example for the three existing fulfillment modes; it is controlled test geometry, not a replacement production art scene.

- Version 1 requires grid navigation. Set `motion_units` to native art width / 720; scene preflight rejects a density mismatch. Logical customer speed is the shared 170. Employee attributes come from their registered definitions and upgrades, then convert to native units.
- Define `actor_areas` as permission name to an array of grid `Rect2i`s. `staff` and `customer` are required. Optional serve-role profiles `front` and `kitchen` restrict those employees; roles without a separate profile use explicit `staff` access. Each profile intersects the overall `areas`. Unknown profiles are denied.
- Author `customer_queue` in queue order and `customer_points` for `entrance`, `exit`, `pickup`, `seat:<group>/<index>` and `wait:<group>/<index>`. These are reachable approach ports. Employee station points and customer pickup points are separate; the seated sprite position remains an art anchor offset.
- Keep the entire 12-logical-unit foot radius clear. Routes conservatively use its square bounds. Unreachable requests wait and retain their actual location, task and reservations; they cannot turn into straight paths or business arrivals. Navigation obstacles still follow `obstacle_stations` unlock state.
- Business calls `ShopRules.begin_move` / `advance_move` and consumes customer readiness. Views consume detached `ShopView.render_snapshot().movement`; they must not integrate GUI delta to advance business travel. The dining component renders furniture/items only in this mode.
- Movement state version 1 is saved with routes, identities and pending exits. Legacy files receive a backup before first replacement; future versions cannot be overwritten. Customer positions absent from a legacy save are reconstructed from its stage/ports, rather than claimed as exact historical GUI coordinates.

Editable scene modules now export customer ports and permission areas alongside employee space; see the module section below. Legacy scenes still use their original employee-only Nav export. Production shops are migrated in T09/T10. Run `tests/render_shared_movement.gd` alongside the ordinary shop UI and rule regressions. See [shared-movement.md](qa/shared-movement.md) for the tested behavior and limits.

## Composable actor actions

`dispatch.action_version = 0` preserves legacy execution. Version 1 supports `serve`, `handoff` and `single`, and requires `layout.motion_version = 1`. All three formal shops use it. `rule_actions.gd` owns only the lifecycle of a sequential plan; recipe dependencies remain in the existing fulfillment rules.

An action step is `{kind, target, seconds, label, data}`. The six registered kinds are `move`, `pickup`, `operate`, `transport`, `drop`, `wait`. `ActionContext` owns the meaning of ports and durations; the serve adapter calculates operation/pick/drop durations from existing rules on entry, while explicit waits use their `seconds`. `ready` must be read-only and is checked before entry and each tick. A blocked action retains its remaining time and reservations. Each tick commits at most one action, including zero-duration actions.

The context's `reserve` returns `{error, lease}` atomically. The lease references the one business inventory/reservation owner; do not create a second stock ledger in the executor. `commit` must complete its validated transaction and release a terminal lease. `cancel` releases/compensates only the uncompleted business scope. Use the cancellation API before replacing a program; arbitrary record replacement cannot infer where real items should go.

Programs contain only data and keep a versioned cursor/status. Cursors commit before synchronous effects broadcast events. Future versions cannot overwrite an existing file; legacy active jobs rebuild from their recorded stage and remaining time, with an original-file backup before replacement. `ShopView.render_snapshot().actions` publishes detached per-worker summaries; presentation code must never commit action effects.

See [composable-actor-actions.md](qa/composable-actor-actions.md), `tests/fixtures/action_context.gd` for a small real inventory context, and `serve_action_context.gd` for a production-rule adapter. Run `tests/render_actor_actions.gd` in addition to the shared movement and ordinary shop regressions.

`handoff_action_context.gd` binds the existing inventory job. `single_action_context.gd` binds one current order step or pot chore. Single batch pickup records whether stock was taken; recall returns unfinished material, releases stations and retains paid order progress for redeployment. Keep operation durations in the original business functions. Clear completed actions and business claims before broadcasting a sale. These adapters do not provide a new recipe language or enable serve-only flow policies on single/handoff.

## Production dependencies and order delivery

`fulfillment.flow_version = 0` preserves existing recipes, delivery and content fingerprints. Version 1 currently supports `serve`. `production_plan.gd` compiles existing `SpecStep.consumes/produces` into a dependency graph; `unit.done` and the original goods ledger remain authoritative. Independent work steps can run concurrently and a join waits for every producer, regardless of their order in the recipe array. Each item needs one producer; cycles, missing inputs, insufficient work output, surplus unused work output and final quantities other than one fail validation. Supply and batch-pot steps remain reusable sources.

`delivery_batch = "item"` retains individual delivery. `"order"` requires `serve`, `seat_wait`, `dispatch.action_version = 1` and `layout.motion_version = 1`. Optional `delivery_points` maps dish IDs to pickup station IDs and requires order delivery. Unmapped dishes use the first pickup station. Author every pickup's spatial port; a locked pickup cannot receive finished goods. Multiple pickup stations require flow version 1.

An order job reserves all outstanding finished goods atomically after they reach their collection ports. Employee capacity must cover the entire outstanding order. Missing food or insufficient capacity waits; it does not partially reserve or split the order. The reserved capacity remains valid if a temporary bonus expires. The composed actions collect each real good, then deliver the whole bundle at the customer's seat. Payment and eating state commit before events are announced. Cancellation returns held IDs to their individual collection ports and releases every reservation. The sprite uses the first held item and the existing quantity indicator; each item keeps its own ledger identity.

New active units save a version and recipe signature. The signature includes item, step order, station, action and input/output counts, excluding durations. Changing an active recipe's indexed identity protects its original save from overwrite. Legacy units without signatures can adopt the current recipe only when original step indices retain their meaning; the first replacement preserves a verified original-file backup. This is not a step-remapping migration. Future flow/bundle versions are protected as well.

Use `tests/fixtures/flow_shop.gd` for controlled parallel and two-port examples. `ShopView.production_snapshot(dish_id)` and `render_snapshot().flow` return detached definition and delivery summaries. Run `tests/test_flow_composition.gd` through the normal suite and `tests/render_flow_composition.gd` for real character carrying and event snapshots. See [production-and-delivery-composition.md](qa/production-and-delivery-composition.md). Production shops remain on their legacy settings until the separate migration tasks.

## Editable scene modules

Start from `presentation/shop/modules/ShopTemplate.tscn`. Instantiate the supplied station, counter, table, entrance/queue and space prefabs under `Sortables`; replace only their `Visual` subtree with approved assets. Each module has a unique `module_id`. Station modules reference stable `station_id`s; tables bind seat group, first seat, table index, purpose and `seats_per_table`. Their local `Anchors` and `Nav` children describe interaction rectangles, display points, approach ports and footprints. Module roots and their coordinate parent chains support translation only. Scale sprites inside `Visual` when fitting artwork.

`Anchors` metadata `module_version = 1` opts into the complete export. Root Nav declares grid, cell, dimensions, motion version/density, aliases and spawn point. Module `Areas` and `Access/<profile>` rectangles use native pixel coordinates and must align exactly to grid cells after translation. Footprints remain pixel rectangles. The export validates clear, reachable staff/customer ports against all authored footprints and preserves the shared foot radius. Missing or duplicate bindings, unsupported transforms, bad references and disconnected routes fail preflight.

The read-only `ShopAnchors` projection exposes existing paths to the generic renderer. Moving a module changes its interaction regions, seating and exported space together; no duplicate anchor tree is generated. Work/seat approaches are separate from furniture or seated sprite positions. Queues require contiguous numeric ordering from zero. Table capacity is published to the existing cup renderer; first seat and table index must agree with that capacity. Station visuals follow existing unlocks. The graybox tables are preplaced, chairs follow purchased seats, and the entire furniture footprint is always reserved.

Run `tools/sync_shop_layouts.gd -- --shop=<resource>` to export one explicit shop, and append `--check` for a byte-preserving comparison. `--campaign=<resource>` selects a custom campaign instead; empty targets or conflicting options fail. All candidates are validated before any are written. The full field comparison includes motion settings, actor permissions, customer ports/queue, aliases and spawn point. The runtime consumes the saved `SpecLayout`; it never silently repairs it from art.

See [the module authoring guide](../presentation/shop/modules/README.md) and [T08 QA](qa/editable-scene-modules.md). `tests/fixtures/module_shop.gd` is an independent full assembly using copies of existing content; `tests/render_scene_modules.gd` exercises real world input, rendering, sales and session restore. Formal rollout is staged; arbitrary live-save relocation is a separate capability.

The formal `stirfry` shop now demonstrates the shared template. It references global employee definitions, enables shared movement/actions and preserves its original self-pickup/flow-0 policy. Shared furniture uses `station_slots`: local `Anchors/Slots/<slot>` and `Nav/Slots/<slot>/Work` bind additional station IDs without copying a stove or counter. `Visual/Slots/<slot>` follows that station's unlock state; a fixed base can live in `FixedVisual`. Independent purchase stages require Frames; non-purchasable companion ports can omit them.

Self-pickup modules can author `Nav/Pickup/0...` (or root `Nav/Customers/Pickup/0...`) for explicit `customer_points["pickup:<index>"]`. These are ordered, reachable approach ports covering maximum seat capacity. Existing definitions without these points retain their old scatter behavior. Staff may use the side passage while the customer permission region excludes the kitchen.

`movement_adoption.gd` handles the first legacy save without movement state for all three business modes. It preserves business identity, reservations, goods and remaining timers, retargets current ports, and relocates invalid legacy positions to the nearest reachable grid center. Already-running hand actions adopt their current port. The generated state is validated again. Before first replacement, `ShopSave` verifies an original-file backup; unavailable adoption geometry protects the original file instead of clearing progress. Existing v1 files are not automatically relocated for arbitrary later layout edits.

See [T09 QA](qa/stirfry-shared-template.md) and [T10 QA and rhythm comparison](qa/first-shops-shared-template.md). Run `tests/render_stirfry_migration.gd` and `tests/render_first_shops_migration.gd` for real old-file startup, pause, 1/2/4 speed controls, save and reopen. Recipe/policy tests using frozen legacy definitions remain separate from formal shared behavior tests. Tea/pancake keep their existing inherited/procedural art hierarchy and use complete root Nav exports; new shops should begin with the reusable module template.

## Art contract

`presentation/shop/shop_scene_contract.gd` exposes read-only `validate(shop, art)` and `prepare(shop)`. Preparation returns `{errors, art}` and frees rejected instances. The caller owns a successful candidate. The generic scene validates data and prepares one art candidate before calling `Session.start`; it adopts that exact candidate on success and frees it when session startup fails. An authoring error blocks business and saving without replacing or quarantining existing progress. Repair the configuration and use the retry button.

The scene uses one shared world coordinate system:

- Art root and the actor-parent chain must have identity transforms. `Anchors` is a `Node2D` at the origin. Descendant anchors support translation only; rotation, scale and skew are rejected.
- `Anchors` metadata defines `world_size` and `top_margin`. Character height and customer speed come from `content/characters/actor_presentation.tres`; per-scene `customer_height`, `staff_height` and `customer_speed` are rejected. Actor-local sizes use the tea baseline (128 staff / 110 customer); the whole actor scales by native canvas width / 720, and the camera cancels that density so the same character has the same screen size across shops. `sortables` resolves a `Node2D` relative to the art root, defaulting to `Sortables`. Rectangle anchors use `AnchorRect` with positive finite size. Optional numeric/vector metadata is type-checked before use.
- Every stage-unlocked station needs `Stations/<id>/Tap` and `/Frame`. Stations with upgrades/material purchases need a Tap. A counter can use the existing dining-seat chip entry instead of a Tap.
- A draggable seatable station or counter needs a Post rectangle and a matching `Drops/<n>` rectangle with `metadata/post`. Drop references must resolve to shop stations. Ground placement still uses the layout's existing fallback.
- Queue needs at least one point. The renderer extends its final segment for additional customers. Seat groups need enough `Seats/<group>/<n>` points for all declared stage seats and purchases.
- Every enabled connection needs `Connections/<id>/Frame` and at least two `Path` points. The rules use the same connection ID for the displayed route.
- An installed `shop_dining.gd` component additionally requires `Lanes`, `Aisle` and `Entrance`, because its path builder directly consumes those anchors. Its rendered dining group also needs enough `Tables/<group>` points for the declared seat capacity (starting seats plus explicit purchase steps, or the fixed step times purchase count). Table count rounds up for partial tables; `per_table` defaults to 2 and must be a positive integer. Table anchors remain optional without the dining component.
- `Nav` is optional for legacy scenes (straight layouts commonly omit it). Module version 1 requires a complete grid Nav export. When present, exported fields must equal `shop.layout`; preflight never silently changes rule data to fit art. Local module anchors follow the same rectangle and metadata rules as root anchors.

Safe existing fallbacks stay optional: station Mark/Badge/Buffer/Put, shelf/chip decoration, Waiting, Sale and Pickup, and Exit (falls back to Entrance). In a scene without the dining component, Entrance and Aisle also have safe fallbacks. Other arbitrary art metadata remains available for decoration and extensions.

## Isolated third-shop example

`tests/fixtures/noodle/` contains a full `SpecShop`, its own one-shop campaign and an independent graybox scene. The scene exports the fixture's unchanged straight-layout coordinates. Its ASCII labels fit the existing production font; it uses generic character/item artwork, including the default drink placeholder for items. It is an interaction fixture, not a production noodle art pack.

The real-click regression constructs a real `Profile`, `ShopSave` and `ShopSession`; it never assigns `Profile.shop` directly. It opens the shop, hires employees, unlocks stations, upgrades a flavor, sells every dish, saves and reopens, checks exact subsequent simulation, and restarts into a new business. It also tests malformed data/art with an existing old shop file and a pending fresh-shop marker, including repair/retry and candidate disposal. The default campaign remains unchanged, and `tests/*` remains excluded from production exports.

Run from the project root:

```powershell
$env:APPDATA = 'D:/Tes/eatventure-analysis/shop-contracts-userdata/session-lifecycle-userdata/scene'
& 'D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe' --headless --path . -s tools/validate_shops.gd
& 'D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe' --headless --path . -s tests/render_shop_noodle.gd
```

The read-only CLI checks both production shops and the isolated fixture. CI runs it with a 30-second limit and the third-shop GUI regression with a 60-second limit. For graphical QA, omit `--headless` and append `-- --size=480x800 --screenshot=D:/path/noodle.png`; also check `720x1280` and `1280x720`. Capture arguments only resize the final QA view; the full input regression runs at 720x1280. Use isolated APPDATA/XDG_DATA_HOME for every test run; the session-lifecycle runner requires a `session-lifecycle-userdata` path segment.
