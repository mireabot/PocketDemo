import { z } from "zod";

// Validate the wire format at the browser boundary; accept new event kinds without a UI release.
export const eventSchema = z.looseObject({
  id: z.number().int().positive(),
  at: z.number(),
  requestId: z.string(),
  device: z.string().nullable(),
  method: z.string(),
  path: z.string(),
  status: z.number(),
  durationMs: z.number(),
  kind: z.string(),
  recordingId: z.string().nullable(),
  key: z.string().nullable(),
  summary: z.string(),
  detail: z.unknown(),
});
export const eventPageSchema = z.object({ events: z.array(eventSchema) });
export type LogEvent = z.infer<typeof eventSchema>;
export type Category =
  | "fetch"
  | "applied"
  | "conflict"
  | "gone"
  | "replay"
  | "fault"
  | "noop";
export const labels: Record<Category, string> = {
  fetch: "Fetch",
  applied: "Applied",
  conflict: "Conflict",
  gone: "Rejected / gone",
  replay: "Replayed",
  fault: "Fault",
  noop: "No change",
};
export function category(kind: string): Category {
  if (["list", "browse", "detail"].includes(kind)) return "fetch";
  if (kind.endsWith(".applied")) return "applied";
  if (kind.endsWith(".conflict") || kind.endsWith(".cursor_reset"))
    return "conflict";
  if (kind.endsWith(".gone") || ["rejected", "not_found"].includes(kind))
    return "gone";
  if (kind.endsWith(".replayed")) return "replay";
  if (kind.startsWith("fault.")) return "fault";
  return "noop";
}
export function filterEvents(
  events: LogEvent[],
  hidden: Set<string>,
  outcome: string,
  query: string,
) {
  const search = query.trim().toLowerCase();
  return events.filter(
    (e) =>
      !hidden.has(e.device ?? "server") &&
      (outcome === "all" || category(e.kind) === outcome) &&
      (!search || JSON.stringify(e).toLowerCase().includes(search)),
  );
}
export function groupEvents(events: LogEvent[]) {
  const groups = new Map<string, LogEvent[]>();
  for (const event of events) {
    const key = event.recordingId
      ? `recording:${event.recordingId}`
      : `sync:${event.device ?? "server"}`;
    const group = groups.get(key);
    if (group) group.push(event);
    else groups.set(key, [event]);
  }
  return [...groups.entries()]
    .map(([key, steps]) => ({
      key,
      steps: steps.toSorted((a, b) => a.id - b.id),
    }))
    .sort((a, b) => (b.steps.at(-1)?.id ?? 0) - (a.steps.at(-1)?.id ?? 0));
}
export function isRetry(previous: LogEvent | undefined, next: LogEvent) {
  return Boolean(
    previous?.key &&
      previous.key === next.key &&
      next.kind !== "fault.response_dropped",
  );
}
export function detailParts(event: LogEvent) {
  if (
    typeof event.detail === "object" &&
    event.detail !== null &&
    "request" in event.detail
  ) {
    const { request, ...result } = event.detail;
    return { request, result };
  }
  return { result: event.detail };
}
export function formatTime(ms: number) {
  return (
    new Date(ms).toLocaleTimeString([], { hour12: false }) +
    "." +
    String(ms % 1000).padStart(3, "0")
  );
}
