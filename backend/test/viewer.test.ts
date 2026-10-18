import { expect, test } from "bun:test";
import {
  category,
  detailParts,
  eventPageSchema,
  filterEvents,
  groupEvents,
  isRetry,
  type LogEvent,
} from "../src/viewer/model";

const event = (id: number, extra: Partial<LogEvent> = {}): LogEvent => ({
  id,
  at: id * 1000,
  requestId: `req-${id}`,
  device: "sim-a",
  method: "PATCH",
  path: "/recordings/rec_1",
  status: 200,
  durationMs: 5,
  kind: "edit.applied",
  recordingId: "rec_1",
  key: "mutation-key",
  summary: "Title changed",
  detail: {},
  ...extra,
});

test("chains preserve request order, keep device sync separate, and surface latest activity", () => {
  const groups = groupEvents([
    event(3),
    event(1),
    event(2, { recordingId: null, device: "sim-b" }),
    event(4, { recordingId: null, device: "sim-a" }),
  ]);
  expect(groups.map((g) => g.key)).toEqual([
    "sync:sim-a",
    "recording:rec_1",
    "sync:sim-b",
  ]);
  expect(groups[1]?.steps.map((e) => e.id)).toEqual([1, 3]);
});

test("search includes nested payloads and combines with source and outcome filters", () => {
  const records = [
    event(1, {
      detail: { conflicts: [{ theirs: "Museum" }] },
      kind: "edit.conflict",
    }),
    event(2),
    event(3, { device: "sim-b", kind: "edit.conflict" }),
  ];
  expect(
    filterEvents(records, new Set(["sim-b"]), "conflict", "museum").map(
      (e) => e.id,
    ),
  ).toEqual([1]);
  expect(
    filterEvents(records, new Set(["sim-a"]), "all", "").map((e) => e.id),
  ).toEqual([3]);
});

test("a dropped acknowledgement is not a retry, and replay is linked to the same key", () => {
  const applied = event(1);
  const drop = event(2, { kind: "fault.response_dropped", status: 0 });
  expect(isRetry(applied, drop)).toBe(false);
  expect(isRetry(drop, event(3, { kind: "edit.replayed" }))).toBe(true);
  expect(isRetry(applied, event(4, { key: "different-key" }))).toBe(false);
  expect(category("browse.cursor_reset")).toBe("conflict");
});

test("overview preserves null logged fields and all conflict evidence", () => {
  const detail = {
    request: null,
    conflicts: [{ field: "title", yours: "A", theirs: "B" }],
    current: { version: 12 },
  };
  expect(detailParts(event(1, { detail }))).toEqual({
    request: null,
    result: { conflicts: detail.conflicts, current: detail.current },
  });
  expect(detailParts(event(2, { detail: ["opaque result"] }))).toEqual({
    result: ["opaque result"],
  });
});

test("wire parsing rejects malformed pages and preserves extra raw event fields", () => {
  const record = { ...event(1), futureField: { preserved: true } };
  expect(eventPageSchema.parse({ events: [record] }).events[0]).toEqual(record);
  expect(eventPageSchema.safeParse({ events: [{ id: "bad" }] }).success).toBe(
    false,
  );
});
