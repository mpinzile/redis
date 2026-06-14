import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { NuruEmojiPicker, type NuruEmojiPickerProps } from "./NuruEmojiPicker";
import { useState, type ReactNode } from "react";

interface Props extends Omit<NuruEmojiPickerProps, "onClose"> {
  children: ReactNode;
  align?: "start" | "center" | "end";
  side?: "top" | "right" | "bottom" | "left";
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
}

export function EmojiPickerPopover({
  children,
  align = "start",
  side = "top",
  open: openProp,
  onOpenChange,
  onSelect,
  reactionMode,
  className,
}: Props) {
  const [internalOpen, setInternalOpen] = useState(false);
  const open = openProp ?? internalOpen;
  const setOpen = onOpenChange ?? setInternalOpen;

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>{children}</PopoverTrigger>
      <PopoverContent
        align={align}
        side={side}
        className="w-auto border-0 bg-transparent p-0 shadow-none"
      >
        <NuruEmojiPicker
          reactionMode={reactionMode}
          className={className}
          onSelect={(e) => {
            onSelect(e);
            setOpen(false);
          }}
          onClose={() => setOpen(false)}
        />
      </PopoverContent>
    </Popover>
  );
}
