import { Database } from "bun:sqlite";
import type { DeviceId, IdempotencyKey, RecordingId } from "./domain";

/**
 * Structured event log. One event per handled request (plus fault and control events), kept in its
 * own SQLite file so logging can never block or roll back a recordings write. The log viewer at
 * /logs reads it; every event is also written to stdout as one JSON line.
 */
export const EVENT_KINDS = [
  "list",
  "list.cursor_reset",
  "browse",
  "browse.cursor_reset",
  "detail",
  "detail.gone",
  "edit.applied",
  "edit.noop",
  "edit.replayed",
  "edit.conflict",
  "edit.gone",
  "delete.applied",
  "delete.noop",
  "delete.replayed",
  "delete.conflict",
  "rejected",
  "not_found",
  "fault.response_dropped",
  "fault.configured",
] as const;
export type EventKind = (typeof EVENT_KINDS)[number];

export interface EventDraft {
  readonly kind: EventKind;
  readonly recordingId: RecordingId | null;
  /** One line a human reads in the viewer, e.g. `title "A" → "B" (v41 → v302)`. */
  readonly summary: string;
  readonly detail: Readonly<Record<string, unknown>>;
}

export interface RequestMeta {
  readonly requestId: string;
  readonly device: DeviceId | null;
  readonly method: string;
  readonly path: string;
  readonly key: IdempotencyKey | null;
}

export interface LoggedEvent {
  readonly id: number;
  readonly at: number;
  readonly requestId: string;
  readonly device: string | null;
  readonly method: string;
  readonly path: string;
  readonly status: number;
  readonly durationMs: number;
  readonly kind: EventKind;
  readonly recordingId: string | null;
  readonly key: string | null;
  readonly summary: string;
  readonly detail: unknown;
}

interface EventRow {
  id: number;
  at: number;
  request_id: string;
  device: string | null;
  method: string;
  path: string;
  status: number;
  duration_ms: number;
  kind: EventKind;
  recording_id: string | null;
  idem_key: string | null;
  summary: string;
  detail: string;
}

const SCHEMA = `
  PRAGMA journal_mode = WAL;
  PRAGMA synchronous = NORMAL;
  CREATE TABLE IF NOT EXISTS events (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    at           INTEGER NOT NULL,
    request_id   TEXT    NOT NULL,
    device       TEXT,
    method       TEXT    NOT NULL,
    path         TEXT    NOT NULL,
    status       INTEGER NOT NULL,
    duration_ms  INTEGER NOT NULL,
    kind         TEXT    NOT NULL,
    recording_id TEXT,
    idem_key     TEXT,
    summary      TEXT    NOT NULL,
    detail       TEXT    NOT NULL CHECK (json_valid(detail))
  ) STRICT;
`;

export class EventLog {
  private constructor(
    private readonly db: Database,
    private readonly echo: boolean,
  ) {}

  static open({ path, echo = true }: { path: string; echo?: boolean }): EventLog {
    const db = new Database(path, { create: true, strict: true });
    db.exec(SCHEMA);
    return new EventLog(db, echo);
  }

  write({ meta, draft, status, startedAt }: { meta: RequestMeta; draft: EventDraft; status: number; startedAt: number }): void {
    const at = Date.now();
    const row = {
      at,
      request_id: meta.requestId,
      device: meta.device,
      method: meta.method,
      path: meta.path,
      status,
      duration_ms: Math.round(performance.now() - startedAt),
      kind: draft.kind,
      recording_id: draft.recordingId,
      idem_key: meta.key,
      summary: draft.summary,
      detail: JSON.stringify(draft.detail),
    };
    this.exec(
      `INSERT INTO events (at, request_id, device, method, path, status, duration_ms, kind, recording_id, idem_key, summary, detail)
       VALUES ($at, $request_id, $device, $method, $path, $status, $duration_ms, $kind, $recording_id, $idem_key, $summary, $detail)`,
      row,
    );
    if (this.echo) process.stdout.write(`${JSON.stringify({ ...row, detail: draft.detail })}\n`);
  }

  after({ id, limit }: { id: number; limit: number }): LoggedEvent[] {
    return this.db
      .query<EventRow, { id: number; limit: number }>("SELECT * FROM events WHERE id > $id ORDER BY id LIMIT $limit")
      .all({ id, limit })
      .map((row) => ({
        id: row.id,
        at: row.at,
        requestId: row.request_id,
        device: row.device,
        method: row.method,
        path: row.path,
        status: row.status,
        durationMs: row.duration_ms,
        kind: row.kind,
        recordingId: row.recording_id,
        key: row.idem_key,
        summary: row.summary,
        detail: JSON.parse(row.detail),
      }));
  }

  private exec(sql: string, params: Record<string, string | number | null>) {
    return this.db.query<unknown, [Record<string, string | number | null>]>(sql).run(params);
  }

  clear(): void {
    this.db.run("DELETE FROM events");
  }

  close(): void {
    this.db.close();
  }
}
