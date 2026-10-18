import { Database } from "bun:sqlite";
import { z } from "zod";
import {
  EDITABLE_FIELDS,
  LIMITS,
  type AppliedResult,
  type BrowseCursor,
  type BrowseResult,
  type Cursor,
  type DeleteCommand,
  type DeletedRecording,
  type DeviceId,
  type EditableField,
  type EditCommand,
  type IdempotencyKey,
  type ListResult,
  type LiveRecording,
  type NewRecording,
  type PageLimit,
  type RecordingDetail,
  type RecordingHead,
  type RecordingId,
  type TranscriptSegment,
  type Version,
  type WriteOutcome,
} from "./domain";
import { decideDelete, decideEdit, type RowState } from "./rules";

/**
 * The only module that touches the recordings database. One connection, synchronous methods:
 * Bun runs every request on one thread and bun:sqlite never yields, so each transaction runs to
 * completion before the next request is handled. That is what makes `version` commit in order,
 * which the feed cursor relies on. A second writer process would break it.
 */
export type GetResult =
  | { readonly kind: "live"; readonly detail: RecordingDetail }
  | { readonly kind: "deleted"; readonly head: DeletedRecording }
  | { readonly kind: "not_found" };

const SCHEMA = `
  PRAGMA journal_mode = WAL;
  PRAGMA synchronous = NORMAL;
  PRAGMA foreign_keys = ON;
  PRAGMA busy_timeout = 5000;

  CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  ) STRICT;

  CREATE TABLE IF NOT EXISTS recordings (
    id              TEXT    PRIMARY KEY,
    title           TEXT    NOT NULL CHECK (trim(title) <> ''),
    summary         TEXT    NOT NULL,
    created_at      INTEGER NOT NULL,
    updated_at      INTEGER NOT NULL,
    updated_by      TEXT,
    deleted         INTEGER NOT NULL DEFAULT 0 CHECK (deleted IN (0, 1)),
    version         INTEGER NOT NULL,
    title_version   INTEGER NOT NULL,
    title_by        TEXT,
    title_at        INTEGER NOT NULL,
    summary_version INTEGER NOT NULL,
    summary_by      TEXT,
    summary_at      INTEGER NOT NULL,
    CHECK (title_version <= version AND summary_version <= version)
  ) STRICT;

  CREATE UNIQUE INDEX IF NOT EXISTS recordings_by_version ON recordings(version);
  CREATE INDEX IF NOT EXISTS recordings_by_created ON recordings(created_at DESC, id DESC);

  CREATE TRIGGER IF NOT EXISTS recordings_version_grows
  BEFORE UPDATE ON recordings
  WHEN NEW.version <= OLD.version OR NEW.id IS NOT OLD.id OR NEW.created_at IS NOT OLD.created_at
    OR (OLD.deleted = 1 AND NEW.deleted = 0)
  BEGIN SELECT RAISE(ABORT, 'recordings: version must grow; id, created_at and tombstones are fixed'); END;

  CREATE TRIGGER IF NOT EXISTS recordings_no_delete BEFORE DELETE ON recordings
  BEGIN SELECT RAISE(ABORT, 'recordings are tombstoned, never removed'); END;

  CREATE TABLE IF NOT EXISTS transcripts (
    recording_id  TEXT    PRIMARY KEY REFERENCES recordings(id),
    segments      TEXT    NOT NULL CHECK (json_valid(segments)),
    segment_count INTEGER NOT NULL
  ) STRICT;

  CREATE TRIGGER IF NOT EXISTS transcripts_no_update BEFORE UPDATE ON transcripts
  BEGIN SELECT RAISE(ABORT, 'transcript is immutable'); END;

  CREATE TRIGGER IF NOT EXISTS transcripts_no_delete BEFORE DELETE ON transcripts
  BEGIN SELECT RAISE(ABORT, 'transcript is immutable'); END;

  CREATE TABLE IF NOT EXISTS applied_ops (
    key           TEXT    PRIMARY KEY,
    device_id     TEXT    NOT NULL,
    recording_id  TEXT    NOT NULL REFERENCES recordings(id),
    request_hash  TEXT    NOT NULL,
    result_json   TEXT    NOT NULL,
    created_at    INTEGER NOT NULL
  ) STRICT;
`;

interface RecordingRow {
  id: string;
  title: string;
  summary: string;
  created_at: number;
  updated_at: number;
  updated_by: string | null;
  deleted: number;
  version: number;
  title_version: number;
  title_by: string | null;
  title_at: number;
  summary_version: number;
  summary_by: string | null;
  summary_at: number;
  segment_count: number;
}

const ROW_COLUMNS = `
  r.id, r.title, r.summary, r.created_at, r.updated_at, r.updated_by, r.deleted, r.version,
  r.title_version, r.title_by, r.title_at, r.summary_version, r.summary_by, r.summary_at,
  t.segment_count`;

// Values read back from our own STRICT tables were validated on the way in.
const dbRecordingId = (value: string) => value as RecordingId;
const dbVersion = (value: number) => value as Version;
const dbDevice = (value: string | null) => value as DeviceId | null;

function toHead(row: RecordingRow): RecordingHead {
  if (row.deleted === 1) {
    return {
      kind: "deleted",
      id: dbRecordingId(row.id),
      version: dbVersion(row.version),
      updatedAt: row.updated_at,
      updatedBy: dbDevice(row.updated_by),
    };
  }
  return toLive(row);
}

function toLive(row: RecordingRow): LiveRecording {
  return {
    kind: "live",
    id: dbRecordingId(row.id),
    title: row.title,
    summary: row.summary,
    version: dbVersion(row.version),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    updatedBy: dbDevice(row.updated_by),
    segmentCount: row.segment_count,
  };
}

function toDeleted(row: RecordingRow): DeletedRecording {
  return {
    kind: "deleted",
    id: dbRecordingId(row.id),
    version: dbVersion(row.version),
    updatedAt: row.updated_at,
    updatedBy: dbDevice(row.updated_by),
  };
}

function toRowState(row: RecordingRow): RowState {
  return {
    version: dbVersion(row.version),
    fields: {
      title: { value: row.title, version: dbVersion(row.title_version), by: dbDevice(row.title_by), at: row.title_at },
      summary: {
        value: row.summary,
        version: dbVersion(row.summary_version),
        by: dbDevice(row.summary_by),
        at: row.summary_at,
      },
    },
  };
}

const liveSchema = z.object({
  kind: z.literal("live"),
  id: z.string(),
  title: z.string(),
  summary: z.string(),
  version: z.number(),
  createdAt: z.number(),
  updatedAt: z.number(),
  updatedBy: z.string().nullable(),
  segmentCount: z.number(),
});

const appliedSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("edited"), recording: liveSchema, changed: z.array(z.enum(EDITABLE_FIELDS)) }),
  z.object({
    kind: z.literal("deleted"),
    recording: z.object({
      kind: z.literal("deleted"),
      id: z.string(),
      version: z.number(),
      updatedAt: z.number(),
      updatedBy: z.string().nullable(),
    }),
  }),
]);

/** Ledger rows hold the exact result of the original write, so a replay never reflects later writes. */
function decodeApplied(json: string): AppliedResult {
  const parsed = appliedSchema.parse(JSON.parse(json));
  switch (parsed.kind) {
    case "edited":
      return {
        kind: "edited",
        changed: parsed.changed,
        recording: {
          ...parsed.recording,
          id: dbRecordingId(parsed.recording.id),
          version: dbVersion(parsed.recording.version),
          updatedBy: dbDevice(parsed.recording.updatedBy),
        },
      };
    case "deleted":
      return {
        kind: "deleted",
        recording: {
          ...parsed.recording,
          id: dbRecordingId(parsed.recording.id),
          version: dbVersion(parsed.recording.version),
          updatedBy: dbDevice(parsed.recording.updatedBy),
        },
      };
    default: {
      const _exhaustive: never = parsed;
      return _exhaustive;
    }
  }
}

function requestHash(parts: readonly unknown[]): string {
  return new Bun.CryptoHasher("sha256").update(JSON.stringify(parts)).digest("hex");
}

export function encodeCursor(cursor: Cursor): string {
  return `${cursor.epoch}:v${cursor.after}`;
}

/** null when the string isn't a cursor at all; the epoch check happens in `list`. */
export function decodeCursor(raw: string): Cursor | null {
  const match = /^([0-9a-f-]{36}):v(0|[1-9]\d{0,15})$/.exec(raw);
  if (!match?.[1] || !match[2]) return null;
  const after = Number(match[2]);
  return { epoch: match[1], after: after === 0 ? 0 : dbVersion(after) };
}

export function encodeBrowseCursor(cursor: BrowseCursor): string {
  return `${cursor.epoch}:c${cursor.createdAt}:${cursor.id}`;
}

/** null when the string isn't a browse cursor at all; the epoch check happens in `browse`. */
export function decodeBrowseCursor(raw: string): BrowseCursor | null {
  const match = /^([0-9a-f-]{36}):c(0|[1-9]\d{0,15}):([A-Za-z0-9_-]{1,64})$/.exec(raw);
  if (!match?.[1] || !match[2] || !match[3]) return null;
  return { epoch: match[1], createdAt: Number(match[2]), id: dbRecordingId(match[3]) };
}

type LedgerCheck =
  | { readonly kind: "fresh" }
  | { readonly kind: "replay"; readonly result: AppliedResult }
  | { readonly kind: "key_reused" };

export class RecordingStore {
  readonly epoch: string;

  private constructor(
    private readonly db: Database,
    private readonly now: () => number,
  ) {
    db.run("INSERT OR IGNORE INTO meta (key, value) VALUES ('epoch', ?)", [crypto.randomUUID()]);
    const row = db.query<{ value: string }, []>("SELECT value FROM meta WHERE key = 'epoch'").get();
    if (!row) throw new Error("meta.epoch missing after insert");
    this.epoch = row.value;
  }

  static open({ path, now = Date.now }: { path: string; now?: () => number }): RecordingStore {
    const db = new Database(path, { create: true, strict: true });
    db.exec(SCHEMA);
    return new RecordingStore(db, now);
  }

  count(): number {
    return this.db.query<{ n: number }, []>("SELECT count(*) AS n FROM recordings").get()?.n ?? 0;
  }

  /**
   * First sync, paging and refresh are one call. Rows come back in version order; an edited row
   * moves past every cursor, so a walk never skips anything (it may see a row twice, at a newer state).
   * A first sync (no cursor) leaves out tombstones: a fresh device has nothing to delete.
   */
  list({ cursor, limit }: { cursor: Cursor | null; limit: PageLimit }): ListResult {
    if (cursor && cursor.epoch !== this.epoch) return { kind: "cursor_reset" };
    const after = cursor?.after ?? 0;
    if (after > this.maxVersion()) return { kind: "cursor_reset" };

    const rows = this.db
      .query<RecordingRow, { after: number; limit: number; live_only: number }>(
        `SELECT ${ROW_COLUMNS} FROM recordings r JOIN transcripts t ON t.recording_id = r.id
         WHERE r.version > $after AND ($live_only = 0 OR r.deleted = 0)
         ORDER BY r.version LIMIT $limit`,
      )
      .all({ after, limit: limit + 1, live_only: cursor ? 0 : 1 });

    const items = rows.slice(0, limit).map(toHead);
    const last = items.at(-1);
    return {
      kind: "page",
      page: { items, hasMore: rows.length > limit, next: { epoch: this.epoch, after: last ? last.version : after } },
    };
  }

  /**
   * The list the user scrolls: live rows, newest first, keyset-paged on (created_at, id).
   * Every page also returns the feed cursor read in the same synchronous call, so a device that
   * starts from the first page and then follows `list` from that cursor misses no later change.
   */
  browse({ cursor, limit }: { cursor: BrowseCursor | null; limit: PageLimit }): BrowseResult {
    if (cursor && cursor.epoch !== this.epoch) return { kind: "cursor_reset" };
    const rows = this.db
      .query<RecordingRow, { first: number; created: number; id: string; limit: number }>(
        `SELECT ${ROW_COLUMNS} FROM recordings r JOIN transcripts t ON t.recording_id = r.id
         WHERE r.deleted = 0
           AND ($first = 1 OR r.created_at < $created OR (r.created_at = $created AND r.id < $id))
         ORDER BY r.created_at DESC, r.id DESC LIMIT $limit`,
      )
      .all({ first: cursor ? 0 : 1, created: cursor?.createdAt ?? 0, id: cursor?.id ?? "", limit: limit + 1 });
    const items = rows.slice(0, limit).map(toLive);
    const last = items.at(-1);
    return {
      kind: "page",
      page: {
        items,
        hasMore: rows.length > limit,
        next: last ? { epoch: this.epoch, createdAt: last.createdAt, id: last.id } : cursor,
        sync: { epoch: this.epoch, after: dbVersion(this.maxVersion()) },
      },
    };
  }

  /** Head only, no transcript. */
  head(id: RecordingId): RecordingHead | null {
    const row = this.row(id);
    return row ? toHead(row) : null;
  }

  get(id: RecordingId): GetResult {
    const row = this.row(id);
    if (!row) return { kind: "not_found" };
    if (row.deleted === 1) return { kind: "deleted", head: toDeleted(row) };
    const segments = this.db
      .query<{ segments: string }, { id: string }>("SELECT segments FROM transcripts WHERE recording_id = $id")
      .get({ id });
    if (!segments) throw new Error(`recording ${id} has no transcript row`);
    const transcript = z.array(z.object({ startMs: z.number(), text: z.string() })).parse(JSON.parse(segments.segments));
    return { kind: "live", detail: { head: toLive(row), transcript } };
  }

  edit(cmd: EditCommand): WriteOutcome {
    return this.db
      .transaction((): WriteOutcome => {
        const hash = requestHash(["edit", cmd.device, cmd.id, cmd.baseVersion, cmd.edits.title ?? null, cmd.edits.summary ?? null]);
        const ledger = this.checkLedger({ key: cmd.key, hash });
        if (ledger.kind === "replay") return { kind: "applied", result: ledger.result, replayed: true };
        if (ledger.kind === "key_reused") return { kind: "key_reused" };

        const row = this.row(cmd.id);
        if (!row) return { kind: "not_found" };
        // Checked before the conflict rule: an edit to a deleted recording can't be resolved, only dropped.
        if (row.deleted === 1) return { kind: "gone", current: toDeleted(row) };

        const decision = decideEdit({ row: toRowState(row), baseVersion: cmd.baseVersion, device: cmd.device, edits: cmd.edits });
        switch (decision.kind) {
          case "base_ahead":
            return { kind: "base_ahead", current: toLive(row) };
          case "conflict":
            return { kind: "conflict", fields: decision.fields, current: toLive(row) };
          case "noop": {
            const result: AppliedResult = { kind: "edited", recording: toLive(row), changed: [] };
            this.record({ key: cmd.key, device: cmd.device, id: cmd.id, hash, result });
            return { kind: "applied", result, replayed: false };
          }
          case "write": {
            const changed = EDITABLE_FIELDS.filter((field) => decision.set[field] !== undefined);
            const updated = this.writeFields({ id: cmd.id, device: cmd.device, set: decision.set, changed });
            const result: AppliedResult = { kind: "edited", recording: toLive(updated), changed };
            this.record({ key: cmd.key, device: cmd.device, id: cmd.id, hash, result });
            return { kind: "applied", result, replayed: false };
          }
          default: {
            const _exhaustive: never = decision;
            return _exhaustive;
          }
        }
      })
      .immediate();
  }

  delete(cmd: DeleteCommand): WriteOutcome {
    return this.db
      .transaction((): WriteOutcome => {
        const hash = requestHash(["delete", cmd.device, cmd.id, cmd.baseVersion]);
        const ledger = this.checkLedger({ key: cmd.key, hash });
        if (ledger.kind === "replay") return { kind: "applied", result: ledger.result, replayed: true };
        if (ledger.kind === "key_reused") return { kind: "key_reused" };

        const row = this.row(cmd.id);
        if (!row) return { kind: "not_found" };
        if (row.deleted === 1) {
          // Deleting twice is harmless: report the existing tombstone without writing.
          const result: AppliedResult = { kind: "deleted", recording: toDeleted(row) };
          this.record({ key: cmd.key, device: cmd.device, id: cmd.id, hash, result });
          return { kind: "applied", result, replayed: false };
        }

        const decision = decideDelete({ row: toRowState(row), baseVersion: cmd.baseVersion, device: cmd.device });
        switch (decision.kind) {
          case "base_ahead":
            return { kind: "base_ahead", current: toLive(row) };
          case "conflict":
            return { kind: "conflict", fields: decision.fields, current: toLive(row) };
          case "delete": {
            const tombstone = this.writeTombstone({ id: cmd.id, device: cmd.device });
            const result: AppliedResult = { kind: "deleted", recording: toDeleted(tombstone) };
            this.record({ key: cmd.key, device: cmd.device, id: cmd.id, hash, result });
            return { kind: "applied", result, replayed: false };
          }
          default: {
            const _exhaustive: never = decision;
            return _exhaustive;
          }
        }
      })
      .immediate();
  }

  /** The single creation path. Used by the seed and tests; HTTP never creates recordings. */
  importRecording(rec: NewRecording): void {
    this.db
      .transaction(() => {
        const version = this.nextVersion();
        this.exec(
          `INSERT INTO recordings (id, title, summary, created_at, updated_at, updated_by, version,
             title_version, title_by, title_at, summary_version, summary_by, summary_at)
           VALUES ($id, $title, $summary, $created_at, $created_at, NULL, $version,
             $version, NULL, $created_at, $version, NULL, $created_at)`,
          { id: rec.id, title: rec.title, summary: rec.summary, created_at: rec.createdAt, version },
        );
        this.exec(
          "INSERT INTO transcripts (recording_id, segments, segment_count) VALUES ($id, $segments, $count)",
          { id: rec.id, segments: JSON.stringify(rec.transcript satisfies readonly TranscriptSegment[]), count: rec.transcript.length },
        );
      })
      .immediate();
  }

  /** Keys only need to outlive a client's retry window. */
  pruneAppliedOps(): number {
    const cutoff = this.now() - LIMITS.appliedOpsRetentionMs;
    return this.exec("DELETE FROM applied_ops WHERE created_at < $cutoff", { cutoff }).changes;
  }

  close(): void {
    this.db.close();
  }

  private exec(sql: string, params: Record<string, string | number | null>) {
    return this.db.query<unknown, [Record<string, string | number | null>]>(sql).run(params);
  }

  private row(id: RecordingId): RecordingRow | null {
    return this.db
      .query<RecordingRow, { id: string }>(
        `SELECT ${ROW_COLUMNS} FROM recordings r JOIN transcripts t ON t.recording_id = r.id WHERE r.id = $id`,
      )
      .get({ id });
  }

  private maxVersion(): number {
    return this.db.query<{ v: number }, []>("SELECT coalesce(MAX(version), 0) AS v FROM recordings").get()?.v ?? 0;
  }

  private nextVersion(): Version {
    return dbVersion(this.maxVersion() + 1);
  }

  private checkLedger({ key, hash }: { key: IdempotencyKey; hash: string }): LedgerCheck {
    const prior = this.db
      .query<{ request_hash: string; result_json: string }, { key: string }>(
        "SELECT request_hash, result_json FROM applied_ops WHERE key = $key",
      )
      .get({ key });
    if (!prior) return { kind: "fresh" };
    if (prior.request_hash !== hash) return { kind: "key_reused" };
    return { kind: "replay", result: decodeApplied(prior.result_json) };
  }

  private record({ key, device, id, hash, result }: {
    key: IdempotencyKey;
    device: DeviceId;
    id: RecordingId;
    hash: string;
    result: AppliedResult;
  }): void {
    this.exec(
      `INSERT INTO applied_ops (key, device_id, recording_id, request_hash, result_json, created_at)
       VALUES ($key, $device, $id, $hash, $result, $now)`,
      { key, device, id, hash, result: JSON.stringify(result), now: this.now() },
    );
  }

  private writeFields({ id, device, set, changed }: {
    id: RecordingId;
    device: DeviceId;
    set: Partial<Record<EditableField, string>>;
    changed: readonly EditableField[];
  }): RecordingRow {
    const version = this.nextVersion();
    const now = this.now();
    this.exec(
      `UPDATE recordings SET
         title           = CASE WHEN $set_title   THEN $title   ELSE title END,
         title_version   = CASE WHEN $set_title   THEN $version ELSE title_version END,
         title_by        = CASE WHEN $set_title   THEN $device  ELSE title_by END,
         title_at        = CASE WHEN $set_title   THEN $now     ELSE title_at END,
         summary         = CASE WHEN $set_summary THEN $summary ELSE summary END,
         summary_version = CASE WHEN $set_summary THEN $version ELSE summary_version END,
         summary_by      = CASE WHEN $set_summary THEN $device  ELSE summary_by END,
         summary_at      = CASE WHEN $set_summary THEN $now     ELSE summary_at END,
         version = $version, updated_at = $now, updated_by = $device
       WHERE id = $id`,
      {
        id,
        device,
        version,
        now,
        title: set.title ?? "",
        summary: set.summary ?? "",
        set_title: changed.includes("title") ? 1 : 0,
        set_summary: changed.includes("summary") ? 1 : 0,
      },
    );
    return this.mustRow(id);
  }

  private writeTombstone({ id, device }: { id: RecordingId; device: DeviceId }): RecordingRow {
    this.exec(
      "UPDATE recordings SET deleted = 1, version = $version, updated_at = $now, updated_by = $device WHERE id = $id",
      { id, device, version: this.nextVersion(), now: this.now() },
    );
    return this.mustRow(id);
  }

  private mustRow(id: RecordingId): RecordingRow {
    const row = this.row(id);
    if (!row) throw new Error(`recording ${id} vanished inside its own transaction`);
    return row;
  }
}
