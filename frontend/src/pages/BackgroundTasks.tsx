/**
 * Dedicated page that lists every background task with full details:
 * progress, status, error messages, and a per-task log. Linked from the
 * left sidebar (near WhatsApp Logs) and the top-bar Activity popover.
 */
import { useMemo, useState } from "react";
import {
  Activity,
  CheckCircle2,
  XCircle,
  Loader2,
  Trash2,
  ChevronDown,
  ChevronRight,
  Inbox,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { Badge } from "@/components/ui/badge";
import {
  useBackgroundTasks,
  removeTask,
  clearCompleted,
  type BackgroundTask,
} from "@/lib/backgroundTasks/store";
import { useNavigate } from "react-router-dom";

const FILTERS = [
  { id: "all", label: "All" },
  { id: "running", label: "Running" },
  { id: "success", label: "Completed" },
  { id: "failed", label: "Failed" },
] as const;
type FilterId = (typeof FILTERS)[number]["id"];

function StatusPill({ t }: { t: BackgroundTask }) {
  if (t.status === "running")
    return (
      <Badge variant="secondary" className="gap-1">
        <Loader2 className="w-3 h-3 animate-spin" /> Running
      </Badge>
    );
  if (t.status === "success")
    return (
      <Badge variant="secondary" className="gap-1 bg-green-100 text-green-800 hover:bg-green-100">
        <CheckCircle2 className="w-3 h-3" /> Completed
      </Badge>
    );
  if (t.status === "failed")
    return (
      <Badge variant="destructive" className="gap-1">
        <XCircle className="w-3 h-3" /> Failed
      </Badge>
    );
  return <Badge variant="outline">Cancelled</Badge>;
}

function formatTime(ts?: number) {
  if (!ts) return "—";
  return new Date(ts).toLocaleString();
}

function TaskCard({ task }: { task: BackgroundTask }) {
  const [open, setOpen] = useState(false);
  const navigate = useNavigate();
  const duration =
    task.finishedAt && task.startedAt
      ? Math.max(0, Math.round((task.finishedAt - task.startedAt) / 1000))
      : null;

  return (
    <div className="border rounded-lg bg-card overflow-hidden">
      <div className="p-4">
        <div className="flex items-start gap-3">
          <button
            onClick={() => setOpen((v) => !v)}
            className="mt-1 text-muted-foreground hover:text-foreground"
            aria-label={open ? "Collapse" : "Expand"}
          >
            {open ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
          </button>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <h3 className="font-medium truncate">{task.title}</h3>
              <StatusPill t={task} />
            </div>
            {task.subtitle && (
              <p className="text-sm text-muted-foreground mt-0.5">{task.subtitle}</p>
            )}

            {task.status === "running" && (
              <div className="mt-3">
                <Progress value={(task.progress ?? 0) * 100} className="h-1.5" />
                <div className="flex items-center justify-between text-xs text-muted-foreground mt-1">
                  <span>
                    {task.total
                      ? `${task.processed ?? 0} of ${task.total}`
                      : task.progress != null
                      ? `${Math.round((task.progress ?? 0) * 100)}%`
                      : "Working…"}
                  </span>
                  <span>Started {formatTime(task.startedAt)}</span>
                </div>
              </div>
            )}

            {task.status !== "running" && (
              <div className="text-xs text-muted-foreground mt-2 flex gap-3 flex-wrap">
                <span>Started {formatTime(task.startedAt)}</span>
                {task.finishedAt && <span>Finished {formatTime(task.finishedAt)}</span>}
                {duration != null && <span>{duration}s</span>}
                {task.total != null && (
                  <span>
                    {task.processed ?? task.total} / {task.total} processed
                  </span>
                )}
              </div>
            )}

            {task.status === "failed" && task.error && (
              <div className="mt-2 text-sm rounded-md border border-destructive/30 bg-destructive/5 text-destructive px-3 py-2">
                {task.error}
              </div>
            )}
          </div>

          <div className="flex flex-col items-end gap-2 shrink-0">
            {task.href && (
              <Button variant="outline" size="sm" onClick={() => navigate(task.href!)}>
                Open
              </Button>
            )}
            {task.status !== "running" && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => removeTask(task.id)}
                className="text-muted-foreground hover:text-destructive"
              >
                <Trash2 className="w-4 h-4" />
              </Button>
            )}
          </div>
        </div>
      </div>

      {open && (
        <div className="border-t bg-muted/30 px-4 py-3">
          <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide mb-2">
            Activity log
          </p>
          {task.details.length === 0 ? (
            <p className="text-xs text-muted-foreground italic">No log entries yet.</p>
          ) : (
            <ul className="space-y-1 max-h-60 overflow-y-auto">
              {task.details.map((d, i) => (
                <li key={i} className="text-xs flex gap-2">
                  <span className="text-muted-foreground tabular-nums shrink-0">
                    {new Date(d.ts).toLocaleTimeString()}
                  </span>
                  <span
                    className={
                      d.level === "error"
                        ? "text-destructive"
                        : d.level === "warn"
                        ? "text-amber-600"
                        : "text-foreground/80"
                    }
                  >
                    {d.message}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}

export default function BackgroundTasksPage() {
  const tasks = useBackgroundTasks();
  const [filter, setFilter] = useState<FilterId>("all");

  const counts = useMemo(
    () => ({
      all: tasks.length,
      running: tasks.filter((t) => t.status === "running").length,
      success: tasks.filter((t) => t.status === "success").length,
      failed: tasks.filter((t) => t.status === "failed").length,
    }),
    [tasks],
  );

  const filtered = tasks.filter((t) => (filter === "all" ? true : t.status === filter));
  const hasCompleted = tasks.some((t) => t.status !== "running");

  return (
    <div className="space-y-5">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Activity className="w-6 h-6 text-primary" /> Background Tasks
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Everything Nuru is doing for you in the background — uploads, bulk
            actions, reminders, and exports. Safe to close any dialog; tasks
            keep running here.
          </p>
        </div>
        {hasCompleted && (
          <Button variant="outline" size="sm" onClick={clearCompleted}>
            Clear completed
          </Button>
        )}
      </div>

      <div className="flex gap-2 mb-4 flex-wrap">
        {FILTERS.map((f) => (
          <button
            key={f.id}
            onClick={() => setFilter(f.id)}
            className={`px-3 py-1.5 rounded-full text-sm border transition ${
              filter === f.id
                ? "bg-primary text-primary-foreground border-primary"
                : "bg-card hover:bg-muted/60"
            }`}
          >
            {f.label}
            <span className="ml-1.5 text-xs opacity-75">{counts[f.id]}</span>
          </button>
        ))}
      </div>

      {filtered.length === 0 ? (
        <div className="border rounded-lg p-10 text-center text-muted-foreground">
          <Inbox className="w-10 h-10 mx-auto mb-2 opacity-40" />
          <p className="text-sm">No tasks here yet.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {filtered.map((t) => (
            <TaskCard key={t.id} task={t} />
          ))}
        </div>
      )}
    </div>
  );
}
