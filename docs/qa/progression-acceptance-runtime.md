# Progression acceptance execution (no gameplay retuning)

Base: `b60188c23da051a166630f5713e552155d75cbb4`. This branch does not contain
PR #90 or the parallel third-shop branch. It changes test execution only.

## Evidence and cause

Main CI 43674221446 and PR #90 CI 43696635849 both killed `shop_progression`
at 240 wall-clock seconds (return code -9). Both logs only contained Godot's
startup line. That is an execution timeout, not a completion-target assertion.
The script originally ran three shops plus two extra stirfry seeds serially,
and printed only after an entire scenario returned.

Unlike normal 1x gameplay (`shop_play.gd`), the direct rule simulation never
saved. Formal `ShopSave.save_game` validates and writes the snapshot, then
adopts its compacted history. Without that path, completed transaction records
remain in long-running rule queries. Instrumented tea/seed20261025 observations showed
increasing wall time per simulated minute. At simulation 901 seconds, the old
path had taken about 111 seconds and the saved path about 41 seconds on this
cloud host. These concurrent diagnostic measurements are evidence of the trend,
not a portable performance benchmark or an FPS claim.

## Changes and contracts

- The CLI now uses formal disk saves every 10 simulated seconds, representing
  unpaused 1x gameplay. The original pure `sample` remains available for comparison
  and legacy-rule tests. No direct pruning, fast-forward, different physics step,
  free purchases, production values or target changes.
- Failed checkpoints stop that scenario and remain errors. The last successful
  checkpoint is retained in the isolated test userdata for diagnosis. Successful
  temporary checkpoint files are cleaned up, never the player's save.
- Every simulated minute prints shop, seed, clock, wall time, stage and sold count.
  This distinguishes slow forward progress from missing progress in timeout logs.
- Each shop has its own manifest job and report. The stirfry job still executes
  the default seed plus 42 and 84 and checks all of them.
- CI economy scenarios run independently from behavior acceptance, so they cannot
  exhaust the behavior job's 30-minute budget or prevent other scenarios reporting.
  Tea/pancake processes are bounded at 600 seconds; the three-seed stirfry
  process at 1200 seconds; each CI job at 25 minutes
  including engine download/import. Economy failures remain separately reported.

## Interpretation

The fixed `minute_visit_role_load_v1` purchase/deployment bot is a reproducible
scenario, not an optimal-player claim or a balance approval. Default content seeds
and the two existing stirfry audit seeds are unchanged.

The historical `shared_shop_progression.json` fixture remains untouched. Its
+/-5% completion checks remain available through `completion_errors`, and every
CLI run prints/stores their results as `legacy_target_diagnostics`. They are
**not newly approved balance targets**. In particular, the old 46-minute stirfry
figure is not authorization to tune that shop.

Current acceptance instead requires successful completion within the unchanged
5400-simulation-second scenario limit, no checkpoint/restore errors, all default
and audit seeds present, and strict scenario-and-setup agreement with the separately
recorded `current_shop_progression.json`. A changed deterministic snapshot, a
historical target mismatch, a failed save and an execution timeout are distinct.
Tests explicitly prove that a legacy-target miss remains visible while unfinished
runs, missing audits and save errors still fail current acceptance. No production
values are adjusted to fit either snapshot.

The report setup now records the save interval and playback speed. Consequently
the old no-save fixture setup is explicitly different rather than silently treated
as the same experiment. The measured 4.7 replay times were 344.916 seconds (tea), 49.005 seconds
(pancake), and 749.619 seconds (all three stirfry seeds). These support the
600/600/1200-second process budgets with headroom. Actual CI host differences
remain relevant; this local-only branch has not run a new remote workflow.

## Recorded current scenario results

Godot 4.6.3 generated the new version-3 fixture on the base above. The current
protocol is replayed independently with CI's actual Godot
`4.7.stable.official.5b4e0cb0f`, comparing every selected scenario metric,
content fingerprint, stage and purchase action against that fixture.

| Scenario | Seed | Completion (simulation seconds) | Sold | Revenue | Staff | Historical target diagnostic |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| tea | 20261025 | 2382.2 | 408 | 15174 | 7 | +11.68%, outside old +/-5% |
| pancake | 0 | 1377.1 | 272 | 5824 | 4 | +0.88%, within old band |
| stirfry | 11 | 2917.0 | 252 | 3803 | 6 | +5.69%, outside old +/-5% |
| stirfry audit | 42 | 2864.1 | 242 | 3661 | 6 | +3.77%, within old band |
| stirfry audit | 84 | 2814.9 | 241 | 3497 | 6 | +1.99%, within old band |

All five generation scenarios completed and all periodic checkpoints and final
restores succeeded. No failed or incomplete scenario is recorded as a passing
fixture. These are this bot's current measurements, not changes to design targets.

Reproduce current snapshot checks without changing content:

```sh
python3 tools/check_shops.py --engine /path/to/godot --profile economy --output _work/economy-check
# One shop, still including all three stirfry seeds:
python3 tools/check_shops.py --engine /path/to/godot --profile economy --only shop_progression_stirfry --output _work/stirfry-check
```

The old `shared_shop_progression.json` remains byte-for-byte unchanged.

## Final verification

- Godot 4.7 full rule suite: **1049 tests, 0 failures**.
- Python acceptance-runner contracts: **10 tests, 0 failures**; workflow YAML
  parses and each new `--only` entry resolves to the intended scenario.
- Godot 4.7 full three-shop 600-second rhythm check: **0 failures** against the
  refreshed fixture (also reproduced with 4.6.3).
- Godot 4.7 independent progression replay: all three commands exit 0; all five
  scenarios match the 4.6.3-generated current fixture's full configuration and
  scenario data, including purchase actions and both audit seeds.
- Checkpoint failure propagation, 600-second saved/unsaved equivalence, missing
  audit rejection, unfinished-run rejection and separate historical target
  diagnostics are covered by regressions. Targeted missing-feature and stale-baseline guards were observed red before
  implementation and green afterward.
- New fixture SHA256:
  `b654fef0c0db4f386d51419b8460b830bb9b5f2ffc6468204bcb8cfa76cbe6e3`.
- No changes in `content/`, `game/`, or `presentation/`; no changes to the
  historical progression fixture. `git diff --check` passes.

Future gameplay/configuration integration, including the separate pending PRs,
requires its own replay before accepting changed snapshots. A snapshot update is
never approval of a new completion-time target. No push or deployment is included.
