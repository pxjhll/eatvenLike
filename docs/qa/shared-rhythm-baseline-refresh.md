# Shared rhythm baseline refresh (2026-11-15)

## Why this is a fixture update, not balance tuning

The previous `shared_shop_rhythm.json` is byte-identical to the fixture at
`1e58da9` (2026-11-12, initial shared template/service lifecycle), whose commit
explicitly left formal shop migration unfinished. Later formal content and
service migrations reached main `b60188c`, but this fixture did not follow them.
In particular its tea and pancake `orders_done` were still `-1`, the legacy
non-template sentinel. The current shared service records actual deliveries.
All three content fingerprints also differ from that old fixture.

The baseline is now the **unmodified measured report** from main `b60188c`:
[CI run 43674221446](https://github.com/pxjhll/eatvenLike/actions/runs/43674221446),
artifact `shop-acceptance` (ID 14146216892),
`_work/ci/economy/shared-rhythm.json`.
It is byte-identical to the independent
[PR 90 run 43696635849](https://github.com/pxjhll/eatvenLike/actions/runs/43696635849)
report, before this baseline refresh. Both used Godot
`4.7.stable.official.5b4e0cb0f`.
The report SHA-256 is
`00cf0b9dc06e7fce3e2801eee1bd7601996e390e61bfd2903aac076c8a7ecea2`.

No gameplay resources, economy values, tool simulation setup, comparison
strictness, or completion targets are changed here. A captured diagnostic is
not a claim that current balance or progression is desirable.

## Reproduction

On the source revision above, import with Godot 4.7, then run:

```sh
godot --headless --path . --import
godot --headless --path . -s tools/shop_rhythm.gd -- \
  --check=res://tests/baselines/shared_shop_rhythm.json \
  --output=res://_work/shared-rhythm-refresh.json
```

The fixed scenario remains seed 42, 600 simulated seconds, 0.1-second steps,
all unlocks/boxes opened and two actually deployed employees, separately for tea,
pancake and stirfry. This is not normal-money progression or a player speedrun.

| Shop | Old sold / revenue / lost | Current sold / revenue / lost |
| --- | --- | --- |
| Tea | 31 / 808 / 0 | 38 / 1022 / 140 |
| Pancake | 50 / 1076 / 80 | 54 / 1173 / 70 |
| Stirfry | 38 / 419 / 54 | 40 / 441 / 57 |

These differences include changed service/content semantics; the table must not
be interpreted as a controlled isolated balance improvement.

## Guards retained

The tool still compares the complete persisted report, including content hashes,
setup, every metric and minute sample. Existing mutation tests require missing
shops, modified content, changed metrics and changed setup to fail. The added
cheap regression rejects an old-content fixture before a full simulation:
three formal content hashes, scenario, ticks, staff, physical/save checks and
shared-service delivered-order accounting must all be current. It failed on the
old fixture and passes with this measured refresh. This does not replace the
full deterministic rhythm run, and must not be used to auto-refresh baselines.

## Local verification of this refresh

On the independent `fix/economy-acceptance-baselines` branch based on `b60188c`,
Godot 4.6.3 reran the complete three-shop 600-second diagnostic and returned
`SHOP RHYTHM: 0 failures` against the recorded 4.7 report. The generated report
is equal to both CI artifacts after JSON numeric normalization (serialization
spells some whole-valued floats differently between engine versions). Focused rhythm regressions: 5 cases,
0 failures, including deterministic resampling and deliberate report drift.
The local check supplements, rather than relabels, the recorded 4.7 evidence.
