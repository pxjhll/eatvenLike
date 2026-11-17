# Advisory fixed-post hint

Built on the verified save/touch/staffing fixes (`c01266a`), without economic or
dispatch changes. This is an optional presentation recommendation, not an
optimization promise or automatic staff placement.

## Conditions

- A declared shared `dispatch.station_posts` binding exists and placement is legal.
- No deployed worker already holds that post.
- At least two deployed, mobile, operating-qualified workers with native transport
  permissions can occupy it, so choosing one need not remove the last mover.
- An actual machine run is waiting for load/operate/stir/unload, not automatically
  processing, idle, or simply holding finished inventory. Any other active
  productive slot on that same machine suppresses the recommendation.
- Its customer-owned work is still accepted and unfulfilled; or a shared-stock
  run produces an item that accepted customer work currently needs and has no
  available source stock. Idle reserve replenishment alone is insufficient.
- Either the same run/phase/stir stop remains blocked for 20 simulated seconds;
  or at least 3 distinct waits in the last 60 simulated seconds total at least
  20 seconds, with the current wait already lasting 3 seconds. Overlapping slot
  waits count only once. No queue-full condition is required; paused time does
  not count. This reuses the existing 20-second bottleneck budget while recognizing
  repeated short human-operation stops.

Recovery, changed run/phase or staffing changes hide the current warning.
Historical wait episodes expire after 60 seconds; load/restart or runtime replacement
clears them immediately. Observation is view-local and not stored in saves.
Queries never dispatch workers or consume RNG. The advice does not claim all
production has stopped, nor that fixed staffing always improves the economy.

## Presentation

Uses the existing bottleneck strip and machine highlight, without an automatic
popup/toast or pause. The short text includes retaining mobile staff. Tapping
opens the staff page and explains the optional action; no placement is performed.
Existing no-staff and no-carrier warnings remain separate.

## Limits

This deliberately conservative condition omits isolated short waits and
multi-slot slowdowns while another slot is productive. It does not diagnose missing ingredients, prices, order mix,
all sources of long queues, or whether a human understands the advice. Actual
mobile layout and touch-device acceptance remain separate from headless tests.

## Threshold evidence and checks

A real seed-11 normal-player checkpoint replay from minute 25 to 35 observed
264.5 seconds of qualifying staff waits, but the longest uninterrupted phase
was only 7.6 seconds. A strict continuous 20-second condition produced no hint.
The final repeated-wait condition identified the shared cooking machine, first
at 1556.4 seconds, and hid the hint at 1558.2 when work resumed. The ten-minute
replay had 28 visible intervals, all on the same machine; these are passive HUD
intervals, not 28 popups or notifications. No customer/economy state was changed
by observation.

- Focused rule regressions: 9 tests, 0 failures, including generic machine identity,
  no-demand/early-staffing/fixed-post guards, pause, recovery, restore, repeated
  same-key episodes, expiry and overlapping slot intervals.
- Actual scene HUD regression: 8 checks, 0 failures; the existing strip opens the
  staff page, displays the transport tradeoff and does not place a worker.
- Focused manifest: 8 jobs, 0 failures, including formal sessions, refresh snapshot,
  guide, command contracts and template boundary checks.
- Local engine: Godot 4.6.3. Full rule acceptance and actual mobile visual testing
  remain separate checks; headless results do not prove final phone layout.
