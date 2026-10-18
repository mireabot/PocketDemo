import { Fragment, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  Activity,
  ArrowDown,
  ArrowRight,
  Braces,
  Check,
  ChevronRight,
  Clock3,
  GitBranch,
  Inbox,
  List,
  Pause,
  Play,
  Radio,
  RefreshCw,
  Search,
  Trash2,
  X,
} from "lucide-react";
import { Button } from "../components/ui/button";
import { Badge } from "../components/ui/badge";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "../components/ui/card";
import { Input } from "../components/ui/input";
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "../components/ui/tabs";
import { JsonPreview } from "./json-preview";
import {
  category,
  detailParts,
  eventPageSchema,
  filterEvents,
  formatTime,
  groupEvents,
  isRetry,
  labels,
  type LogEvent,
} from "./model";

const palette = [
  "#5477b8",
  "#ad7542",
  "#388674",
  "#9273b4",
  "#ad5b70",
  "#427e94",
];
function Outcome({ event }: { event: LogEvent }) {
  return (
    <Badge variant="outline" className={`outcome ${category(event.kind)}`}>
      <span className="status-dot" />
      {event.kind}
    </Badge>
  );
}
function App() {
  const [events, setEvents] = useState<LogEvent[]>([]);
  const [view, setView] = useState("chains");
  const [live, setLive] = useState(true);
  const [hidden, setHidden] = useState(new Set<string>());
  const [outcome, setOutcome] = useState("all");
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [connection, setConnection] = useState("Connecting");
  const [updated, setUpdated] = useState<number | null>(null);
  const [clearing, setClearing] = useState(false);
  const [clearConfirm, setClearConfirm] = useState(false);
  const cursor = useRef(0);
  const generation = useRef(0);
  const polling = useRef(false);
  const clearInProgress = useRef(false);
  const inspector = useRef<HTMLElement>(null);
  const devices = [...new Set(events.map((e) => e.device ?? "server"))];
  const visible = filterEvents(events, hidden, outcome, query);
  const selected = events.find((e) => e.id === selectedId);
  const groups = groupEvents(visible);
  const deviceColor = (device: string | null) =>
    palette[devices.indexOf(device ?? "server") % palette.length] ?? palette[0];

  async function poll() {
    if (polling.current || clearInProgress.current) return;
    polling.current = true;
    const currentGeneration = generation.current;
    try {
      // Drain full pages without waiting for the next live interval.
      let more = true;
      while (more && generation.current === currentGeneration) {
        const response = await fetch(`/logs/events?after=${cursor.current}`, {
          signal: AbortSignal.timeout(10000),
        });
        if (!response.ok) throw new Error("Unable to load events");
        const page = eventPageSchema.parse(await response.json());
        if (generation.current !== currentGeneration) return;
        const last = page.events.at(-1);
        if (last) {
          cursor.current = last.id;
          setEvents((previous) => [...previous, ...page.events]);
        }
        more = page.events.length === 1000;
      }
      if (generation.current === currentGeneration) {
        setConnection("Connected");
        setUpdated(Date.now());
      }
    } catch {
      if (generation.current === currentGeneration)
        setConnection("Connection lost · retry to reconnect");
    } finally {
      polling.current = false;
    }
  }
  useEffect(() => {
    if (!live) return;
    void poll();
    const timer = setInterval(() => void poll(), 1500);
    return () => clearInterval(timer);
  }, [live]);

  async function clearLog() {
    setClearing(true);
    clearInProgress.current = true;
    generation.current += 1;
    try {
      const response = await fetch("/logs/events", { method: "DELETE" });
      if (!response.ok) throw new Error("Unable to clear");
      cursor.current = 0;
      setEvents([]);
      setSelectedId(null);
      setHidden(new Set());
      setClearConfirm(false);
      setConnection("Connected");
    } catch {
      setConnection("Could not clear log · try again");
    } finally {
      setClearing(false);
      clearInProgress.current = false;
    }
  }
  function selectEvent(id: number) {
    setSelectedId(id);
    if (window.matchMedia("(max-width: 1100px)").matches) {
      requestAnimationFrame(() =>
        inspector.current?.scrollIntoView({ block: "start" }),
      );
    }
  }
  function resetFilters() {
    setHidden(new Set());
    setQuery("");
    setOutcome("all");
  }
  const conflicts = events.filter(
    (e) => category(e.kind) === "conflict",
  ).length;
  const stats = [
    {
      label: "Events captured",
      value: events.length,
      icon: Activity,
      note: `${devices.length} sources observed`,
    },
    {
      label: "Writes applied",
      value: events.filter((e) => category(e.kind) === "applied").length,
      icon: Check,
      note: "Committed to the server",
    },
    {
      label: "Conflicts",
      value: conflicts,
      icon: GitBranch,
      note: "Including cursor resets",
    },
    {
      label: "Replays",
      value: events.filter((e) => category(e.kind) === "replay").length,
      icon: RefreshCw,
      note: "Original result returned",
    },
  ];
  function eventCard(event: LogEvent, index: number) {
    return (
      <button
        className={`event-card ${selectedId === event.id ? "selected" : ""}`}
        onClick={() => selectEvent(event.id)}
        aria-pressed={selectedId === event.id}
      >
        <div className="event-top">
          <span className="step-number">
            {String(index + 1).padStart(2, "0")}
          </span>
          <Outcome event={event} />
          <span className="event-id">#{event.id}</span>
        </div>
        <p className="event-summary">{event.summary}</p>
        <div className="event-endpoint">
          <span>{event.method}</span>
          <span title={event.path}>{event.path.split("?")[0]}</span>
        </div>
        <div className="event-bottom">
          <span className="device-label">
            <i style={{ background: deviceColor(event.device) }} />
            {event.device ?? "server"}
          </span>
          <span>
            {event.durationMs} ms <span className="separator">/</span>{" "}
            {event.status || "Dropped"}
          </span>
        </div>
        <div className="event-time">
          {formatTime(event.at)}
          <ChevronRight size={13} />
        </div>
      </button>
    );
  }
  const parts = selected ? detailParts(selected) : null;
  const related = selected?.key
    ? events.filter((e) => e.key === selected.key && e.id !== selected.id)
    : [];
  return (
    <>
      <header className="app-header">
        <div className="brand">
          <span className="brand-mark">
            <Activity size={18} />
          </span>
          <strong>PocketDemo</strong>
          <span className="header-divider" />
          <span>Developer console</span>
        </div>
        <Badge variant="outline" className="environment">
          <span className="status-dot" />
          Local environment
        </Badge>
      </header>
      <main className="page-shell">
        <div className="breadcrumb">
          Workspace
          <ChevronRight size={12} />
          <span>Observability</span>
          <ChevronRight size={12} />
          <strong>Sync logs</strong>
        </div>
        <div className="page-heading">
          <div>
            <div className="eyebrow">OBSERVABILITY</div>
            <h1>
              Sync logs<span className="heading-dot">.</span>
            </h1>
            <p>
              Follow every request, conflict, and retry across your devices.
            </p>
          </div>
          <div className="page-actions">
            <Button
              variant="outline"
              onClick={() => void poll()}
              disabled={clearing}
            >
              <RefreshCw />
              Refresh
            </Button>
            <Button
              variant={live ? "default" : "outline"}
              onClick={() => setLive(!live)}
              aria-pressed={live}
            >
              {live ? <Pause /> : <Play />}
              {live ? "Pause live" : "Resume live"}
            </Button>
          </div>
        </div>
        <div className="stats-grid">
          {stats.map((stat) => (
            <Card key={stat.label} className="stat-card">
              <CardHeader>
                <CardTitle>{stat.label}</CardTitle>
                <stat.icon size={16} />
              </CardHeader>
              <CardContent>
                <div className="stat-value">{stat.value.toLocaleString()}</div>
                <p>{stat.note}</p>
              </CardContent>
            </Card>
          ))}
        </div>
        <div className="workspace">
          <section className="events-section" aria-label="Log events">
            <div className="events-toolbar">
              <Tabs value={view} onValueChange={setView}>
                <TabsList aria-label="Event view">
                  <TabsTrigger value="chains">
                    <GitBranch />
                    Chains
                  </TabsTrigger>
                  <TabsTrigger value="timeline">
                    <List />
                    Timeline
                  </TabsTrigger>
                </TabsList>
              </Tabs>
              <span className="capture-state">
                <span
                  className={`status-dot ${connection === "Connected" && live ? "connected" : ""}`}
                />
                {connection === "Connected"
                  ? live
                    ? "Live updates"
                    : "Updates paused"
                  : connection}
              </span>
            </div>
            <div className="filter-toolbar">
              <div className="search-input">
                <Search size={15} />
                <Input
                  aria-label="Search logs"
                  placeholder="Search events, recordings, or keys…"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                />
                {query && (
                  <button
                    aria-label="Clear search"
                    onClick={() => setQuery("")}
                  >
                    <X size={14} />
                  </button>
                )}
              </div>
              <select
                aria-label="Filter by outcome"
                value={outcome}
                onChange={(e) => setOutcome(e.target.value)}
              >
                <option value="all">All outcomes</option>
                {Object.entries(labels).map(([key, label]) => (
                  <option value={key} key={key}>
                    {label}
                  </option>
                ))}
              </select>
            </div>
            {devices.length > 0 && (
              <div className="device-filters">
                <span>Sources</span>
                {devices.map((device) => (
                  <Button
                    key={device}
                    variant="outline"
                    size="xs"
                    className={
                      hidden.has(device)
                        ? "device-chip hidden-device"
                        : "device-chip"
                    }
                    aria-pressed={!hidden.has(device)}
                    onClick={() =>
                      setHidden((previous) => {
                        const next = new Set(previous);
                        next.has(device)
                          ? next.delete(device)
                          : next.add(device);
                        return next;
                      })
                    }
                  >
                    <i style={{ background: deviceColor(device) }} />
                    {device}
                  </Button>
                ))}
              </div>
            )}
            <div className="section-caption">
              <span>
                {visible.length} of {events.length} events
                {view === "chains" ? ` · ${groups.length} chains` : ""}
              </span>
              <span>
                {view === "chains" ? "Steps oldest first" : "Newest first"}
                <ArrowDown size={12} />
              </span>
            </div>
            <div className="events-content">
              {visible.length === 0 ? (
                <Card className="empty-state">
                  <span className="empty-icon">
                    <Inbox />
                  </span>
                  <h2>
                    {events.length
                      ? "No matching events"
                      : "Ready when your devices are"}
                  </h2>
                  <p>
                    {events.length
                      ? "Try a different search or show more sources."
                      : "Point a simulator at this server. Requests will appear here as they arrive."}
                  </p>
                  {events.length > 0 ? (
                    <Button variant="outline" onClick={resetFilters}>
                      Reset filters
                    </Button>
                  ) : (
                    <code>X-Device-Id: your-device</code>
                  )}
                </Card>
              ) : view === "chains" ? (
                groups.map(({ key, steps }) => (
                  <Card className="chain-card" key={key}>
                    <CardHeader className="chain-header">
                      <div className="chain-title">
                        <span className="chain-icon">
                          {key.startsWith("recording:") ? (
                            <GitBranch size={16} />
                          ) : (
                            <Radio size={16} />
                          )}
                        </span>
                        <div>
                          <CardTitle>
                            {steps[0]?.recordingId ??
                              `Sync · ${steps[0]?.device ?? "server"}`}
                          </CardTitle>
                          <p>
                            {steps.length}{" "}
                            {steps.length === 1 ? "event" : "events"}{" "}
                            <span>·</span>{" "}
                            {
                              new Set(steps.map((e) => e.device ?? "server"))
                                .size
                            }{" "}
                            sources
                          </p>
                        </div>
                      </div>
                      <div className="chain-tail">
                        <span>
                          {steps.filter((e) => category(e.kind) === "conflict")
                            .length > 0 && (
                            <Badge
                              className="outcome conflict"
                              variant="outline"
                            >
                              {
                                steps.filter(
                                  (e) => category(e.kind) === "conflict",
                                ).length
                              }{" "}
                              conflicts
                            </Badge>
                          )}
                        </span>
                        <time>
                          {steps.at(-1) && formatTime(steps.at(-1)?.at ?? 0)}
                        </time>
                      </div>
                    </CardHeader>
                    <CardContent className="chain-flow">
                      {steps.map((event, index) => (
                        <Fragment key={event.id}>
                          {index > 0 && (
                            <span
                              className={`flow-arrow ${isRetry(steps[index - 1], event) ? "retry" : ""}`}
                            >
                              {isRetry(steps[index - 1], event) ? (
                                <>
                                  <RefreshCw size={14} />
                                  <small>retry</small>
                                </>
                              ) : (
                                <ArrowRight size={16} />
                              )}
                            </span>
                          )}
                          {eventCard(event, index)}
                        </Fragment>
                      ))}
                    </CardContent>
                  </Card>
                ))
              ) : (
                <Card className="timeline-card">
                  <div className="timeline-head">
                    <span>Time / source</span>
                    <span>Event / request</span>
                    <span>Result</span>
                  </div>
                  {visible.toReversed().map((event) => (
                    <button
                      className={`timeline-row ${selectedId === event.id ? "selected" : ""}`}
                      key={event.id}
                      onClick={() => selectEvent(event.id)}
                      aria-pressed={selectedId === event.id}
                    >
                      <div className="timeline-source">
                        <time>{formatTime(event.at)}</time>
                        <span className="device-label">
                          <i
                            style={{ background: deviceColor(event.device) }}
                          />
                          {event.device ?? "server"}
                        </span>
                      </div>
                      <div className="timeline-event">
                        <div>
                          <Outcome event={event} />
                          <span className="event-id">#{event.id}</span>
                        </div>
                        <p>{event.summary}</p>
                        <code>
                          {event.method} {event.path}
                        </code>
                      </div>
                      <div className="timeline-result">
                        <strong>{event.status || "Dropped"}</strong>
                        <span>{event.durationMs} ms</span>
                        <ChevronRight size={14} />
                      </div>
                    </button>
                  ))}
                </Card>
              )}
            </div>
            <footer className="events-footer">
              <span>
                {updated
                  ? `Last checked ${new Date(updated).toLocaleTimeString([], { hour12: false })}`
                  : "Waiting for server"}
              </span>
              <Button
                variant="ghost"
                size="xs"
                onClick={() => setClearConfirm(true)}
                disabled={!events.length || clearing}
              >
                <Trash2 />
                Clear log
              </Button>
            </footer>
            {clearConfirm && (
              <div className="clear-confirm" role="alert">
                <span>Delete all captured events from this server?</span>
                <Button
                  size="xs"
                  variant="outline"
                  onClick={() => setClearConfirm(false)}
                  disabled={clearing}
                >
                  Cancel
                </Button>
                <Button
                  size="xs"
                  variant="destructive"
                  onClick={() => void clearLog()}
                  disabled={clearing}
                >
                  {clearing ? "Clearing…" : "Delete events"}
                </Button>
              </div>
            )}
          </section>
          <aside
            className="inspector"
            aria-label="Event inspector"
            ref={inspector}
          >
            <div className="inspector-heading">
              <span>
                <Braces size={16} />
                Event inspector
              </span>
              {selected && (
                <Button
                  variant="ghost"
                  size="icon-xs"
                  aria-label="Close event details"
                  onClick={() => setSelectedId(null)}
                >
                  <X />
                </Button>
              )}
            </div>
            {!selected ? (
              <div className="inspector-empty">
                <div className="inspector-illustration">
                  <div />
                  <div />
                  <div />
                  <span>
                    <Braces size={23} />
                  </span>
                </div>
                <h2>A closer look at every event</h2>
                <p>
                  Select an event to inspect its request,
                  <br />
                  result, and raw JSON.
                </p>
                <div className="inspector-hint">
                  <span>01</span>Choose an event in a chain or timeline
                </div>
                <div className="inspector-hint">
                  <span>02</span>Inspect the outcome and logged payload
                </div>
                <div className="inspector-hint">
                  <span>03</span>Trace retries with the same key
                </div>
              </div>
            ) : (
              <div className="inspector-body" key={selected.id}>
                <div className="detail-overline">
                  <span>EVENT #{selected.id}</span>
                  <span>{formatTime(selected.at)}</span>
                </div>
                <Outcome event={selected} />
                <h2 className="detail-summary">{selected.summary}</h2>
                <div className="request-line">
                  <Badge variant="secondary">{selected.method}</Badge>
                  <code>{selected.path}</code>
                </div>
                {!visible.some((e) => e.id === selected.id) && (
                  <p className="filtered-selection">
                    This event is outside the current filters.
                  </p>
                )}
                <Tabs defaultValue="overview" className="detail-tabs">
                  <TabsList aria-label="Event detail view">
                    <TabsTrigger value="overview">Overview</TabsTrigger>
                    <TabsTrigger value="raw">
                      <Braces size={13} />
                      Raw JSON
                    </TabsTrigger>
                  </TabsList>
                  <TabsContent value="overview">
                    <dl className="metadata">
                      <div>
                        <dt>Status</dt>
                        <dd
                          className={
                            selected.status >= 400 ? "text-amber-700" : ""
                          }
                        >
                          {selected.status
                            ? `HTTP ${selected.status}`
                            : "Response dropped"}
                        </dd>
                      </div>
                      <div>
                        <dt>Duration</dt>
                        <dd>
                          <Clock3 size={12} />
                          {selected.durationMs} ms
                        </dd>
                      </div>
                      <div>
                        <dt>Device</dt>
                        <dd className="device-label">
                          <i
                            style={{ background: deviceColor(selected.device) }}
                          />
                          {selected.device ?? "server"}
                        </dd>
                      </div>
                      <div>
                        <dt>Recorded</dt>
                        <dd>{new Date(selected.at).toLocaleString()}</dd>
                      </div>
                      <div>
                        <dt>Recording</dt>
                        <dd>{selected.recordingId ?? "—"}</dd>
                      </div>
                      <div>
                        <dt>Request ID</dt>
                        <dd>{selected.requestId}</dd>
                      </div>
                      <div>
                        <dt>Idempotency key</dt>
                        <dd>{selected.key ?? "—"}</dd>
                      </div>
                    </dl>
                    {parts && "request" in parts && (
                      <JsonPreview
                        title="Logged request fields"
                        value={parts.request}
                      />
                    )}
                    {parts && (
                      <JsonPreview
                        title="Logged result / detail"
                        value={parts.result}
                      />
                    )}
                    <p className="payload-note">
                      Payloads show the data captured by the event log.
                    </p>
                  </TabsContent>
                  <TabsContent value="raw">
                    <JsonPreview title="Full event" value={selected} />
                  </TabsContent>
                </Tabs>
                {related.length > 0 && (
                  <section className="related-events">
                    <h3>
                      <RefreshCw size={14} />
                      Same idempotency key
                      <Badge variant="secondary">{related.length}</Badge>
                    </h3>
                    {related.map((event) => (
                      <button
                        key={event.id}
                        onClick={() => selectEvent(event.id)}
                      >
                        <span className="event-id">#{event.id}</span>
                        <span>{event.kind}</span>
                        <ChevronRight size={13} />
                      </button>
                    ))}
                  </section>
                )}
              </div>
            )}
          </aside>
        </div>
        <div className="page-footer">
          <span>
            <Activity size={12} />
            PocketDemo / Sync observability
          </span>
          <span>Local server · polling every 1.5s</span>
        </div>
      </main>
    </>
  );
}
const root = document.getElementById("root");
if (root) createRoot(root).render(<App />);
