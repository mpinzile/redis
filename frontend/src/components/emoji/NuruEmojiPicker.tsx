import { useEffect, useMemo, useState } from "react";
import { Search, X, Clock } from "lucide-react";
import {
  CATEGORIES,
  REACTION_ROW,
  loadRecent,
  searchEmojis,
  topFrequent,
  trackEmoji,
} from "./data";
import { cn } from "@/lib/utils";

export interface NuruEmojiPickerProps {
  onSelect: (emoji: string) => void;
  onClose?: () => void;
  /** When true, show the large reactions row at top (e.g. for Glow). */
  reactionMode?: boolean;
  className?: string;
}

/**
 * Modern Nuru emoji picker — categories, search, recent, reactions row.
 * Uses semantic design tokens; works inside a popover or a sheet.
 */
export function NuruEmojiPicker({
  onSelect,
  onClose,
  reactionMode = false,
  className,
}: NuruEmojiPickerProps) {
  const [categoryIndex, setCategoryIndex] = useState(0);
  const [query, setQuery] = useState("");
  const [recent, setRecent] = useState<string[]>([]);
  const [frequent, setFrequent] = useState<string[]>(REACTION_ROW);

  useEffect(() => {
    setRecent(loadRecent());
    setFrequent(topFrequent(8));
  }, []);

  const cat = CATEGORIES[categoryIndex];
  const searching = query.trim().length > 0;
  const results = useMemo(
    () => (searching ? searchEmojis(query) : []),
    [query, searching],
  );

  const handlePick = (e: string) => {
    trackEmoji(e);
    setRecent((prev) => [e, ...prev.filter((x) => x !== e)].slice(0, 32));
    setFrequent(topFrequent(8));
    onSelect(e);
  };

  return (
    <div
      className={cn(
        "flex h-[380px] w-[340px] flex-col overflow-hidden rounded-2xl border border-border bg-background shadow-xl",
        className,
      )}
    >
      {/* Header: search + close */}
      <div className="flex items-center gap-2 border-b border-border px-3 py-2">
        <div className="flex h-9 flex-1 items-center gap-2 rounded-full border border-border bg-muted/40 px-3">
          <Search className="h-4 w-4 text-muted-foreground" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search emoji"
            className="h-full flex-1 border-0 bg-transparent text-sm text-foreground placeholder:text-muted-foreground focus:outline-none"
          />
        </div>
        {onClose && (
          <button
            type="button"
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-full border border-border text-foreground hover:bg-muted"
            aria-label="Close emoji picker"
          >
            <X className="h-4 w-4" />
          </button>
        )}
      </div>

      {/* Reactions row */}
      {reactionMode && !searching && (
        <div className="flex items-center justify-between gap-1 border-b border-border bg-muted/30 px-3 py-2">
          {REACTION_ROW.map((e) => (
            <button
              key={e}
              type="button"
              onClick={() => handlePick(e)}
              className="rounded-full px-1.5 py-0.5 text-2xl transition-transform hover:scale-125"
            >
              {e}
            </button>
          ))}
        </div>
      )}

      {/* Body */}
      {searching ? (
        <div className="flex-1 overflow-y-auto px-2 py-2">
          {results.length === 0 ? (
            <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
              No emoji found
            </div>
          ) : (
            <div className="grid grid-cols-8 gap-1">
              {results.map((e) => (
                <button
                  key={e}
                  type="button"
                  onClick={() => handlePick(e)}
                  className="aspect-square rounded-md text-xl hover:bg-muted"
                >
                  {e}
                </button>
              ))}
            </div>
          )}
        </div>
      ) : (
        <div className="flex min-h-0 flex-1">
          {/* Rail */}
          <div className="flex w-12 flex-col border-r border-border bg-muted/20 py-1">
            {CATEGORIES.map((c, i) => (
              <button
                key={c.id}
                type="button"
                onClick={() => setCategoryIndex(i)}
                title={c.label}
                className={cn(
                  "flex h-10 items-center justify-center text-lg transition-colors",
                  categoryIndex === i
                    ? "border-r-2 border-primary bg-background text-foreground"
                    : "text-muted-foreground hover:text-foreground",
                )}
              >
                {c.icon}
              </button>
            ))}
          </div>

          {/* Grid */}
          <div className="flex-1 overflow-y-auto px-2 py-2">
            {recent.length > 0 && categoryIndex === 0 && (
              <>
                <div className="mb-1 flex items-center gap-1 px-1 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                  <Clock className="h-3 w-3" /> Recent
                </div>
                <div className="mb-2 grid grid-cols-8 gap-1">
                  {recent.slice(0, 16).map((e) => (
                    <button
                      key={"r-" + e}
                      type="button"
                      onClick={() => handlePick(e)}
                      className="aspect-square rounded-md text-xl hover:bg-muted"
                    >
                      {e}
                    </button>
                  ))}
                </div>
              </>
            )}
            <div className="mb-1 px-1 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
              {cat.label}
            </div>
            <div className="grid grid-cols-8 gap-1">
              {cat.emojis.map((e) => (
                <button
                  key={e}
                  type="button"
                  onClick={() => handlePick(e)}
                  className="aspect-square rounded-md text-xl hover:bg-muted"
                >
                  {e}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Footer: frequent */}
      {!searching && (
        <div className="flex items-center gap-1 border-t border-border bg-muted/20 px-3 py-1.5">
          <span className="mr-1 text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
            Frequent
          </span>
          {frequent.slice(0, 7).map((e) => (
            <button
              key={"f-" + e}
              type="button"
              onClick={() => handlePick(e)}
              className="text-lg transition-transform hover:scale-125"
            >
              {e}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
