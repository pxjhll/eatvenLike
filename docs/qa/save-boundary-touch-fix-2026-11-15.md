# Save boundary and native guide touch

Base: main `b60188c23da051a166630f5713e552155d75cbb4`.
No economy, recipe, stage, content or deployment changes.

## Save boundary

The dispatcher may cancel an order-follow scope after service queue synchronization.
At the end of that tick a waiting customer still targeted pickup while restore
validation expected the ordinary queue. The previous save was preserved, but this
tick could not be saved. Another tick recovered naturally.

The shared runtime now synchronizes dispatch-dependent customer destinations after
allocation, without advancing time, admitting customers or weakening restore checks.
This may begin/retract a customer approach one simulation tick earlier than before.
The historical checkpoint regression checks real disk saves at 1349.9, 1350.0 and
1350.1 seconds and identical post-load continuation.

## Native touch

Guide bubble actions now handle native touch without requiring mouse emulation.
Presses are tied to the originating guide step, canceled/drag-out touches do not
activate, synthesized mouse input does not activate twice, and physical mouse
clicks remain supported.

## Verification

Local engine: Godot 4.6.3; project configuration is 4.6, CI documentation requests
4.7. Actual Android/browser visual validation is not covered by headless checks.

- Captured save boundary regression: passed.
- Guide checks: 72 checks, 0 failures.
- Official shop sessions: 4013 checks, 0 failures.
- Manifest focused acceptance: 5 jobs, 0 failures (template boundary and its
  tests, template authoring, guide, command contracts).
- Full rule-suite verification tracked separately; do not infer full CI passage
  from the focused checks above.
