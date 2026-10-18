# Known limitations

Things intentionally simplified or left for a later revision.

## Multi-field edits are sent as separate requests

**Today:** each row in the app's `mutations` table holds one field change (`field` = `title` or `summary`). If the user edits both the title and the summary of the same recording, the Supervisor sends two `PATCH` requests, one per row, in order.

**Why it's fine for now:** it's correct. The server's conflict check is per field and knows which device made each field's latest change, so the second request isn't blocked by the first one's write. On localhost the extra round trip costs nothing. It also keeps every row, request and conflict about exactly one field.

**Next revision:** merge (union) a recording's pending edit rows before sending. The Supervisor would group consecutive `pending` edit rows for the same `record_id`, combine them into one `PATCH {baseVersion, title, summary}`, and mark all of them with the reply. If the same field was edited more than once, the latest row's value wins and the earliest row's `old_value` stays the merge base. The server already accepts both fields in one request, so this is an app-only change. Things to settle then:

- which id to send as `Idempotency-Key` for a merged request (for example a new id saved before the first send, mapped to the grouped rows);
- freezing the group once it's in flight, so later edits start a new group;
- a conflict on one field holds back the other field in the same request (the server applies all or nothing per request).

## Unresolved conflicts are lost on reinstall

Pending edits and unresolved conflicts live only in the app's local database. Reinstalling the app loses them. The server keeps no copy of the app's mutations.

## No restore after delete

If one device edits a recording that another device already deleted, the server returns 410. The app tells the user the recording no longer exists and removes it locally. There is no undelete.

## One version counter for the whole server

**Today:** every write to any recording takes the next number from one server-wide counter. That number is both the conflict check and the refresh cursor, which is why a recording can jump from v37 to v119: the server made 81 other writes in between, counting the rest of the seed. It is correct only because one Bun process does all writes with synchronous SQLite. The number is assigned inside the write transaction, so commits happen in version order.

**Used in production?** Yes, in this narrow form. Replicache documents the same design, one global version returned as the pull cookie with pushes serialized, as its recommended starting strategy ([Replicache: global version](https://doc.replicache.dev/strategies/global-version)). Larger systems use a scoped variant instead: ElectricSQL's cursor embeds the Postgres log position and is kept per shape ([LogOffset](https://electric.hexdocs.pm/Electric.Replication.LogOffset.html)), and CouchDB's changes sequence became an opaque, per-shard value once it was clustered ([CouchDB 2.0 notes](https://docs.couchdb.org/en/3.5.1/_sources/whatsnew/2.0.rst.txt)).

**What breaks at scale:**

- **Several writers.** If a number is taken before its transaction commits, a refresh can read v4 while v3 is still uncommitted, move its cursor past v3 and never download it. Postgres sequences behave this way, and they also leave gaps on rollback ([Postgres sequence functions](https://www.postgresql.org/docs/current/functions-sequence.html)). Replicache says not to use a Postgres sequence or `NOW()` for this version.
- **One lock for every write.** Serialized writes make the counter a global lock. Replicache's worked example gets about 50 pushes per second at 20 ms per push.
- **Many shards.** Computing one sequence across shards is expensive, which is why CouchDB added `seq_interval` ([CouchDB changes feed](https://docs.couchdb.org/en/2.3.1/api/database/changes.html)).

**Next revision:** for one server with one database, nothing needs to change. With several writers or shards, the usual fix is a counter per scope (per user, space or shard) with a cursor per scope, or a cursor taken from a commit-ordered log such as Postgres logical replication. I found no source that names per-user counters as the standard answer, so treat that choice as untested.

## Transcript cache limit is a fixed, experimental number

**Today:** cached transcripts share one limit, `TranscriptRecord.cacheLimitBytes` = 30 MB. When a new transcript pushes the total over it, the least recently opened transcripts are evicted. An evicted transcript is fetched again the next time its recording is opened, so nothing is lost except offline access to it.

**Why it's experimental:** 30 MB is a starting number, not measured against real recordings or devices.

**Next revision:** a dynamic cache is still an open exploration. Examples: sizing the budget from free disk space, keeping transcripts the user opens often, or prefetching likely ones on Wi-Fi. It can clearly be improved, but it is out of scope for this revision.

## A conflict blocks new edits to the whole recording

While a recording has an unresolved conflict, the editor refuses new edits and deletes for it ("Resolve the recording's conflict first."), even for the field that isn't in conflict. Rows that were already queued for the other field still send. Allowing new edits to the other field is possible because the server checks each field separately, but it was left out to keep the conflict screen simple.

## Offline browsing shows only loaded pages

The list loads 30 recordings per page as the user scrolls. Offline, only pages loaded before going offline are available; the list footer says so. Edits to recordings past the loaded pages are picked up when browsing reaches them, not by the change feed.

## Approaches I'm not fully confident in

I built these from Apple and library documentation, web research or the reference app's code. They pass the build and, where noted, the verification scripts, but I have not confirmed them on a device or with a profiler.

- **Off-main startup.** `PocketDB.live()` is a `@concurrent` function, based on the Swift 6.2 concurrency documentation. I did not measure launch with Instruments to confirm the main thread no longer waits on SQLite.
- **Registering dependencies after an `await`.** `prepareDependencies` runs once the database is open, not at the start of launch. The swift-dependencies docs show it called early and once. The app holds feature screens behind a progress view until then, so no feature reads a dependency first.
- **Toolbar glass morph on iOS 26.** The detail screen's bottom toolbar morphs only when its items use the system's shared glass background. I found that by trying variants, not from documentation, and Delete moved to the leading side for the same reason.
- **Infinite scroll trigger.** The next page loads when the first of the last 10 rows appears, a pattern copied from the reference app. I have not tested fast scrolling or very large text sizes on a simulator.
- **Change feed past the browse edge.** The app skips feed items for recordings it has not browsed to yet and picks them up when scrolling reaches them. The verification script covers edits past the edge. It does not cover another device deleting the last browsed recording.
- **Interrupted server reset.** Resuming a reset after a relaunch passes the verification script, which drives the database directly. I have not run it on two simulators with real network delays.
- **Detail previews.** The Xcode previews build, but I have not opened them in the canvas.
