# Dispatch release save boundary

`tea_before_uncall.json` is a valid 1340-second checkpoint captured from formal
tea content at main `b60188c23da051a166630f5713e552155d75cbb4`, seed 84,
active-player progression. It contains synthetic test-game state only.

Without end-of-tick target synchronization, advancing by 0.1 seconds to 1350
releases an order-follow scope after the service queue update. The customer's
movement still targets pickup and the formal save validator rejects that tick.
The next tick repairs itself. The regression verifies actual disk saves and
identical post-load continuation before, during, and after that boundary.

Keep this historical checkpoint rather than updating it to a passing replay.
