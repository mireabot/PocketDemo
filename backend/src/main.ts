import { mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { EventLog } from "./events";
import { Faults } from "./faults";
import { seedRecordings } from "./seed";
import { startServer } from "./server";
import { RecordingStore } from "./store";

const port = Number(process.env.PORT ?? 8787);
const hostname = process.env.HOST ?? "127.0.0.1";
const dataDir = process.env.DATA_DIR ?? join(import.meta.dir, "..", "data");

const dbPath = join(dataDir, "pocket.db");
const eventsPath = join(dataDir, "events.db");

mkdirSync(dataDir, { recursive: true });
if (process.argv.includes("--reset")) {
  // A new database gets a new epoch, so clients holding old cursors are told to resync.
  for (const base of [dbPath, eventsPath]) for (const suffix of ["", "-wal", "-shm"]) rmSync(base + suffix, { force: true });
}

const store = RecordingStore.open({ path: dbPath });
if (store.count() === 0) for (const rec of seedRecordings({ now: Date.now() })) store.importRecording(rec);
const pruned = store.pruneAppliedOps();

const events = EventLog.open({ path: eventsPath });
const server = startServer({ port, hostname, store, events, faults: new Faults() });

process.stdout.write(
  `${JSON.stringify({ msg: "listening", url: server.url.href, logs: `${server.url.href}logs`, epoch: store.epoch, recordings: store.count(), prunedKeys: pruned })}\n`,
);
