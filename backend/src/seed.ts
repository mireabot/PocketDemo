import { z } from "zod";
import type { NewRecording, RecordingId, TranscriptSegment } from "./domain";
import seedData from "./seed-data.json";

const seedSchema = z
  .array(
    z.strictObject({
      title: z.string().refine((s) => s.trim() !== ""),
      summary: z.string(),
      transcript: z.array(z.string()).min(1),
    }),
  )
  .min(1);

/** Every 25th recording gets a 3000-segment transcript, so "never ship transcripts in the list" matters. */
const LONG_EVERY = 25;
const LONG_SEGMENTS = 3000;
const SEGMENT_MS = 4000;

/** Demo library from seed-data.json. Oldest first, so the newest recordings get the highest versions. */
export function seedRecordings({ now }: { now: number }): NewRecording[] {
  const records = seedSchema.parse(seedData);
  const spacing = 12 * 60 * 60 * 1000;
  const oldest = now - records.length * spacing;
  return records.map((rec, i): NewRecording => {
    const length = (i + 1) % LONG_EVERY === 0 ? LONG_SEGMENTS : rec.transcript.length;
    const transcript: TranscriptSegment[] = Array.from({ length }, (_, s) => ({
      startMs: s * SEGMENT_MS,
      text: rec.transcript[s % rec.transcript.length] ?? "",
    }));
    return {
      id: `rec_${String(i + 1).padStart(4, "0")}` as RecordingId,
      title: rec.title,
      summary: rec.summary,
      createdAt: oldest + i * spacing,
      transcript,
    };
  });
}
