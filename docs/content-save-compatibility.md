# Content updates and saved progress

Shop saves now use wrapper version 2 and record `content.version`, `content.gameplay`
and `content.structure` fingerprints. Identical gameplay resumes the exact saved
state. Valid version 1 saves are treated as legacy and refreshed against current
definitions; no migration writes occur during loading.
Version 1 has no original content fingerprints, so compatibility can only be
assessed by validating its saved state against current definitions. Historical
geometry or mode changes that leave no invalid saved references cannot be detected.

Compatible numeric updates preserve gold, staff, upgrade levels, business progress,
RNG state, event history, and recorded jobs and timers. They adopt current prices,
upgrade effects, staff base stats and station capacities. Non-upgrade modifiers keep
their order and remaining duration; one-shot rewards are never replayed.

For version 2 saves, structural changes are conservatively blocked: IDs, mode, recipe routes, storage
keys, track level counts, stage order and navigation geometry must still match.
A different saved shop ID at the same destination is also incompatible. Future
wrapper or content versions are protected. These files stay at their original
paths, with their bytes unchanged. Restore compatible content or repair the save,
then use the startup retry button. The same session rereads the repaired file.
Failed startup exposes no rules and disables business processing and saves.

Every write reassesses the file currently on disk, including fresh-shop intent and
files replaced after loading. A successful migration copies the exact previous
file to a sibling named `<save>.pre-content-<unix-seconds>-<ticks>` before the atomic
save replaces it. Collision suffixes keep backup names unique. Backups are retained
without automatic deletion, including copies made before unsuccessful writes.
Backup or atomic-write failures preserve the original and allow saving again after
the underlying problem is repaired.

Invalid legacy business state is protected as incompatible. Malformed envelopes,
binary corruption, malformed v2 metadata and invalid same-content business state
retain the existing `.corrupt-*` quarantine behavior. Failed quarantine blocks
subsequent blind saves; an explicit load/retry reassesses the repaired file.

Outgoing rules must use the store's gameplay definitions (equivalent deep copies
are accepted), and their state must pass semantic validation. This prevents old
cached values from being labeled with a newer fingerprint. Fresh-shop marker
acknowledgement occurs only after the guarded shop save succeeds.

Persistent events must be declared in the shop specification. Runtime-only
`add_event` definitions are not part of the store contract and cannot be recovered
by a later store load; outgoing validation uses the same definitions as loading.
