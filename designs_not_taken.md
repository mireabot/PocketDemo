# Designs not taken

Approaches I considered and dropped, with the reason each one didn't fit.

## 1. `updated_at` timestamp as the version check

**Idea:** the client sends the `updated_at` it last saw; the server rejects the edit if the row's `updated_at` has moved on. The same timestamp doubles as the "changed since" cursor for refresh.

**Why not:**

- **Same-millisecond writes share a timestamp.** If two devices write the same recording within one millisecond, both writes carry the same `updated_at`. A device whose base is already stale then looks current, so its edit passes the check and silently overwrites the other one. That's a conflict that never gets detected.
- **Clocks aren't monotonic.** Device clocks drift and users can change them. Even the server's clock can step backwards when NTP corrects it, which makes a newer write look older.
- **It's a weak refresh cursor.** With `updated_at > :cursor`, a page that ends in the middle of rows sharing a timestamp skips the rest of them. A row stamped earlier than a cursor a device already holds is never fetched.
- **Fixing it means building a counter anyway.** A correct version needs `max(now, last + 1)` plus an `(updated_at, id)` cursor, and a separate timestamp for each field. That is a version counter measured in milliseconds.

**Chosen instead:** a server-wide integer `version` (`MAX + 1` on every write, unique index). It is both the per-recording conflict token and the refresh cursor. `updated_at` is kept for display only ("edited 5 min ago").

## 2. The `old` value as the conflict check (compare-and-set)

**Idea:** each mutation sends `{ old, new }`; the server applies it only if the current value still equals `old`.

**Why not:**

- **Payload size.** Summaries can be long, and every edit would send the full old text alongside the new text, roughly doubling upload size per edit.
- **It can't say who changed a field or when.** A value mismatch only says "it's different now", so the conflict screen can't show "edited on sim-b, 2 min ago".
- **It still gets lost acks wrong.** Suppose my edit was applied, the reply was lost, and another device changed the field before my retry. The retry's `old` no longer matches, so I get a false conflict against my own applied edit. Telling those apart needs the idempotency key anyway.
- **It's a second notion of "what I saw".** The refresh cursor already tracks that with `version`; `old` would duplicate it.

**Chosen instead:** `baseVersion` plus per-field versions (`title_version`, `summary_version`) and per-field last writer (`title_by`, `summary_by`), with the mutation id sent as `Idempotency-Key`.

The app still keeps `old` in its mutations table, but only as the base for its 3-way merge (base / mine / server) on the conflict screen. It is never sent to the server.
