# PocketDemo backend

Local REST server for the recordings app: TypeScript on Bun, one SQLite file. Design and reasoning are in [DESIGN.md](DESIGN.md).

## Run

```bash
cd backend
bun install
bun run start          # http://127.0.0.1:8787, seeds 100 demo recordings on first start
bun run reset          # wipe both databases and reseed (new epoch: clients resync)
bun test               # rule table + HTTP scenarios (conflicts, lost ack, deletes, paging)
bun run typecheck
```

Environment: `PORT` (8787), `HOST` (127.0.0.1), `DATA_DIR` (`backend/data`).

Both iOS simulators share the Mac's network, so both use `http://127.0.0.1:8787`. Each app install sends its own `X-Device-Id`.

## Log viewer

Open **http://127.0.0.1:8787/logs**.

- **Chains** groups events per recording, left to right, with arrows between steps. A repeated `Idempotency-Key` is drawn as a ↻ retry. List fetches form a "sync" chain per device.
- **Timeline** lists every event, newest first.
- Search across event metadata and payloads; combine outcome and device filters to narrow the capture.
- Select a card or timeline row to open its inspector. **Overview** shows request metadata, logged request fields and result details. **Raw JSON** shows the complete event, with syntax highlighting, line numbers, wrapping and copy controls. Related events link requests with the same idempotency key.
- **Pause live** pauses automatic polling; **Refresh** fetches new events on demand. **Clear log** asks for confirmation before deleting captured events.

The page uses React and shadcn/ui components, bundled by Bun's HTML imports and Tailwind plugin. No separate frontend server or build command is needed. The event payload is a diagnostic record, not a full HTTP capture: for example, logged edit fields omit `baseVersion`, and fetch details can summarize the response.

Every event is also printed to stdout as one JSON line.

## API

All `/recordings` requests need `X-Device-Id`. `PATCH` and `DELETE` also need `Idempotency-Key` (the app's mutation id). Timestamps are unix milliseconds.

| Request | Result |
|---|---|
| `GET /recordings/browse?after=&limit=` | The list the user scrolls, newest first: `{ items, nextCursor, hasMore, syncCursor }`. Live recordings only, no transcripts. `syncCursor` is where the change feed starts. |
| `GET /recordings?cursor=&limit=` | The change feed in write order: `{ items, nextCursor, hasMore }`. No transcripts. Deleted items come as `{ id, version, deleted: true }` on delta pages. |
| `GET /recordings/:id` | recording + `transcript`; 410 if deleted |
| `PATCH /recordings/:id` `{ baseVersion, title?, summary? }` | 200 `{ recording, changed }` · 409 conflict · 410 deleted |
| `DELETE /recordings/:id?baseVersion=` | 200 `{ recording }` (tombstone) · 409 conflict |
| `PUT /_sim/devices/:device` `{ dropResponses?, latencyMs? }` | per-simulator faults; `latest` targets the device that sent the most recent request |
| `DELETE /_sim/devices/:device` | clear one device's faults (`latest` works here too) |
| `DELETE /_sim/devices` | clear every fault |
| `X-Sim-Fault: slow` or `drop` header on a PATCH or DELETE | faults that one write only: `slow` imitates an overloaded link (first byte after 0.4–1.2 s, then the reply trickles in at about 100 bytes/s, several seconds in all), `drop` commits and cuts the reply after 1 s. The app's Save menu sends it. After a `drop`, the app keeps the write locally and resends it, without the header, on the next refresh. The menu's "request never reaches the server" choice never reaches the backend, so it has no header and no log entry until that refresh. |

## Reproduce the scenarios with curl

```bash
S=http://127.0.0.1:8787
A=(-H 'X-Device-Id: sim-a' -H 'Content-Type: application/json')
B=(-H 'X-Device-Id: sim-b' -H 'Content-Type: application/json')

# Conflict: both edit rec_0001's title from base version 1
curl -s -X PATCH "${B[@]}" -H 'Idempotency-Key: demo-b-0001' -d '{"baseVersion":1,"title":"From B"}' $S/recordings/rec_0001
curl -s -X PATCH "${A[@]}" -H 'Idempotency-Key: demo-a-0001' -d '{"baseVersion":1,"title":"From A"}' $S/recordings/rec_0001   # 409

# Lost ack: the next write from sim-a commits, then the socket is cut
curl -s -X PUT -d '{"dropResponses":1}' $S/_sim/devices/latest
curl -s -X PATCH "${A[@]}" -H 'Idempotency-Key: demo-a-0002' -d '{"baseVersion":2,"summary":"Lost reply"}' $S/recordings/rec_0002   # empty reply
curl -si -X PATCH "${A[@]}" -H 'Idempotency-Key: demo-a-0002' -d '{"baseVersion":2,"summary":"Lost reply"}' $S/recordings/rec_0002 | grep -i replayed

# Delete, then an edit from the other device gets 410
curl -s -X DELETE "${B[@]}" -H 'Idempotency-Key: demo-b-0003' "$S/recordings/rec_0003?baseVersion=3"
curl -s -X PATCH "${A[@]}" -H 'Idempotency-Key: demo-a-0003' -d '{"baseVersion":3,"title":"Too late"}' $S/recordings/rec_0003
```

Then watch the chains appear in `/logs`.

## Layout

```
src/domain.ts   types and the one EDITABLE_FIELDS list
src/rules.ts    pure conflict rule (decideEdit, decideDelete)
src/store.ts    the only SQLite code: schema, version clock, cursors, browse, idempotency ledger
src/server.ts   routes, request parsing, outcome → HTTP, event per request, lost-ack fault
src/events.ts   structured event log (separate SQLite file)
src/faults.ts   per-device dropResponses / latencyMs
src/viewer.html the /logs HTML entry
src/viewer/     React log viewer, data projection helpers, JSON previews and styles
src/components/ui/ shadcn/ui primitives (official new-york-v4 registry)
src/seed-data.json  100 synthetic recordings (title, summary, transcript lines)
src/seed.ts     loads seed-data.json; every 25th recording gets a 3000-segment transcript
```
