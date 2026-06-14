/**
 * Top-bar Activity indicator + popover listing recent background tasks.
 * Click an item to jump to the full Background Tasks page.
 */
import { Link, useNavigate } from "react-router-dom";
import { Activity, CheckCircle2, XCircle, Loader2, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Progress } from "@/components/ui/progress";
import {
  useBackgroundTasks,
  type BackgroundTask,
} from "@/lib/backgroundTasks/store";

function statusIcon(t: BackgroundTask) {
  if (t.status === "running") return <Loader2 className="w-3.5 h-3.5 animate-spin text-primary" />;
  if (t.status === "success") return <CheckCircle2 className="w-3.5 h-3.5 text-green-600" />;
  return <XCircle className="w-3.5 h-3.5 text-destructive" />;
}

export default function BackgroundTaskBadge() {
  const tasks = useBackgroundTasks();
  const navigate = useNavigate();
  const running = tasks.filter((t) => t.status === "running").length;
  const failed = tasks.filter((t) => t.status === "failed").length;
  if (tasks.length === 0) return null;

  const recent = tasks.slice(0, 6);

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="icon" className="relative" aria-label="Background tasks">
          <Activity className={`w-5 h-5 ${running ? "text-primary" : ""}`} />
          {running > 0 && (
            <span className="absolute -top-1 -right-1 bg-primary text-primary-foreground text-[10px] md:text-xs rounded-full w-4 h-4 md:w-5 md:h-5 flex items-center justify-center">
              {running > 9 ? "9+" : running}
            </span>
          )}
          {running === 0 && failed > 0 && (
            <span className="absolute -top-0.5 -right-0.5 w-2 h-2 bg-destructive rounded-full" />
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-80 p-0" align="end">
        <div className="flex items-center justify-between px-3 py-2 border-b">
          <p className="text-sm font-semibold">Background tasks</p>
          <button
            className="text-xs text-primary hover:underline"
            onClick={() => navigate("/background-tasks")}
          >
            View all
          </button>
        </div>
        <div className="max-h-96 overflow-y-auto divide-y">
          {recent.map((t) => (
            <Link
              key={t.id}
              to="/background-tasks"
              className="block px-3 py-2.5 hover:bg-muted/60 transition"
            >
              <div className="flex items-start gap-2">
                <div className="mt-0.5">{statusIcon(t)}</div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-medium truncate flex-1">{t.title}</p>
                    <ChevronRight className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
                  </div>
                  {t.subtitle && (
                    <p className="text-xs text-muted-foreground truncate">{t.subtitle}</p>
                  )}
                  {t.status === "running" && (
                    <div className="mt-1.5">
                      <Progress value={(t.progress ?? 0) * 100} className="h-1" />
                      {t.total ? (
                        <p className="text-[11px] text-muted-foreground mt-0.5">
                          {t.processed ?? 0} / {t.total}
                        </p>
                      ) : null}
                    </div>
                  )}
                  {t.status === "failed" && t.error && (
                    <p className="text-[11px] text-destructive mt-0.5 line-clamp-2">{t.error}</p>
                  )}
                </div>
              </div>
            </Link>
          ))}
        </div>
      </PopoverContent>
    </Popover>
  );
}
