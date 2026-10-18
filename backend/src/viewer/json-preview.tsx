import { useState } from "react";
import { Check, Copy, WrapText } from "lucide-react";
import { Button } from "../components/ui/button";

// Render tokens as text nodes, never HTML, so arbitrary log content stays inert.
function tokens(line: string) {
  return line
    .split(
      /("(?:\\.|[^"\\])*"\s*:|"(?:\\.|[^"\\])*"|\btrue\b|\bfalse\b|\bnull\b|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/g,
    )
    .map((part, i) => (
      <span
        key={i}
        className={
          part.startsWith('"')
            ? part.trimEnd().endsWith(":")
              ? "json-key"
              : "json-string"
            : /^(true|false|null)$/.test(part)
              ? "json-literal"
              : /^-?\d/.test(part)
                ? "json-number"
                : undefined
        }
      >
        {part}
      </span>
    ));
}
export function JsonPreview({
  title,
  value,
}: {
  title: string;
  value: unknown;
}) {
  const [wrap, setWrap] = useState(false);
  const [copyState, setCopyState] = useState("Copy");
  const json = JSON.stringify(value, null, 2) ?? "null";
  async function copy() {
    try {
      await navigator.clipboard.writeText(json);
      setCopyState("Copied");
    } catch {
      setCopyState("Copy failed");
    }
    setTimeout(() => setCopyState("Copy"), 1800);
  }
  return (
    <section className="json-panel" aria-label={title}>
      <div className="json-heading">
        <span>{title}</span>
        <div className="flex items-center gap-1">
          <span className="json-format">JSON</span>
          <Button
            variant="ghost"
            size="icon-xs"
            title="Wrap JSON lines"
            aria-label="Wrap JSON lines"
            aria-pressed={wrap}
            onClick={() => setWrap(!wrap)}
          >
            <WrapText />
          </Button>
          <Button
            variant="ghost"
            size="xs"
            onClick={copy}
            aria-label={`Copy ${title}`}
          >
            {copyState === "Copied" ? <Check /> : <Copy />}
            <span aria-live="polite">{copyState}</span>
          </Button>
        </div>
      </div>
      <pre className={wrap ? "json-code wrap" : "json-code"} tabIndex={0}>
        <code>
          {json.split("\n").map((line, i) => (
            <span className="json-line" key={i}>
              <span className="line-number" aria-hidden="true">
                {i + 1}
              </span>
              <span className="line-content">{tokens(line)}</span>
              {"\n"}
            </span>
          ))}
        </code>
      </pre>
    </section>
  );
}
