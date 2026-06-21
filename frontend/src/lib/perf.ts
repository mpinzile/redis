/**
 * Nuru web performance instrumentation — Stage 1.
 *
 * - markTap(action): records the moment a user-facing action started.
 * - markRendered(action): records when the screen finished updating.
 * - installFetchTracer(): wraps window.fetch to log request/response timing,
 *   payload size, and the X-Request-ID echoed from the backend so a web
 *   action can be correlated with the corresponding backend perf line.
 *
 * Outputs structured JSON lines via console.info. A future telemetry sink
 * can subscribe via window.addEventListener("nuru:perf", ...).
 *
 * Disable by setting localStorage.NURU_PERF = "off".
 */

type PerfRecord = Record<string, unknown> & {
  evt: string;
  ts: number;
};

const ENABLED = (() => {
  try {
    return typeof window !== "undefined" &&
      window.localStorage?.getItem("NURU_PERF") !== "off";
  } catch {
    return true;
  }
})();

const taps = new Map<string, number>();

function emit(record: PerfRecord): void {
  if (!ENABLED) return;
  try {
    // eslint-disable-next-line no-console
    console.info("[nuru.perf]", JSON.stringify(record));
    window.dispatchEvent(new CustomEvent("nuru:perf", { detail: record }));
  } catch {
    /* never let logging break the app */
  }
}

export function markTap(action: string, meta?: Record<string, unknown>): void {
  if (!ENABLED) return;
  const t = performance.now();
  taps.set(action, t);
  emit({ evt: "tap", action, ts: t, ...meta });
}

export function markRendered(
  action: string,
  meta?: Record<string, unknown>,
): void {
  if (!ENABLED) return;
  const t = performance.now();
  const started = taps.get(action);
  taps.delete(action);
  emit({
    evt: "rendered",
    action,
    ts: t,
    waited_ms: started != null ? Math.round(t - started) : null,
    ...meta,
  });
}

export function markBgStart(action: string): void {
  if (!ENABLED) return;
  emit({ evt: "bg_start", action, ts: performance.now() });
}

export function markBgEnd(action: string, meta?: Record<string, unknown>): void {
  if (!ENABLED) return;
  emit({ evt: "bg_end", action, ts: performance.now(), ...meta });
}

let fetchInstalled = false;

export function installFetchTracer(): void {
  if (!ENABLED || fetchInstalled) return;
  if (typeof window === "undefined" || !window.fetch) return;
  fetchInstalled = true;

  const orig = window.fetch.bind(window);
  window.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
    const started = performance.now();
    const method =
      (init?.method ||
        (typeof input !== "string" && "method" in (input as Request)
          ? (input as Request).method
          : "GET")) || "GET";
    const url =
      typeof input === "string"
        ? input
        : input instanceof URL
          ? input.toString()
          : (input as Request).url;

    let status = 0;
    let bytes = 0;
    let requestId: string | null = null;

    try {
      const res = await orig(input, init);
      status = res.status;
      requestId = res.headers.get("x-request-id");
      const cl = res.headers.get("content-length");
      if (cl) bytes = parseInt(cl, 10) || 0;
      return res;
    } finally {
      const dur = Math.round(performance.now() - started);
      emit({
        evt: "fetch",
        ts: performance.now(),
        method,
        url: shortenUrl(url),
        status,
        bytes,
        dur_ms: dur,
        rid: requestId,
      });
    }
  };
}

function shortenUrl(u: string): string {
  // Drop origin and query string for log brevity; keep path template-ish.
  try {
    const parsed = new URL(u, window.location.origin);
    return parsed.pathname;
  } catch {
    return u;
  }
}
