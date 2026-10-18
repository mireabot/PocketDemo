import type { Server } from "bun";
import { z } from "zod";
import {
  EDITABLE_FIELDS,
  LIMITS,
  type AppliedResult,
  type DeletedRecording,
  type DeviceId,
  type FieldConflict,
  type FieldEdits,
  type IdempotencyKey,
  type LiveRecording,
  type PageLimit,
  type RecordingHead,
  type RecordingId,
  type Version,
  type WriteOutcome,
} from "./domain";
import type { EventDraft, EventLog, RequestMeta } from "./events";
import { faultRuleSchema, type Faults } from "./faults";
import { decodeBrowseCursor, decodeCursor, encodeBrowseCursor, encodeCursor, type RecordingStore } from "./store";
import viewer from "./viewer.html";

/**
 * The HTTP boundary. Owns the wire format: nothing else knows JSON shapes or status codes.
 * Request flow: server.ts (parse wire → domain) → store.ts → rules.ts.
 *
 * Wire conventions: JSON, camelCase, timestamps as unix milliseconds. Every /recordings request
 * carries X-Device-Id; PATCH and DELETE also carry Idempotency-Key (the client's mutation id).
 * Errors are { error: { code, message } } plus extra fields where noted.
 */

type ErrorCode =
  | "missing_device_id"
  | "missing_idempotency_key"
  | "invalid_json"
  | "invalid_id"
  | "invalid_body"
  | "unknown_field"
  | "transcript_immutable"
  | "empty_patch"
  | "invalid_limit"
  | "invalid_cursor"
  | "invalid_base_version"
  | "not_found"
  | "version_conflict"
  | "recording_deleted"
  | "cursor_reset"
  | "idempotency_key_reused"
  | "base_version_ahead";

interface HandlerResult {
  readonly response: Response;
  readonly event: EventDraft;
}

type RouteRequest = Request & { params: Record<string, string> };

interface Ctx {
  readonly req: RouteRequest;
  readonly meta: RequestMeta;
}

type Parsed<T> = { readonly ok: true; readonly value: T } | { readonly ok: false; readonly result: HandlerResult };

// ---------- wire encoding (domain → JSON) ----------

function liveJSON(r: LiveRecording) {
  return {
    id: r.id,
    title: r.title,
    summary: r.summary,
    version: r.version,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
    updatedBy: r.updatedBy,
    segmentCount: r.segmentCount,
    deleted: false,
  };
}

function deletedJSON(r: DeletedRecording) {
  return { id: r.id, version: r.version, updatedAt: r.updatedAt, updatedBy: r.updatedBy, deleted: true };
}

function headJSON(r: RecordingHead) {
  switch (r.kind) {
    case "live":
      return liveJSON(r);
    case "deleted":
      return deletedJSON(r);
    default: {
      const _exhaustive: never = r;
      return _exhaustive;
    }
  }
}

function appliedJSON(result: AppliedResult) {
  switch (result.kind) {
    case "edited":
      return { recording: liveJSON(result.recording), changed: result.changed };
    case "deleted":
      return { recording: deletedJSON(result.recording) };
    default: {
      const _exhaustive: never = result;
      return _exhaustive;
    }
  }
}

function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return Response.json(body, { status, headers });
}

function fail({ status, code, message, extra = {}, event }: {
  status: number;
  code: ErrorCode;
  message: string;
  extra?: Record<string, unknown>;
  event?: Partial<EventDraft>;
}): HandlerResult {
  return {
    response: json(status, { error: { code, message }, ...extra }),
    event: {
      kind: event?.kind ?? "rejected",
      recordingId: event?.recordingId ?? null,
      summary: event?.summary ?? `${status} ${code}: ${message}`,
      detail: event?.detail ?? { code, message },
    },
  };
}

// ---------- boundary parsing (wire → domain) ----------

const ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const DEVICE_PATTERN = /^[A-Za-z0-9._-]{1,64}$/;
const KEY_PATTERN = /^[A-Za-z0-9_-]{8,128}$/;

function parseDevice(req: Request): DeviceId | null {
  const raw = req.headers.get("x-device-id");
  return raw && DEVICE_PATTERN.test(raw) ? (raw as DeviceId) : null;
}

function parseKey(req: Request): IdempotencyKey | null {
  const raw = req.headers.get("idempotency-key");
  return raw && KEY_PATTERN.test(raw) ? (raw as IdempotencyKey) : null;
}

/** One write's simulated fault, sent by the app's Save menu. Retries come without it. */
const simulationSchema = z.enum(["slow", "drop"]).nullable().catch(null);
/**
 * `slow` imitates an overloaded link rather than a fixed wait: the first byte arrives after a
 * random 0.4–1.2 s, then the reply trickles out in small chunks (~100 bytes/s), so a normal
 * write reply takes several seconds and the client's idle timer keeps resetting.
 */
const SLOW_LINK = { firstByteMs: [400, 1200], chunkBytes: 16, chunkDelayMs: 150 } as const;

async function throttle(response: Response): Promise<Response> {
  const bytes = new Uint8Array(await response.arrayBuffer());
  const headers = new Headers(response.headers);
  headers.delete("content-length");
  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      try {
        for (let at = 0; at < bytes.length; at += SLOW_LINK.chunkBytes) {
          controller.enqueue(bytes.slice(at, at + SLOW_LINK.chunkBytes));
          await Bun.sleep(SLOW_LINK.chunkDelayMs);
        }
        controller.close();
      } catch {
        // The client hung up mid-reply; the write has already committed.
      }
    },
  });
  return new Response(body, { status: response.status, headers });
}

function parseSimulation(req: Request): "slow" | "drop" | null {
  return simulationSchema.parse(req.headers.get("x-sim-fault"));
}

function parseRecordingId(raw: string | undefined): Parsed<RecordingId> {
  if (raw && ID_PATTERN.test(raw)) return { ok: true, value: raw as RecordingId };
  return { ok: false, result: fail({ status: 400, code: "invalid_id", message: "recording id must match [A-Za-z0-9_-]{1,64}" }) };
}

function parseBaseVersion(raw: unknown): Parsed<Version> {
  const parsed = z.coerce.number().int().positive().safeParse(raw);
  if (parsed.success) return { ok: true, value: parsed.data as Version };
  return { ok: false, result: fail({ status: 400, code: "invalid_base_version", message: "baseVersion must be a positive integer" }) };
}

const patchSchema = z.strictObject({
  baseVersion: z.number().int().positive(),
  title: z
    .string()
    .max(LIMITS.titleChars)
    .refine((s) => s.trim() !== "", "title must not be blank")
    .optional(),
  summary: z.string().max(LIMITS.summaryChars).optional(),
});

function toFieldEdits({ title, summary }: { title?: string; summary?: string }): FieldEdits | null {
  if (title !== undefined) return summary === undefined ? { title } : { title, summary };
  if (summary !== undefined) return { summary };
  return null;
}

async function parsePatchBody(req: Request): Promise<Parsed<{ baseVersion: Version; edits: FieldEdits }>> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return { ok: false, result: fail({ status: 400, code: "invalid_json", message: "body is not valid JSON" }) };
  }
  if (typeof body === "object" && body !== null && "transcript" in body) {
    return { ok: false, result: fail({ status: 400, code: "transcript_immutable", message: "the transcript can never be modified" }) };
  }
  const parsed = patchSchema.safeParse(body);
  if (!parsed.success) {
    const unknownKey = parsed.error.issues.some((issue) => issue.code === "unrecognized_keys");
    return {
      ok: false,
      result: fail({
        status: 400,
        code: unknownKey ? "unknown_field" : "invalid_body",
        message: parsed.error.issues.map((issue) => `${issue.path.join(".") || "body"}: ${issue.message}`).join("; "),
      }),
    };
  }
  const edits = toFieldEdits(parsed.data);
  if (!edits) return { ok: false, result: fail({ status: 400, code: "empty_patch", message: "send title and/or summary" }) };
  return { ok: true, value: { baseVersion: parsed.data.baseVersion as Version, edits } };
}

function parseLimit(raw: string | null): Parsed<PageLimit> {
  if (raw === null) return { ok: true, value: LIMITS.defaultPage as PageLimit };
  const parsed = z.coerce.number().int().min(1).max(LIMITS.maxPage).safeParse(raw);
  if (parsed.success) return { ok: true, value: parsed.data as PageLimit };
  return { ok: false, result: fail({ status: 400, code: "invalid_limit", message: `limit must be 1..${LIMITS.maxPage}` }) };
}

// ---------- event summaries ----------

const quote = (s: string) => JSON.stringify(s.length > 40 ? `${s.slice(0, 40)}…` : s);

function describeEdit({ before, edits }: { before: LiveRecording; edits: FieldEdits }): string {
  return EDITABLE_FIELDS.flatMap((field) => {
    const wanted = edits[field];
    return wanted === undefined ? [] : [`${field} ${quote(before[field])} → ${quote(wanted)}`];
  }).join(", ");
}

function conflictJSON({ fields, yours }: { fields: readonly FieldConflict[]; yours: FieldEdits | null }) {
  return fields.map((c) => ({ field: c.field, yours: yours?.[c.field] ?? null, theirs: c.theirs, changedBy: c.changedBy, changedAt: c.changedAt }));
}

// ---------- outcome → HTTP ----------

function writeResponse({ outcome, action, id, edits, before }: {
  outcome: WriteOutcome;
  action: "edit" | "delete";
  id: RecordingId;
  edits: FieldEdits | null;
  before: RecordingHead | null;
}): HandlerResult {
  const editText = edits && before?.kind === "live" ? describeEdit({ before, edits }) : "";
  switch (outcome.kind) {
    case "applied": {
      const body = appliedJSON(outcome.result);
      const headers: Record<string, string> = outcome.replayed ? { "Idempotent-Replayed": "true" } : {};
      const version = outcome.result.recording.version;
      const changed = outcome.result.kind === "edited" ? outcome.result.changed : [];
      const kind = outcome.replayed
        ? (`${action}.replayed` as const)
        : action === "edit" && changed.length === 0
          ? "edit.noop"
          : action === "delete" && before?.kind === "deleted"
            ? "delete.noop"
            : (`${action}.applied` as const);
      const summary = outcome.replayed
        ? `retry recognised, original reply returned (v${version}); nothing applied twice`
        : action === "edit"
          ? changed.length === 0
            ? `already equal, nothing to write (v${version})`
            : `${editText} (v${before?.version} → v${version})`
          : before?.kind === "deleted"
            ? `already deleted (v${version})`
            : `deleted (v${before?.version} → v${version})`;
      return { response: json(200, body, headers), event: { kind, recordingId: id, summary, detail: { request: edits, result: body } } };
    }
    case "conflict": {
      const conflicts = conflictJSON({ fields: outcome.fields, yours: edits });
      const who = [...new Set(outcome.fields.map((c) => c.changedBy ?? "seed"))].join(", ");
      return {
        response: json(409, {
          error: { code: "version_conflict", message: `changed by another device since your base version` },
          action,
          yours: edits,
          conflicts,
          current: liveJSON(outcome.current),
        }),
        event: {
          kind: `${action}.conflict`,
          recordingId: id,
          summary:
            action === "edit"
              ? `rejected: ${conflicts.map((c) => `${c.field} wanted ${quote(c.yours ?? "")}, server has ${quote(c.theirs)}`).join("; ")} (changed by ${who}, now v${outcome.current.version})`
              : `delete rejected: ${outcome.fields.map((c) => c.field).join(", ")} changed by ${who} (now v${outcome.current.version})`,
          detail: { request: edits, conflicts, current: liveJSON(outcome.current) },
        },
      };
    }
    case "gone":
      return fail({
        status: 410,
        code: "recording_deleted",
        message: "this recording was deleted on another device",
        extra: { current: deletedJSON(outcome.current) },
        event: {
          kind: "edit.gone",
          recordingId: id,
          summary: `edit dropped: recording deleted by ${outcome.current.updatedBy ?? "seed"} (v${outcome.current.version})`,
          detail: { request: edits, current: deletedJSON(outcome.current) },
        },
      });
    case "not_found":
      return fail({ status: 404, code: "not_found", message: `no recording ${id}`, event: { kind: "not_found", recordingId: id } });
    case "key_reused":
      return fail({
        status: 422,
        code: "idempotency_key_reused",
        message: "this Idempotency-Key was already used for a different request",
        event: { recordingId: id },
      });
    case "base_ahead":
      return fail({
        status: 422,
        code: "base_version_ahead",
        message: "baseVersion is newer than the server copy; re-fetch this recording",
        extra: { current: headJSON(outcome.current) },
        event: { recordingId: id },
      });
    default: {
      const _exhaustive: never = outcome;
      return _exhaustive;
    }
  }
}

// ---------- handlers ----------

function listRecordings(store: RecordingStore, { req }: Ctx): HandlerResult {
  const url = new URL(req.url);
  const limit = parseLimit(url.searchParams.get("limit"));
  if (!limit.ok) return limit.result;
  const rawCursor = url.searchParams.get("cursor");
  const cursor = rawCursor === null ? null : decodeCursor(rawCursor);
  if (rawCursor !== null && cursor === null) return fail({ status: 400, code: "invalid_cursor", message: "cursor is not one this server issued" });

  const result = store.list({ cursor, limit: limit.value });
  if (result.kind === "cursor_reset") {
    return fail({
      status: 410,
      code: "cursor_reset",
      message: "the server database was reset; drop the cursor and sync from scratch",
      event: { kind: "list.cursor_reset", summary: "stale cursor from another database: client must resync" },
    });
  }
  const { items, next, hasMore } = result.page;
  const deleted = items.filter((i) => i.kind === "deleted").length;
  return {
    response: json(200, { items: items.map(headJSON), nextCursor: encodeCursor(next), hasMore }),
    event: {
      kind: "list",
      recordingId: null,
      summary: `${cursor ? `delta after v${cursor.after}` : "first sync"}: ${items.length} item(s)${deleted ? `, ${deleted} deleted` : ""}${hasMore ? ", more pages" : ""}`,
      detail: { cursor: rawCursor, limit: limit.value, ids: items.map((i) => `${i.id}@v${i.version}`), nextCursor: encodeCursor(next), hasMore },
    },
  };
}

function browseRecordings(store: RecordingStore, { req }: Ctx): HandlerResult {
  const url = new URL(req.url);
  const limit = parseLimit(url.searchParams.get("limit"));
  if (!limit.ok) return limit.result;
  const rawCursor = url.searchParams.get("after");
  const cursor = rawCursor === null ? null : decodeBrowseCursor(rawCursor);
  if (rawCursor !== null && cursor === null) return fail({ status: 400, code: "invalid_cursor", message: "after is not a browse cursor this server issued" });

  const result = store.browse({ cursor, limit: limit.value });
  if (result.kind === "cursor_reset") {
    return fail({
      status: 410,
      code: "cursor_reset",
      message: "the server database was reset; browse again from the first page",
      event: { kind: "browse.cursor_reset", summary: "stale browse cursor from another database: client must resync" },
    });
  }
  const { items, next, hasMore, sync } = result.page;
  const nextCursor = next ? encodeBrowseCursor(next) : null;
  return {
    response: json(200, { items: items.map(liveJSON), nextCursor, hasMore, syncCursor: encodeCursor(sync) }),
    event: {
      kind: "browse",
      recordingId: null,
      summary: `${cursor ? "next page" : "first page"}: ${items.length} item(s)${hasMore ? ", more pages" : ", end of list"}`,
      detail: { after: rawCursor, limit: limit.value, ids: items.map((i) => `${i.id}@v${i.version}`), nextCursor, hasMore, syncCursor: encodeCursor(sync) },
    },
  };
}

function getRecording(store: RecordingStore, { req }: Ctx): HandlerResult {
  const id = parseRecordingId(req.params.id);
  if (!id.ok) return id.result;
  const result = store.get(id.value);
  switch (result.kind) {
    case "live": {
      const { head, transcript } = result.detail;
      return {
        response: json(200, { ...liveJSON(head), transcript }),
        event: {
          kind: "detail",
          recordingId: id.value,
          summary: `opened ${quote(head.title)} with ${transcript.length} transcript segments (v${head.version})`,
          detail: { version: head.version, segmentCount: transcript.length },
        },
      };
    }
    case "deleted":
      return fail({
        status: 410,
        code: "recording_deleted",
        message: "this recording was deleted",
        extra: { current: deletedJSON(result.head) },
        event: { kind: "detail.gone", recordingId: id.value, summary: `deleted by ${result.head.updatedBy ?? "seed"} (v${result.head.version})` },
      });
    case "not_found":
      return fail({ status: 404, code: "not_found", message: `no recording ${id.value}`, event: { kind: "not_found", recordingId: id.value } });
    default: {
      const _exhaustive: never = result;
      return _exhaustive;
    }
  }
}

async function patchRecording(store: RecordingStore, { req, meta }: Ctx): Promise<HandlerResult> {
  const id = parseRecordingId(req.params.id);
  if (!id.ok) return id.result;
  if (!meta.key) return fail({ status: 400, code: "missing_idempotency_key", message: "PATCH needs an Idempotency-Key header (the mutation id)" });
  if (!meta.device) return fail({ status: 400, code: "missing_device_id", message: "X-Device-Id header is required" });
  const body = await parsePatchBody(req);
  if (!body.ok) return { ...body.result, event: { ...body.result.event, recordingId: id.value } };

  // No await between here and the write: the read and the write see the same row.
  const before = store.head(id.value);
  const outcome = store.edit({ id: id.value, baseVersion: body.value.baseVersion, edits: body.value.edits, key: meta.key, device: meta.device });
  return writeResponse({ outcome, action: "edit", id: id.value, edits: body.value.edits, before });
}

function deleteRecording(store: RecordingStore, { req, meta }: Ctx): HandlerResult {
  const id = parseRecordingId(req.params.id);
  if (!id.ok) return id.result;
  if (!meta.key) return fail({ status: 400, code: "missing_idempotency_key", message: "DELETE needs an Idempotency-Key header (the mutation id)" });
  if (!meta.device) return fail({ status: 400, code: "missing_device_id", message: "X-Device-Id header is required" });
  const baseVersion = parseBaseVersion(new URL(req.url).searchParams.get("baseVersion"));
  if (!baseVersion.ok) return baseVersion.result;

  const before = store.head(id.value);
  const outcome = store.delete({ id: id.value, baseVersion: baseVersion.value, key: meta.key, device: meta.device });
  return writeResponse({ outcome, action: "delete", id: id.value, edits: null, before });
}

// ---------- server ----------

export function startServer({ port, hostname, store, events, faults }: {
  port: number;
  hostname: string;
  store: RecordingStore;
  events: EventLog;
  faults: Faults;
}): Server<undefined> {
  /**
   * Wraps every /recordings handler: identifies the device, applies latency, logs one event, and
   * for PATCH/DELETE may cut the socket after the write committed (the lost-ack fault).
   */
  const api =
    (handler: (ctx: Ctx) => HandlerResult | Promise<HandlerResult>, opts: { mutating: boolean }) =>
    async (req: RouteRequest, server: Server<undefined>): Promise<Response> => {
      const startedAt = performance.now();
      const meta: RequestMeta = {
        requestId: crypto.randomUUID().slice(0, 8),
        device: parseDevice(req),
        method: req.method,
        path: new URL(req.url).pathname + new URL(req.url).search,
        key: parseKey(req),
      };
      faults.noteRequest(meta.device);
      const simulation = opts.mutating ? parseSimulation(req) : null;
      const [minFirstByte, maxFirstByte] = SLOW_LINK.firstByteMs;
      const firstByte = simulation === "slow" ? minFirstByte + Math.random() * (maxFirstByte - minFirstByte) : 0;
      const latency = faults.latencyFor(meta.device) + firstByte;
      if (latency > 0) await Bun.sleep(latency);

      const { response, event } = meta.device
        ? await handler({ req, meta })
        : fail({ status: 400, code: "missing_device_id", message: "X-Device-Id header is required" });
      response.headers.set("X-Request-Id", meta.requestId);
      events.write({ meta, draft: event, status: response.status, startedAt });

      if (opts.mutating && (simulation === "drop" || faults.takeDrop(meta.device))) {
        events.write({
          meta,
          draft: {
            kind: "fault.response_dropped",
            recordingId: event.recordingId,
            summary: `reply (${response.status}) dropped after commit: the device will see a network error`,
            detail: { droppedStatus: response.status },
          },
          status: 0,
          startedAt,
        });
        server.timeout(req, 1);
        return new Promise<Response>(() => {});
      }
      return simulation === "slow" ? throttle(response) : response;
    };

  const control = (req: Request, draft: Omit<EventDraft, "recordingId">) =>
    events.write({
      meta: { requestId: crypto.randomUUID().slice(0, 8), device: null, method: req.method, path: new URL(req.url).pathname, key: null },
      draft: { ...draft, recordingId: null },
      status: 200,
      startedAt: performance.now(),
    });

  return Bun.serve({
    port,
    hostname,
    development: false,
    routes: {
      "/health": () => json(200, { ok: true, epoch: store.epoch, recordings: store.count() }),
      "/recordings": { GET: api((ctx) => listRecordings(store, ctx), { mutating: false }) },
      "/recordings/browse": { GET: api((ctx) => browseRecordings(store, ctx), { mutating: false }) },
      "/recordings/:id": {
        GET: api((ctx) => getRecording(store, ctx), { mutating: false }),
        PATCH: api((ctx) => patchRecording(store, ctx), { mutating: true }),
        DELETE: api((ctx) => deleteRecording(store, ctx), { mutating: true }),
      },

      "/logs": viewer,
      "/logs/events": {
        GET: (req) => {
          const after = z.coerce.number().int().min(0).catch(0).parse(new URL(req.url).searchParams.get("after") ?? 0);
          return json(200, { events: events.after({ id: after, limit: 1000 }) });
        },
        DELETE: () => {
          events.clear();
          return new Response(null, { status: 204 });
        },
      },

      "/_sim/devices": {
        GET: () => json(200, faults.all()),
        DELETE: (req) => {
          faults.clearAll();
          control(req, { kind: "fault.configured", summary: "all faults cleared", detail: {} });
          return new Response(null, { status: 204 });
        },
      },
      "/_sim/devices/:device": {
        PUT: async (req) => {
          const raw = DEVICE_PATTERN.test(req.params.device) ? (req.params.device as DeviceId) : null;
          const device = raw && faults.resolve(raw);
          if (!device) return json(400, { error: { code: "missing_device_id", message: "bad device id, or no device has sent a request yet" } });
          const rule = faultRuleSchema.safeParse(await req.json().catch(() => null));
          if (!rule.success) return json(400, { error: { code: "invalid_body", message: rule.error.message } });
          faults.set({ device, rule: rule.data });
          control(req, { kind: "fault.configured", summary: `${device}: dropResponses=${rule.data.dropResponses}, latencyMs=${rule.data.latencyMs}`, detail: { device, rule: rule.data } });
          return json(200, rule.data);
        },
        DELETE: (req) => {
          const raw = DEVICE_PATTERN.test(req.params.device) ? (req.params.device as DeviceId) : null;
          const device = raw && faults.resolve(raw);
          if (!device) return json(400, { error: { code: "missing_device_id", message: "bad device id, or no device has sent a request yet" } });
          faults.clear(device);
          control(req, { kind: "fault.configured", summary: `${device}: faults cleared`, detail: { device } });
          return new Response(null, { status: 204 });
        },
      },
    },
    fetch: () => json(404, { error: { code: "not_found", message: "no such route" } }),
  });
}
