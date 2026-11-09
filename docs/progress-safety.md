# Progress persistence boundaries

`Profile` keeps its version1 JSON representation, including ordinary JSON floating point values. A missing `version` is read as legacy version1. String, Boolean, fractional and unsupported versions, malformed JSON and invalid permanent-field shapes block writes without modifying the original file. The same guard runs immediately before every commit, including reset, so replacing the file after startup cannot silently downgrade a newer profile. `last_error` and `load_error` explain blocked reads; `load_profile()` explicitly retries after a file is repaired.

`finish_shop(record)`, `select_shop(id)` and `acknowledge_fresh_shop()` return `Error` and persist a candidate before updating memory. `save()` retains its `Error` return. The overridable `_write_candidate(candidate)` boundary enables storage failure injection. Its default implementation writes sibling `.tmp`, flushes and checks the stream error, then renames over the destination. This protects the prior file from open/write/rename failures; it does not promise filesystem power-loss durability beyond Godot's flush/rename facilities.

`progress_service.gd` orders cross-file work:

1. Finish commits Profile before deleting the old shop file. Cleanup leaves at worst an old copy; the accepted transition cannot be recorded again by the departing scene.
2. Debug jumps save the current shop before committing the target Profile.
3. Fresh initialization first checks Profile write protection, saves an empty target shop, then durably acknowledges `fresh_shop`. Only then does the scene initialize gameplay, guide and autosave. Either failure retains the marker and shows a retry screen. While blocked, processing, input, explicit save, focus/exit saves and gameplay are disabled.

The synchronous `test_profile_safety.gd` suite covers candidate failures, disk bytes, memory snapshots, version protection, actual finish/jump signals and blocked startup. `render_progress_retry.gd` runs the full deferred scene startup/retry/restart lifecycle and verifies the responsive480x800 retry screen. It is also a bounded headless CI step. Optional `-- --screenshot=absolute.png` exports the blocked screen with graphical rendering.

All local engine runs must isolate `APPDATA` before launching Godot. Temporary Profile and ShopSave paths include the process ID; the live retry fixture's guide/tuning/recording writes stay inside that isolated application-data directory.
