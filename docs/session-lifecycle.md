# Shop session lifecycle

`game/app/shop_session.gd` owns the current shop's rules and persistence operations. Construct it with an explicit Profile, ShopSave and optional ShopRules. `start()` is idempotent while active; supplied rules are used directly, otherwise the store restores them. Fresh-shop initialization and retries use ProgressService's existing commit ordering. Failed starts expose no playable scene and cannot autosave. Successful finish/jump seals the session against further saves, restarts and transitions.

Normal gameplay creates its session only through `App.create_session()`. App loads the production Profile lazily and explicitly enables guides, tuning persistence and recording with their existing `user://` destinations. Shop scenes without an injected session use that factory. The `rules`, `store` and `profile` scene fields are read aliases after startup; injecting them without a session is rejected before consulting App.

Tests inject a session before adding a scene to the tree:

```gdscript
const TestSession = preload("res://tests/shop_test_session.gd")
var scene = load("res://presentation/shop/shop_play.tscn").instantiate()
scene.session = TestSession.make(spec, "my-test-%d" % OS.get_process_id())
scene.session.guide_enabled = true
root.add_child(scene)
```

The helper assigns isolated Profile, shop save, tuning and recording paths. All three services default off independently. Enabling guides never enables file persistence. Reusing a namespace reopens that fixture's campaign intent; only a newly created Profile selects the requested shop. Optional rules/store/profile arguments retain supplied objects, including failure injection. Enabled tuning or recording requires a nonempty destination. A disabled recorder does not read, count, delete or export files.

Call `scene.restart()` for the complete UI operation. It cancels dragging before resetting rules, resumes business (`paused = false`), clears old popup callbacks, selection, visuals, guide transient state, tuning shade, autosave timer and recorder sampling. Seen guide IDs, tutorial preference, speed and tuning remain. The scene returns to the shop page and saves through the same guarded session path. Session-only `restart()` resets rules and emits `restarted` without saving or changing Profile. RuleEvents retains its identity and subscriptions across reset and successful restore, so audio stays connected once.

`tests/render_session_lifecycle.gd` exercises real scenes and production-path poison sentinels. It requires a disposable data directory containing `session-lifecycle-userdata` (APPDATA on Windows, XDG_DATA_HOME on Linux), restores sentinel originals, and has an internal 25-second timeout. CI also applies an external 30-second bound. Existing scene, retry, tutorial, audio and work-action fixtures use the same isolated factory.

With shared movement, seated and exiting customers live in `rules.movement.customers` and their actors in `scene._customers`. The dining component retains furniture and table cups; it must not create duplicate actors. The lifecycle regression waits for actual business to seat and dismiss guests, verifies that restart clears rule routes and frees their actors/cups, preserves furniture, and seats new guests after reopening the shop. Legacy pending dining requests are also cleared on restart.

Local checks after changes to shared customer rendering or restart must include the existing lifecycle regression, in addition to new migration tests. A passing `tests/run_all.gd` does not cover these live scene scripts:

- `tests/render_session_lifecycle.gd`: session restart, shared dining customers, isolated persistence.
- `tests/render_progress_retry.gd`: failed startup and safe retry.
- `tests/render_command_contracts.gd`: real scene commands and persistence.
- `tests/render_presentation_boundary.gd`: scene writes and detached reads.

The full `tools/check_shops.py --profile headless --engine <Godot>` gate now includes all four entries through `tests/shop_acceptance.json`, using the same list locally, in CI and in Pages builds. Use `--only session_lifecycle` for a focused rerun, not as a replacement for full acceptance.

Run each with isolated user data, matching the CI entry points. For example:

```powershell
$env:APPDATA = 'D:/Tes/eatventure/_work/local-checks/session-lifecycle-userdata'
& 'D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe' --headless --path 'D:/Tes/eatventure' -s tests/render_session_lifecycle.gd
```
