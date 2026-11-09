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
