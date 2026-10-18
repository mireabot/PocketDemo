import { Database } from "bun:sqlite";
import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { z } from "zod";
import type { RecordingId } from "../src/domain";
import { EventLog } from "../src/events";
import { Faults } from "../src/faults";
import { startServer } from "../src/server";
import { RecordingStore } from "../src/store";

const dir = mkdtempSync(join(tmpdir(), "pocket-test-"));
let n = 0;

interface Harness {
  base: string;
  store: RecordingStore;
  dbPath: string;
  stop: () => void;
}

function boot(): Harness {
  n += 1;
  const dbPath = join(dir, `t${n}.db`);
  const store = RecordingStore.open({ path: dbPath });
  for (let i = 1; i <= 5; i++) {
    store.importRecording({
      id: `rec_${i}` as RecordingId,
      title: `Title ${i}`,
      summary: `Summary ${i}`,
      createdAt: i,
      transcript: [{ startMs: 0, text: `hello ${i}` }],
    });
  }
  const events = EventLog.open({ path: join(dir, `t${n}-events.db`), echo: false });
  const server = startServer({ port: 0, hostname: "127.0.0.1", store, events, faults: new Faults() });
  return { base: server.url.href.replace(/\/$/, ""), store, dbPath, stop: () => server.stop(true) };
}

let h: Harness;
beforeEach(() => {
  h?.stop();
  h = boot();
});
afterAll(() => {
  h?.stop();
  rmSync(dir, { recursive: true, force: true });
});

const key = () => crypto.randomUUID();

const listBody = z.object({ items: z.array(z.looseObject({ id: z.string() })), nextCursor: z.string(), hasMore: z.boolean() });
const errorBody = z.looseObject({ error: z.object({ code: z.string() }) });
const appliedBody = z.looseObject({ recording: z.looseObject({}) });
const browseBody = z.object({
  items: z.array(z.looseObject({ id: z.string() })),
  nextCursor: z.string().nullable(),
  hasMore: z.boolean(),
  syncCursor: z.string(),
});
const list = async (res: Response) => listBody.parse(await res.json());
const browse = async (res: Response) => browseBody.parse(await res.json());
const errorCode = async (res: Response) => errorBody.parse(await res.json()).error.code;
const recording = async (res: Response) => appliedBody.parse(await res.json()).recording;


function req(device: string, method: string, path: string, opts: { body?: unknown; key?: string; fault?: string } = {}) {
  const headers: Record<string, string> = { "X-Device-Id": device };
  if (opts.key) headers["Idempotency-Key"] = opts.key;
  if (opts.fault) headers["X-Sim-Fault"] = opts.fault;
  if (opts.body !== undefined) headers["Content-Type"] = "application/json";
  return fetch(`${h.base}${path}`, { method, headers, body: opts.body === undefined ? undefined : JSON.stringify(opts.body) });
}

const patch = (device: string, id: string, body: unknown, k = key()) => req(device, "PATCH", `/recordings/${id}`, { body, key: k });
const del = (device: string, id: string, baseVersion: number, k = key()) =>
  req(device, "DELETE", `/recordings/${id}?baseVersion=${baseVersion}`, { key: k });

describe("fetch", () => {
  test("list pages by cursor, never includes transcripts, and a delta returns only changes", async () => {
    const first = await list(await req("sim-a", "GET", "/recordings?limit=3"));
    expect(first.items).toHaveLength(3);
    expect(first.hasMore).toBe(true);
    expect(first.items.every((r) => !("transcript" in r))).toBe(true);

    const second = await list(await req("sim-a", "GET", `/recordings?limit=3&cursor=${first.nextCursor}`));
    expect(second.items.map((r) => r.id)).toEqual(["rec_4", "rec_5"]);
    expect(second.hasMore).toBe(false);

    await patch("sim-b", "rec_2", { baseVersion: 2, title: "Changed on B" });
    const delta = await list(await req("sim-a", "GET", `/recordings?cursor=${second.nextCursor}`));
    expect(delta.items).toHaveLength(1);
    expect(delta.items[0]).toMatchObject({ id: "rec_2", title: "Changed on B", version: 6, updatedBy: "sim-b" });
  });

  test("browse pages newest first and hands back the feed cursor for later changes", async () => {
    const first = await browse(await req("sim-a", "GET", "/recordings/browse?limit=2"));
    expect(first.items.map((r) => r.id)).toEqual(["rec_5", "rec_4"]);
    expect(first.hasMore).toBe(true);

    await patch("sim-b", "rec_1", { baseVersion: 1, title: "Changed while browsing" });
    await del("sim-b", "rec_3", 3);
    const second = await browse(await req("sim-a", "GET", `/recordings/browse?limit=2&after=${first.nextCursor}`));
    expect(second.items.map((r) => r.id)).toEqual(["rec_2", "rec_1"]);
    expect(second.items[1]).toMatchObject({ title: "Changed while browsing" });
    expect(second.hasMore).toBe(false);

    const delta = await list(await req("sim-a", "GET", `/recordings?cursor=${first.syncCursor}`));
    expect(delta.items.map((r) => r.id)).toEqual(["rec_1", "rec_3"]);
    expect(delta.items[1]).toMatchObject({ deleted: true });
  });

  test("a browse cursor from another database is rejected with cursor_reset", async () => {
    const res = await req("sim-a", "GET", "/recordings/browse?after=00000000-0000-0000-0000-000000000000:c3:rec_3");
    expect(res.status).toBe(410);
    expect(await errorCode(res)).toBe("cursor_reset");
  });

  test("detail includes the transcript", async () => {
    const res = await req("sim-a", "GET", "/recordings/rec_1");
    expect(await res.json()).toMatchObject({ id: "rec_1", transcript: [{ startMs: 0, text: "hello 1" }] });
  });

  test("a cursor from another database is rejected with cursor_reset", async () => {
    const res = await req("sim-a", "GET", "/recordings?cursor=00000000-0000-0000-0000-000000000000:v3");
    expect(res.status).toBe(410);
    expect(await errorCode(res)).toBe("cursor_reset");
  });
});

describe("edit", () => {
  test("applies and bumps the version", async () => {
    const res = await patch("sim-a", "rec_1", { baseVersion: 1, title: "New" });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ recording: { title: "New", version: 6 }, changed: ["title"] });
  });

  test("same field edited on two devices: the second gets 409 with both sides", async () => {
    await patch("sim-b", "rec_1", { baseVersion: 1, title: "Theirs" });
    const res = await patch("sim-a", "rec_1", { baseVersion: 1, title: "Mine" });
    expect(res.status).toBe(409);
    expect(await res.json()).toMatchObject({
      action: "edit",
      yours: { title: "Mine" },
      conflicts: [{ field: "title", yours: "Mine", theirs: "Theirs", changedBy: "sim-b" }],
      current: { title: "Theirs", version: 6 },
    });
  });

  test("different fields on two devices both apply", async () => {
    expect((await patch("sim-b", "rec_1", { baseVersion: 1, summary: "B summary" })).status).toBe(200);
    const res = await patch("sim-a", "rec_1", { baseVersion: 1, title: "A title" });
    expect(res.status).toBe(200);
    expect(await recording(res)).toMatchObject({ title: "A title", summary: "B summary" });
  });

  test("a device's own queued edits don't conflict with each other", async () => {
    expect((await patch("sim-a", "rec_1", { baseVersion: 1, title: "First" })).status).toBe(200);
    expect((await patch("sim-a", "rec_1", { baseVersion: 1, title: "Second" })).status).toBe(200);
  });

  test("the transcript can't be edited and unknown fields are rejected", async () => {
    const t = await patch("sim-a", "rec_1", { baseVersion: 1, transcript: [] });
    expect(await errorCode(t)).toBe("transcript_immutable");
    const u = await patch("sim-a", "rec_1", { baseVersion: 1, titel: "typo" });
    expect(await errorCode(u)).toBe("unknown_field");
  });

  test("the database itself refuses to change a transcript", () => {
    const raw = new Database(h.dbPath);
    expect(() => raw.run("UPDATE transcripts SET segments = '[]' WHERE recording_id = 'rec_1'")).toThrow("transcript is immutable");
    raw.close();
  });

  test("headers are required", async () => {
    const noKey = await req("sim-a", "PATCH", "/recordings/rec_1", { body: { baseVersion: 1, title: "x" } });
    expect(await errorCode(noKey)).toBe("missing_idempotency_key");
    const noDevice = await fetch(`${h.base}/recordings`);
    expect(await errorCode(noDevice)).toBe("missing_device_id");
  });
});

describe("lost ack and retries", () => {
  test("server commits, reply is dropped, retry returns the original reply without applying twice", async () => {
    const k = key();
    await fetch(`${h.base}/_sim/devices/sim-a`, { method: "PUT", body: JSON.stringify({ dropResponses: 1 }) });

    expect(patch("sim-a", "rec_1", { baseVersion: 1, title: "Mine" }, k)).rejects.toThrow();
    await Bun.sleep(5000);

    // Another device edits the same field before the retry arrives.
    expect((await patch("sim-b", "rec_1", { baseVersion: 6, title: "Theirs later" })).status).toBe(200);

    const retry = await patch("sim-a", "rec_1", { baseVersion: 1, title: "Mine" }, k);
    expect(retry.status).toBe(200);
    expect(retry.headers.get("Idempotent-Replayed")).toBe("true");
    expect(await recording(retry)).toMatchObject({ title: "Mine", version: 6 });

    const now: unknown = await (await req("sim-a", "GET", "/recordings/rec_1")).json();
    expect(now).toMatchObject({ title: "Theirs later", version: 7 });
  }, 15_000);

  test("a write's own fault header slows it or drops its reply once", async () => {
    const started = performance.now();
    const slow = await req("sim-a", "PATCH", "/recordings/rec_2", { body: { baseVersion: 2, title: "Slow" }, key: key(), fault: "slow" });
    expect(slow.status).toBe(200);
    expect(slow.headers.get("content-length")).toBeNull();
    expect(await recording(slow)).toMatchObject({ title: "Slow" });
    expect(performance.now() - started).toBeGreaterThanOrEqual(2000);

    const k = key();
    const cutAt = performance.now();
    const dropped = req("sim-a", "PATCH", "/recordings/rec_2", { body: { baseVersion: 2, summary: "Lost" }, key: k, fault: "drop" });
    expect(dropped).rejects.toThrow();
    await dropped.catch(() => {});
    expect(performance.now() - cutAt).toBeGreaterThanOrEqual(900);

    const retry = await patch("sim-a", "rec_2", { baseVersion: 2, summary: "Lost" }, k);
    expect(retry.status).toBe(200);
    expect(retry.headers.get("Idempotent-Replayed")).toBe("true");
  }, 15_000);

  test("faults can target the device that sent the latest request", async () => {
    await req("sim-a", "GET", "/recordings/rec_1");
    await fetch(`${h.base}/_sim/devices/latest`, { method: "PUT", body: JSON.stringify({ dropResponses: 1 }) });
    const all = (await (await fetch(`${h.base}/_sim/devices`)).json()) as Record<string, unknown>;
    expect(Object.keys(all)).toEqual(["sim-a"]);
    await fetch(`${h.base}/_sim/devices`, { method: "DELETE" });
    expect(await (await fetch(`${h.base}/_sim/devices`)).json()).toEqual({});
  });

  test("reusing a key for a different request is refused", async () => {
    const k = key();
    await patch("sim-a", "rec_1", { baseVersion: 1, title: "One" }, k);
    const res = await patch("sim-a", "rec_1", { baseVersion: 1, title: "Two" }, k);
    expect(res.status).toBe(422);
    expect(await errorCode(res)).toBe("idempotency_key_reused");
  });
});

describe("delete", () => {
  test("edit after another device deleted: 410, feed and detail show the tombstone", async () => {
    expect((await del("sim-b", "rec_3", 3)).status).toBe(200);

    const edit = await patch("sim-a", "rec_3", { baseVersion: 3, title: "Too late" });
    expect(edit.status).toBe(410);
    expect(await errorCode(edit)).toBe("recording_deleted");

    expect((await req("sim-a", "GET", "/recordings/rec_3")).status).toBe(410);

    const first = await list(await req("sim-a", "GET", "/recordings?limit=100"));
    expect(first.items.find((r) => r.id === "rec_3")).toBeUndefined();
    const delta = await list(await req("sim-a", "GET", `/recordings?cursor=${first.nextCursor.replace(/v\d+$/, "v5")}`));
    expect(delta.items).toEqual([expect.objectContaining({ id: "rec_3", deleted: true, version: 6 })]);
  });

  test("delete after another device edited is a conflict", async () => {
    await patch("sim-b", "rec_1", { baseVersion: 1, title: "B edit" });
    const res = await del("sim-a", "rec_1", 1);
    expect(res.status).toBe(409);
    expect(await res.json()).toMatchObject({ action: "delete", yours: null, conflicts: [{ field: "title", theirs: "B edit" }] });
  });

  test("deleting twice is harmless", async () => {
    await del("sim-a", "rec_1", 1);
    const again = await del("sim-b", "rec_1", 1);
    expect(again.status).toBe(200);
    expect(await recording(again)).toMatchObject({ deleted: true, version: 6 });
  });
});
