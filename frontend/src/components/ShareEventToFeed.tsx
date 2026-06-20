import { useState } from "react";
import { Globe, Users, Clock, Infinity, Loader2, CalendarIcon } from "lucide-react";
import SvgIcon from '@/components/ui/svg-icon';
import ShareIcon from '@/assets/icons/share-icon.svg';
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Calendar } from "@/components/ui/calendar";
import { Input } from "@/components/ui/input";
import { format } from "date-fns";
import { cn } from "@/lib/utils";
import { socialApi } from "@/lib/api/social";
import { toast } from "sonner";
import { useLanguage } from '@/lib/i18n/LanguageContext';

interface ShareEventToFeedProps {
  event: {
    id: string;
    title: string;
    start_date?: string;
    location?: string;
    cover_image?: string;
    description?: string;
  };
  trigger?: React.ReactNode;
}

const ShareEventToFeed = ({ event, trigger }: ShareEventToFeedProps) => {
  const { t } = useLanguage();
  const [open, setOpen] = useState(false);
  const [visibility, setVisibility] = useState<"public" | "circle">("public");
  const [duration, setDuration] = useState<"until" | "lifetime">("lifetime");
  const [untilDate, setUntilDate] = useState<Date | undefined>();
  const [untilTime, setUntilTime] = useState("23:59");
  const [caption, setCaption] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [untilDateOpen, setUntilDateOpen] = useState(false);

  const handleShare = async () => {
    setIsSubmitting(true);
    const tid = `share-event-${event.id}`;
    toast.loading('Sharing event to feed…', { id: tid });
    try {
      const formData = new FormData();
      const content = caption.trim()
        ? caption.trim()
        : `Check out my event: ${event.title}`;

      formData.append("content", content);
      formData.append("visibility", visibility);
      formData.append("post_type", "event_share");
      formData.append("event_id", event.id);

      if (duration === "until" && untilDate) {
        const expiresAt = new Date(untilDate);
        const [h, m] = untilTime.split(":");
        expiresAt.setHours(parseInt(h), parseInt(m));
        formData.append("expires_at", expiresAt.toISOString());
      }

      const response = await socialApi.createPost(formData);
      if (response.success) {
        toast.success("Event shared to feed!", { id: tid });
        setOpen(false);
        setCaption("");
      } else {
        toast.error(response.message || "Failed to share event", { id: tid });
      }
    } catch {
      toast.error("Failed to share event", { id: tid });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <>
      {trigger ? (
        <div onClick={() => setOpen(true)}>{trigger}</div>
      ) : (
        <Button variant="outline" size="sm" onClick={() => setOpen(true)} className="gap-2">
          <img src={ShareIcon} alt="" className="w-4 h-4 dark:invert opacity-70" />
          Share to Feed
        </Button>
      )}

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Share Event to Feed</DialogTitle>
            <DialogDescription>Share your event with the community</DialogDescription>
          </DialogHeader>

          <div className="space-y-5 py-2">
            {/* Event Preview Card */}
            <div className="rounded-xl border border-border overflow-hidden">
              {event.cover_image && (
                <img 
                  src={event.cover_image} 
                  alt={event.title}
                  className="w-full h-32 object-cover"
                />
              )}
              <div className="p-3">
                <h3 className="font-semibold text-sm text-foreground">{event.title}</h3>
                {event.start_date && (
                  <p className="text-xs text-muted-foreground mt-1">
                    {new Date(event.start_date).toLocaleDateString("en-US", {
                      weekday: "short",
                      month: "short",
                      day: "numeric",
                      year: "numeric",
                    })}
                  </p>
                )}
                {event.location && (
                  <p className="text-xs text-muted-foreground">{event.location}</p>
                )}
              </div>
            </div>

            {/* Caption */}
            <div className="space-y-2">
              <Label>Add a caption (optional)</Label>
              <Textarea
                placeholder="Say something about your event..."
                value={caption}
                onChange={(e) => setCaption(e.target.value)}
                rows={3}
                maxLength={500}
                className="resize-none"
              />
              <p className="text-xs text-muted-foreground text-right">{caption.length}/500</p>
            </div>

            {/* Visibility */}
            <div className="space-y-2">
              <Label>Who can see this?</Label>
              <Select value={visibility} onValueChange={(v: "public" | "circle") => setVisibility(v)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="public">
                    <span className="flex items-center gap-2">
                      <Globe className="w-4 h-4" /> Public — Everyone
                    </span>
                  </SelectItem>
                  <SelectItem value="circle">
                    <span className="flex items-center gap-2">
                      <Users className="w-4 h-4" /> Circle — Close friends
                    </span>
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>

            {/* Duration */}
            <div className="space-y-2">
              <Label>How long should it show?</Label>
              <Select value={duration} onValueChange={(v: "until" | "lifetime") => setDuration(v)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="lifetime">
                    <span className="flex items-center gap-2">
                      <Infinity className="w-4 h-4" /> Until I remove it
                    </span>
                  </SelectItem>
                  <SelectItem value="until">
                    <span className="flex items-center gap-2">
                      <Clock className="w-4 h-4" /> Until a specific date
                    </span>
                  </SelectItem>
                </SelectContent>
              </Select>

              {duration === "until" && (
                <div className="flex gap-2 mt-2">
                  <Popover open={untilDateOpen} onOpenChange={setUntilDateOpen}>
                    <PopoverTrigger asChild>
                      <Button
                        variant="outline"
                        className={cn(
                          "flex-1 justify-start text-left font-normal",
                          !untilDate && "text-muted-foreground"
                        )}
                      >
                        <CalendarIcon className="mr-2 h-4 w-4" />
                        {untilDate ? format(untilDate, "PPP") : "Pick date"}
                      </Button>
                    </PopoverTrigger>
                    <PopoverContent className="w-auto p-0" align="start">
                      <Calendar
                        mode="single"
                        selected={untilDate}
                        onSelect={d => { setUntilDate(d); setUntilDateOpen(false); }}
                        disabled={(date) => date < new Date()}
                        initialFocus
                        className="p-3 pointer-events-auto"
                      />
                    </PopoverContent>
                  </Popover>
                  <Input
                    type="time"
                    value={untilTime}
                    onChange={(e) => setUntilTime(e.target.value)}
                    className="w-28"
                  />
                </div>
              )}
            </div>
          </div>

          <div className="flex gap-3 pt-2">
            <Button variant="outline" className="flex-1" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button 
              className="flex-1" 
              onClick={handleShare} 
              disabled={isSubmitting || (duration === "until" && !untilDate)}
            >
              {isSubmitting ? (
                <><Loader2 className="w-4 h-4 mr-2 animate-spin" /> Sharing...</>
              ) : (
                <><img src={ShareIcon} alt="" className="w-4 h-4 mr-2 dark:invert" /> Share</>
              )}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
};

export default ShareEventToFeed;
