/**
 * Small inline hint shown inside long-running action dialogs to tell users
 * they can safely close the dialog — the work continues in the background
 * and can be tracked from the top-bar Activity menu.
 */
import { Info } from "lucide-react";

export default function DismissibleHint({
  className = "",
}: {
  className?: string;
}) {
  return (
    <div
      className={`flex items-start gap-2 rounded-md border border-primary/20 bg-primary/5 px-3 py-2 text-xs text-foreground/80 ${className}`}
    >
      <Info className="w-4 h-4 text-primary shrink-0 mt-0.5" />
      <p>
        You can safely close this dialog — the action will keep running in the
        background. Track its progress any time from the{" "}
        <span className="font-medium">Activity icon</span> in the top bar or
        the <span className="font-medium">Background Tasks</span> page.
      </p>
    </div>
  );
}
