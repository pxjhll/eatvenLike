# Content updates and saved progress

Shop saves now use wrapper version 2 and record `content.version`, `content.gameplay`
and `content.structure` fingerprints. Identical gameplay resumes the exact saved
state. Valid version 1 saves are treated as legacy and refreshed against current
definitions; no migration writes occur during loading.
Version 1 has no original content fingerprints, so compatibility is assessed by
validating its saved state against current definitions.

Content updates must never lock a player out of a shop (user rule 2026-11-09:
an update must not make a player lose the shop they were playing). Both numeric
and structural changes (layout geometry, level counts, recipe routes, removed
stations/materials/tracks) are migrated: the saved state is validated against
the current definitions and refreshed. IDs that no longer exist are dropped (the
raw `ShopRules.load_dict` merge), so only progress tied to removed content is
lost; new IDs get current defaults. `BY_DATA_ID` maps must still be dictionaries
with string keys. If validation fails, or the file belongs to another shop ID,
the original is quarantined as `.corrupt-*` and the shop opens empty with a
notice. Only saves written by a newer program (future wrapper or content
version) are protected: their bytes stay in place and startup, saves and fresh
initialization are blocked until a newer program or a retry after repair.

Compatible numeric updates preserve gold, staff, upgrade levels, business progress,
RNG state, event history, and recorded jobs and timers. They adopt current prices,
upgrade effects, staff base stats and station capacities. Non-upgrade modifiers keep
their order and remaining duration; one-shot rewards are never replayed.

Every write reassesses the file currently on disk, including fresh-shop intent and
files replaced after loading. A successful migration copies the exact previous
file to a sibling named `<save>.pre-content-<unix-seconds>-<ticks>` before the atomic
save replaces it. Collision suffixes keep backup names unique. Backups are retained
without automatic deletion, including copies made before unsuccessful writes.
Backup or atomic-write failures preserve the original and allow saving again after
the underlying problem is repaired.

Invalid business state (legacy or after a content update) is quarantined. Malformed envelopes,
binary corruption, malformed v2 metadata and invalid same-content business state
retain the existing `.corrupt-*` quarantine behavior. Failed quarantine blocks
subsequent blind saves; an explicit load/retry reassesses the repaired file.

Deletion also reassesses the current on-disk file. Future and unreadable
replacements are retained without quarantine or deletion, including
when an active session has already refused to save over them. Finishing still
commits the profile first, once; retaining a file during postcommit cleanup does
not report a retryable finish failure. A successful finish seals the old session
against further saves and repeated finishes. Compatible saves can be cleaned up
normally, and a missing file requires no cleanup.

Outgoing rules must use the store's gameplay definitions (equivalent deep copies
are accepted), and their state must pass semantic validation. This prevents old
cached values from being labeled with a newer fingerprint. Fresh-shop marker
acknowledgement occurs only after the guarded shop save succeeds.

Persistent events must be declared in the shop specification. Runtime-only
`add_event` definitions are not part of the store contract and cannot be recovered
by a later store load; outgoing validation uses the same definitions as loading.

The store computes its own content fingerprint once and caches it; autosave does
not re-hash the shop definitions on every write.
