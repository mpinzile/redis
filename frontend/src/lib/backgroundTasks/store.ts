/**
 * Global background-task registry.
 *
 * Any long-running async action (bulk upload, bulk delete, import, export,
 * report generation, bulk messaging, …) should register a task here so it
 * shows up in the top-bar Activity menu and the /background-tasks page,
 * even after the user dismisses the originating dialog.
 *
 * The store is intentionally framework-agnostic — `useSyncExternalStore`
 * gives us React reactivity without adding a state library.
 */
import { useSyncExternalStore } from "react";

export type TaskStatus = "running" | "success" | "failed" | "cancelled";
export type TaskKind =
  | "upload"
  | "import"
  | "bulk-remove"
  | "bulk-message"
  | "notify"
  | "export"
  | "report"
  | "generic";

export interface TaskDetail {
  ts: number;
  level: "info" | "warn" | "error";
  message: string;
}

export interface BackgroundTask {
  id: string;
  title: string;
  subtitle?: string;
  kind: TaskKind;
  status: TaskStatus;
  /** 0..1 — omit when unknown */
  progress?: number;
  processed?: number;
  total?: number;
  startedAt: number;
  finishedAt?: number;
  error?: string;
  details: TaskDetail[];
  /** Optional poller invoked every ~2s while running. */
  poll?: (ctx: TaskContext) => Promise<void>;
  /** Optional cancel handler. */
  cancel?: () => Promise<void> | void;
  meta?: Record<string, any>;
  /** Optional path the user can deep-link to (e.g. /event-management/:id). */
  href?: string;
}

export interface TaskContext {
  update: (patch: Partial<BackgroundTask>) => void;
  detail: (entry: Omit<TaskDetail, "ts"> | string) => void;
  finish: (status: Exclude<TaskStatus, "running">, error?: string) => void;
}

type Listener = () => void;

const tasks = new Map<string, BackgroundTask>();
const listeners = new Set<Listener>();
let snapshot: BackgroundTask[] = [];

function rebuild() {
  snapshot = Array.from(tasks.values()).sort((a, b) => b.startedAt - a.startedAt);
  listeners.forEach((l) => l());
}

function ctxFor(id: string): TaskContext {
  return {
    update: (patch) => updateTask(id, patch),
    detail: (entry) =>
      appendDetail(
        id,
        typeof entry === "string" ? { level: "info", message: entry } : entry,
      ),
    finish: (status, error) => finishTask(id, status, error),
  };
}

export function startTask(
  partial: Omit<BackgroundTask, "id" | "status" | "startedAt" | "details"> &
    Partial<Pick<BackgroundTask, "id" | "status" | "startedAt" | "details">>,
): string {
  const id =
    partial.id ?? `bg_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
  const task: BackgroundTask = {
    status: "running",
    startedAt: Date.now(),
    details: [],
    ...partial,
    id,
  };
  tasks.set(id, task);
  rebuild();
  return id;
}

export function updateTask(id: string, patch: Partial<BackgroundTask>) {
  const t = tasks.get(id);
  if (!t) return;
  tasks.set(id, { ...t, ...patch });
  rebuild();
}

export function appendDetail(id: string, entry: Omit<TaskDetail, "ts">) {
  const t = tasks.get(id);
  if (!t) return;
  const next: TaskDetail = { ts: Date.now(), ...entry };
  const details = [...t.details, next].slice(-100);
  tasks.set(id, { ...t, details });
  rebuild();
}

export function finishTask(id: string, status: Exclude<TaskStatus, "running">, error?: string) {
  const t = tasks.get(id);
  if (!t) return;
  tasks.set(id, { ...t, status, error, finishedAt: Date.now() });
  rebuild();
}

export function removeTask(id: string) {
  if (tasks.delete(id)) rebuild();
}

export function clearCompleted() {
  let changed = false;
  for (const [id, t] of tasks) {
    if (t.status !== "running") {
      tasks.delete(id);
      changed = true;
    }
  }
  if (changed) rebuild();
}

function subscribe(l: Listener) {
  listeners.add(l);
  return () => listeners.delete(l);
}

function getSnapshot() {
  return snapshot;
}

export function useBackgroundTasks(): BackgroundTask[] {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

export function getTask(id: string): BackgroundTask | undefined {
  return tasks.get(id);
}

// Polling loop ------------------------------------------------------------
let pollerStarted = false;
function ensurePoller() {
  if (pollerStarted || typeof window === "undefined") return;
  pollerStarted = true;
  setInterval(() => {
    for (const t of tasks.values()) {
      if (t.status !== "running" || !t.poll) continue;
      // Fire and forget; poll implementations must guard their own errors.
      t.poll(ctxFor(t.id)).catch((err) => {
        appendDetail(t.id, {
          level: "error",
          message: err?.message || "Polling error",
        });
      });
    }
  }, 2000);
}
ensurePoller();

/**
 * Convenience helper: register a task and run an async function.
 *
 * The returned promise resolves with the function's return value (or rejects
 * with its error). The task is marked success/failed automatically when the
 * promise settles. The user can dismiss the originating dialog freely — the
 * task keeps running.
 */
export async function runAsTask<T>(
  opts: {
    title: string;
    subtitle?: string;
    kind?: TaskKind;
    meta?: Record<string, any>;
    href?: string;
  },
  run: (ctx: TaskContext) => Promise<T>,
): Promise<T> {
  const id = startTask({
    title: opts.title,
    subtitle: opts.subtitle,
    kind: opts.kind ?? "generic",
    meta: opts.meta,
    href: opts.href,
  });
  const ctx = ctxFor(id);
  try {
    const result = await run(ctx);
    const cur = tasks.get(id);
    if (cur && cur.status === "running") finishTask(id, "success");
    return result;
  } catch (err: any) {
    const msg = err?.message || String(err) || "Task failed";
    appendDetail(id, { level: "error", message: msg });
    finishTask(id, "failed", msg);
    throw err;
  }
}
