import { describe, expect, test } from "bun:test";
import type { DeviceId, Version } from "../src/domain";
import { decideDelete, decideEdit, type RowState } from "../src/rules";

const A = "sim-a" as DeviceId;
const B = "sim-b" as DeviceId;
const v = (n: number) => n as Version;

function row({ title = "T", titleV = 10, titleBy = null, summary = "S", summaryV = 10, summaryBy = null }: {
  title?: string;
  titleV?: number;
  titleBy?: DeviceId | null;
  summary?: string;
  summaryV?: number;
  summaryBy?: DeviceId | null;
} = {}): RowState {
  return {
    version: v(Math.max(titleV, summaryV)),
    fields: {
      title: { value: title, version: v(titleV), by: titleBy, at: 1 },
      summary: { value: summary, version: v(summaryV), by: summaryBy, at: 1 },
    },
  };
}

describe("decideEdit", () => {
  test("unchanged since base: write", () => {
    expect(decideEdit({ row: row(), baseVersion: v(10), device: A, edits: { title: "New" } })).toEqual({ kind: "write", set: { title: "New" } });
  });

  test("same field changed by another device since base: conflict", () => {
    const d = decideEdit({ row: row({ title: "Theirs", titleV: 12, titleBy: B }), baseVersion: v(10), device: A, edits: { title: "Mine" } });
    expect(d).toEqual({ kind: "conflict", fields: [{ field: "title", theirs: "Theirs", changedBy: B, changedAt: 1 }] });
  });

  test("different field changed by another device: write", () => {
    const d = decideEdit({ row: row({ summaryV: 12, summaryBy: B }), baseVersion: v(10), device: A, edits: { title: "Mine" } });
    expect(d).toEqual({ kind: "write", set: { title: "Mine" } });
  });

  test("own earlier write to the same field: write, not conflict", () => {
    const d = decideEdit({ row: row({ title: "Mine 1", titleV: 12, titleBy: A }), baseVersion: v(10), device: A, edits: { title: "Mine 2" } });
    expect(d).toEqual({ kind: "write", set: { title: "Mine 2" } });
  });

  test("both devices typed the same value: noop", () => {
    const d = decideEdit({ row: row({ title: "Same", titleV: 12, titleBy: B }), baseVersion: v(10), device: A, edits: { title: "Same" } });
    expect(d).toEqual({ kind: "noop" });
  });

  test("one conflicting field rejects the whole edit", () => {
    const d = decideEdit({ row: row({ titleV: 12, titleBy: B }), baseVersion: v(10), device: A, edits: { title: "Mine", summary: "Also mine" } });
    expect(d.kind).toBe("conflict");
  });

  test("only fields that actually change are written", () => {
    const d = decideEdit({ row: row(), baseVersion: v(10), device: A, edits: { title: "T", summary: "New" } });
    expect(d).toEqual({ kind: "write", set: { summary: "New" } });
  });

  test("base newer than the server copy: base_ahead", () => {
    expect(decideEdit({ row: row(), baseVersion: v(99), device: A, edits: { title: "x" } })).toEqual({ kind: "base_ahead" });
  });
});

describe("decideDelete", () => {
  test("nothing changed since base: delete", () => {
    expect(decideDelete({ row: row(), baseVersion: v(10), device: A })).toEqual({ kind: "delete" });
  });

  test("another device edited after base: conflict", () => {
    const d = decideDelete({ row: row({ summary: "Theirs", summaryV: 12, summaryBy: B }), baseVersion: v(10), device: A });
    expect(d).toEqual({ kind: "conflict", fields: [{ field: "summary", theirs: "Theirs", changedBy: B, changedAt: 1 }] });
  });

  test("own edit after base: delete", () => {
    expect(decideDelete({ row: row({ titleV: 12, titleBy: A }), baseVersion: v(10), device: A })).toEqual({ kind: "delete" });
  });
});
