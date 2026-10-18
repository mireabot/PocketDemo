import { EventLog } from "../../backend/src/events";
import { Faults } from "../../backend/src/faults";
import { seedRecordings } from "../../backend/src/seed";
import { startServer } from "../../backend/src/server";
import { RecordingStore } from "../../backend/src/store";

const port = Number(process.env.PORT ?? 18787);
const hostname = "127.0.0.1";
const faults = new Faults();
const events = EventLog.open({ path: ":memory:", echo: false });
let resets = 0;

function seededStore() {
  const store = RecordingStore.open({ path: ":memory:" });
  for (const recording of seedRecordings({ now: Date.now() })) {
    store.importRecording(resets === 0 ? recording : {
      ...recording,
      title: `Epoch ${resets}: ${recording.title}`,
      transcript: recording.transcript.map(segment => ({ ...segment, text: `Epoch ${resets}: ${segment.text}` })),
    });
  }
  return store;
}

let store = seededStore();
let server = startServer({ port, hostname, store, events, faults });
const control = Bun.serve({
  hostname,
  port: port + 1,
  routes: {
    "/reset": {
      POST: async () => {
        await server.stop(true);
        store.close();
        resets += 1;
        store = seededStore();
        server = startServer({ port, hostname, store, events, faults });
        return Response.json({ epoch: store.epoch, recordings: store.count(), resets });
      },
    },
  },
  fetch: () => new Response(null, { status: 404 }),
});

process.stdout.write(`${JSON.stringify({ url: server.url.href, control: control.url.href })}\n`);
