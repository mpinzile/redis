import { useEffect, useState, useCallback } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { ChevronLeft, RotateCcw, Trash2, Loader2, Eye, Video, Image } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { adminApi } from "@/lib/api/admin";
import { useAdminMeta } from "@/hooks/useAdminMeta";
import { useConfirmDialog } from "@/hooks/useConfirmDialog";
import { usePromptDialog } from "@/hooks/usePromptDialog";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { getTimeAgo } from "@/utils/getTimeAgo";

export default function AdminMomentDetail() {
  useAdminMeta("Moment Detail");
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { confirm, ConfirmDialog } = useConfirmDialog();
  const { prompt, PromptDialog } = usePromptDialog();
  const [moment, setMoment] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [deletingEcho, setDeletingEcho] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!id) return;
    const res = await adminApi.getMomentDetail(id);
    if (res.success) setMoment(res.data);
    else toast.error("Failed to load moment");
    setLoading(false);
  }, [id]);

  useEffect(() => { load(); }, [load]);

  const handleRemove = async () => {
    if (!moment) return;
    const reason = await prompt({
      title: "Remove this moment?",
      description: "Share the reason for removing it. The user will see this message with the takedown notice.",
      placeholder: "e.g. Contains content that breaks our community guidelines",
      confirmLabel: "Remove moment",
    });
    if (reason === null) return;
    const res = await adminApi.updateMomentStatus(moment.id, false, reason.trim() || "Policy violation");
    if (res.success) { toast.success("Moment removed"); load(); }
    else toast.error(res.message || "Failed");
  };

  const handleRestore = async () => {
    if (!moment) return;
    const ok = await confirm({ title: "Restore Moment?", description: "Restore this moment for users to see?", confirmLabel: "Restore" });
    if (!ok) return;
    const res = await adminApi.updateMomentStatus(moment.id, true);
    if (res.success) { toast.success("Moment restored"); load(); }
    else toast.error(res.message || "Failed");
  };

  const handleDeleteEcho = async (echoId: string, content: string) => {
    const ok = await confirm({ title: "Delete Echo?", description: `Delete: "${content?.slice(0, 60)}"?`, confirmLabel: "Delete", destructive: true });
    if (!ok) return;
    setDeletingEcho(echoId);
    const res = await adminApi.deleteMomentEcho(id!, echoId);
    if (res.success) { toast.success("Echo deleted"); load(); }
    else toast.error(res.message || "Failed");
    setDeletingEcho(null);
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-8 w-40" />
        <Skeleton className="h-80 w-full rounded-xl" />
      </div>
    );
  }

  if (!moment) {
    return (
      <div className="text-center py-20 text-muted-foreground">
        <p>Moment not found.</p>
        <Button variant="outline" className="mt-4" onClick={() => navigate("/admin/moments")}>Back to Moments</Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <ConfirmDialog />
      <PromptDialog />

      <div className="flex items-center gap-3">
        <Button variant="ghost" size="sm" onClick={() => navigate("/admin/moments")}>
          <ChevronLeft className="w-4 h-4 mr-1" /> Moments
        </Button>
        <div className="flex-1" />
        {moment.is_active ? (
          <Button variant="destructive" size="sm" onClick={handleRemove}>Remove Moment</Button>
        ) : (
          <Button variant="outline" size="sm" onClick={handleRestore}>
            <RotateCcw className="w-3.5 h-3.5 mr-1.5" /> Restore Moment
          </Button>
        )}
      </div>

      {/* Moment preview */}
      <div className={cn("bg-card border border-border rounded-xl overflow-hidden", !moment.is_active && "border-destructive/40")}>
        {!moment.is_active && (
          <div className="bg-destructive/10 text-destructive text-xs px-4 py-2 font-medium">
            ⚠ This moment has been removed.
          </div>
        )}
        {/* Media */}
        <div className="relative bg-black aspect-[9/16] max-h-96 flex items-center justify-center">
          {moment.content_type === "video" ? (
            <video src={moment.media_url} controls className="max-h-full max-w-full" />
          ) : moment.media_url ? (
            <img src={moment.media_url} alt="moment" className="max-h-full max-w-full object-contain" />
          ) : (
            <div className="text-muted-foreground flex flex-col items-center gap-2">
              {moment.content_type === "video" ? <Video className="w-8 h-8" /> : <Image className="w-8 h-8" />}
              <span className="text-sm">No media</span>
            </div>
          )}
          {/* User overlay */}
          <div className="absolute top-4 left-4 flex items-center gap-2">
            <div className="w-8 h-8 rounded-full bg-white/20 backdrop-blur overflow-hidden">
              {moment.user?.avatar ? (
                <img src={moment.user.avatar} className="w-full h-full object-cover" alt="" />
              ) : (
                <div className="w-full h-full flex items-center justify-center text-white text-xs font-bold">
                  {moment.user?.name?.[0]}
                </div>
              )}
            </div>
            <div>
              <p className="text-white text-sm font-medium drop-shadow">{moment.user?.name}</p>
              <p className="text-white/70 text-xs drop-shadow">@{moment.user?.username}</p>
            </div>
          </div>
        </div>

        <div className="p-4 space-y-3">
          {moment.caption && <p className="text-foreground">{moment.caption}</p>}
          <div className="flex items-center gap-4 text-sm text-muted-foreground">
            <span className="flex items-center gap-1"><Eye className="w-4 h-4" /> {moment.view_count ?? 0} views</span>
            <span className="capitalize px-2 py-0.5 bg-muted rounded-full text-xs">{moment.privacy}</span>
            <span className="capitalize px-2 py-0.5 bg-muted rounded-full text-xs">{moment.content_type}</span>
            <span className="ml-auto text-xs">{moment.created_at ? getTimeAgo(moment.created_at) : ""}</span>
          </div>
        </div>
      </div>

      {/* Echoes */}
      <div>
        <h3 className="text-base font-semibold text-foreground mb-3">Echoes / Replies ({(moment.echoes || []).length})</h3>
        {(moment.echoes || []).length === 0 ? (
          <p className="text-muted-foreground text-sm text-center py-6">No echoes on this moment</p>
        ) : (
          <div className="space-y-2">
            {(moment.echoes || []).map((echo: any) => (
              <div key={echo.id} className="bg-card border border-border rounded-xl p-4 flex items-start gap-3">
                <div className="w-8 h-8 rounded-full bg-muted shrink-0 overflow-hidden">
                  {echo.user?.avatar ? <img src={echo.user.avatar} className="w-full h-full object-cover" alt="" /> : (
                    <div className="w-full h-full flex items-center justify-center text-xs font-bold text-muted-foreground">{echo.user?.name?.[0]}</div>
                  )}
                </div>
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <span className="font-medium text-sm text-foreground">{echo.user?.name}</span>
                    <span className="text-xs text-muted-foreground">{echo.created_at ? getTimeAgo(echo.created_at) : ""}</span>
                  </div>
                  <p className="text-sm text-muted-foreground mt-0.5">{echo.content}</p>
                </div>
                <Button
                  variant="ghost" size="sm"
                  className="text-destructive hover:bg-destructive/10 shrink-0"
                  disabled={deletingEcho === echo.id}
                  onClick={() => handleDeleteEcho(echo.id, echo.content)}
                >
                  {deletingEcho === echo.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Trash2 className="w-3.5 h-3.5" />}
                </Button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
