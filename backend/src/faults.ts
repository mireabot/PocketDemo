import { z } from "zod";
import type { DeviceId } from "./domain";

/**
 * Per-device faults the app can't produce by itself. Going offline is the app's own airplane-mode
 * switch; what only the server can do is commit a write and then lose the reply.
 *
 *   dropResponses: n   the next n PATCH/DELETE requests from this device commit, then the socket is
 *                      cut before the reply. The client sees a network error: a real lost ack.
 *   latencyMs: n       every request from this device waits n ms before it is handled.
 *
 * The app's Save menu can also fault a single write with an `X-Sim-Fault` header: `slow` imitates
 * an overloaded link (late first byte, then the reply trickles in), `drop` commits the write and
 * cuts the reply. A retry is sent without it.
 *
 * Control routes accept `latest` in place of a device id: the device that sent the most recent
 * /recordings request. Pull to refresh on a simulator, then configure `latest`.
 *
 * In memory only: a server restart clears every rule.
 */
export const faultRuleSchema = z.strictObject({
  dropResponses: z.number().int().min(0).max(100).default(0),
  latencyMs: z.number().int().min(0).max(30_000).default(0),
});
export type FaultRule = z.infer<typeof faultRuleSchema>;

export class Faults {
  private readonly rules = new Map<DeviceId, FaultRule>();
  private latest: DeviceId | null = null;

  noteRequest(device: DeviceId | null): void {
    if (device) this.latest = device;
  }

  /** `latest` means the device that sent the most recent request; null when no device has yet. */
  resolve(device: DeviceId): DeviceId | null {
    return device === "latest" ? this.latest : device;
  }

  set({ device, rule }: { device: DeviceId; rule: FaultRule }): void {
    if (rule.dropResponses === 0 && rule.latencyMs === 0) this.rules.delete(device);
    else this.rules.set(device, rule);
  }

  clear(device: DeviceId): void {
    this.rules.delete(device);
  }

  clearAll(): void {
    this.rules.clear();
  }

  all(): Record<string, FaultRule> {
    return Object.fromEntries(this.rules);
  }

  latencyFor(device: DeviceId | null): number {
    return device ? (this.rules.get(device)?.latencyMs ?? 0) : 0;
  }

  /** Consumes one drop if this device has any left. Call after the write has committed. */
  takeDrop(device: DeviceId | null): boolean {
    if (!device) return false;
    const rule = this.rules.get(device);
    if (!rule || rule.dropResponses === 0) return false;
    this.set({ device, rule: { ...rule, dropResponses: rule.dropResponses - 1 } });
    return true;
  }
}
