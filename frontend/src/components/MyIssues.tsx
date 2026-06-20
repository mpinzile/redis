import { useState, useEffect, useCallback, useRef } from "react";
import { useSearchParams } from "react-router-dom";
import { Loader2, Plus, ChevronLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { issuesApi, Issue, IssueCategory, IssueSummary } from "@/lib/api/issues";
import { uploadsApi } from "@/lib/api/uploads";
import { useWorkspaceMeta } from "@/hooks/useWorkspaceMeta";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import SvgIcon from '@/components/ui/svg-icon';
import closeIcon from "@/assets/icons/close-icon.svg";
import imageIcon from "@/assets/icons/image-icon.svg";
import chatIcon from "@/assets/icons/chat-icon.svg";
import issueIcon from "@/assets/icons/issue-icon.svg";
import { useLanguage } from '@/lib/i18n/LanguageContext';

// ── Staged file type (not yet uploaded) ──
interface StagedFile {
  file: File;
  previewUrl: string;
}

const statusConfig: Record<string, { label: string; color: string; emoji: string }> = {
  open: { label: "Open", color: "bg-blue-500/10 text-blue-600 border-blue-500/20", emoji: "🔵" },
  in_progress: { label: "In Progress", color: "bg-amber-500/10 text-amber-600 border-amber-500/20", emoji: "🟡" },
  resolved: { label: "Resolved", color: "bg-green-500/10 text-green-600 border-green-500/20", emoji: "🟢" },
  closed: { label: "Closed", color: "bg-muted text-muted-foreground border-border", emoji: "⚫" },
};

const priorityConfig: Record<string, { label: string; color: string }> = {
  low: { label: "Low", color: "bg-muted text-muted-foreground" },
  medium: { label: "Medium", color: "bg-blue-500/10 text-blue-600" },
  high: { label: "High", color: "bg-orange-500/10 text-orange-600" },
  critical: { label: "Critical", color: "bg-red-500/10 text-red-600" },
};

export default function MyIssues() {
  const [searchParams] = useSearchParams();
  useWorkspaceMeta({ title: "Report Issue", description: "Submit and track issues" });

  const { t } = useLanguage();
  const [issues, setIssues] = useState<Issue[]>([]);
  const [summary, setSummary] = useState<IssueSummary>({ total: 0, open: 0, in_progress: 0, resolved: 0 });
  const [categories, setCategories] = useState<IssueCategory[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedIssue, setSelectedIssue] = useState<Issue | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [showSubmit, setShowSubmit] = useState(false);
  const [filterStatus, setFilterStatus] = useState<string>("all");
  const [replyText, setReplyText] = useState("");
  const [replying, setReplying] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  // Form state
  const [form, setForm] = useState({
    category_id: "",
    subject: "",
    description: "",
    priority: "medium",
    screenshot_urls: [] as string[],
  });

  // Staged files (selected but not yet uploaded)
  const [stagedFiles, setStagedFiles] = useState<StagedFile[]>([]);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const loadIssues = useCallback(async () => {
    setLoading(true);
    try {
      const params: any = {};
      if (filterStatus !== "all") params.status = filterStatus;
      const res = await issuesApi.getMyIssues(params);
      if (res.success && res.data) {
        // standard_response wraps paginated data as { items: {...}, pagination }
        const payload = res.data.items || res.data;
        setIssues(payload.issues || []);
        setSummary(payload.summary || { total: 0, open: 0, in_progress: 0, resolved: 0 });
      } else {
        toast.error(res.message || "Failed to load issues");
      }
    } catch (err) {
      console.error("Failed to load issues:", err);
    }
    setLoading(false);
  }, [filterStatus]);

  const loadCategories = useCallback(async () => {
    try {
      const res = await issuesApi.getCategories();
      if (res.success && res.data) {
        setCategories(Array.isArray(res.data) ? res.data : []);
      }
    } catch (err) {
      console.error("Failed to load categories:", err);
    }
  }, []);

  useEffect(() => { loadIssues(); }, [loadIssues]);
  useEffect(() => { loadCategories(); }, [loadCategories]);

  // Auto-open issue from URL param (e.g. from notification click)
  const autoOpenHandled = useRef(false);
  useEffect(() => {
    const issueId = searchParams.get("issue");
    if (issueId && !autoOpenHandled.current) {
      autoOpenHandled.current = true;
      openIssueDetail(issueId);
    }
  }, [searchParams]);

  const openIssueDetail = async (issueId: string) => {
    setDetailLoading(true);
    setSelectedIssue(null);
    const res = await issuesApi.getIssue(issueId);
    if (res.success && res.data) {
      setSelectedIssue(res.data);
    } else {
      toast.error("Failed to load issue details");
    }
    setDetailLoading(false);
  };

  // ── Staged file handling ──
  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (!file.type.startsWith("image/")) { toast.error("Only images are allowed"); return; }
    if (file.size > 5 * 1024 * 1024) { toast.error("Max 5MB per screenshot"); return; }
    const totalCount = form.screenshot_urls.length + stagedFiles.length;
    if (totalCount >= 3) { toast.error("Max 3 screenshots"); return; }
    
    const previewUrl = URL.createObjectURL(file);
    setStagedFiles(prev => [...prev, { file, previewUrl }]);
    e.target.value = "";
  };

  const removeStagedFile = (index: number) => {
    setStagedFiles(prev => {
      const removed = prev[index];
      URL.revokeObjectURL(removed.previewUrl);
      return prev.filter((_, i) => i !== index);
    });
  };

  const removeUploadedScreenshot = (index: number) => {
    setForm(prev => ({ ...prev, screenshot_urls: prev.screenshot_urls.filter((_, i) => i !== index) }));
  };

  // Upload staged files then submit
  const handleSubmit = async () => {
    if (!form.category_id) { toast.error("Select a category"); return; }
    if (!form.subject.trim()) { toast.error("Subject is required"); return; }
    if (!form.description.trim()) { toast.error("Description is required"); return; }
    setSubmitting(true);
    const tid = 'submit-issue';
    toast.loading('Submitting your issue…', { id: tid });

    try {
      // Upload staged files first
      const uploadedUrls = [...form.screenshot_urls];
      for (const staged of stagedFiles) {
        const res = await uploadsApi.upload(staged.file);
        if (res.success && res.data?.url) {
          uploadedUrls.push(res.data.url);
        } else {
          toast.error("Failed to upload screenshot", { id: tid });
          setSubmitting(false);
          return;
        }
      }

      const res = await issuesApi.createIssue({
        ...form,
        screenshot_urls: uploadedUrls.length > 0 ? uploadedUrls : undefined,
      });

      if (res.success) {
        toast.success("Issue submitted successfully", { id: tid });
        setShowSubmit(false);
        setForm({ category_id: "", subject: "", description: "", priority: "medium", screenshot_urls: [] });
        stagedFiles.forEach(s => URL.revokeObjectURL(s.previewUrl));
        setStagedFiles([]);
        loadIssues();
      } else {
        toast.error(res.message || "Failed to submit issue", { id: tid });
      }
    } catch {
      toast.error("Failed to submit issue", { id: tid });
    }
    setSubmitting(false);
  };

  const handleReply = async () => {
    if (!selectedIssue || !replyText.trim()) return;
    setReplying(true);
    const tid = `reply-${selectedIssue.id}`;
    toast.loading('Sending reply…', { id: tid });
    const res = await issuesApi.replyToIssue(selectedIssue.id, { message: replyText.trim() });
    if (res.success) {
      toast.success("Reply sent", { id: tid });
      setReplyText("");
      openIssueDetail(selectedIssue.id);
      loadIssues();
    } else {
      toast.error(res.message || "Failed to send reply", { id: tid });
    }
    setReplying(false);
  };

  const handleCloseIssue = async () => {
    if (!selectedIssue) return;
    const tid = `close-${selectedIssue.id}`;
    toast.loading('Closing issue…', { id: tid });
    const res = await issuesApi.closeIssue(selectedIssue.id);
    if (res.success) {
      toast.success("Issue closed", { id: tid });
      setSelectedIssue(null);
      loadIssues();
    } else {
      toast.error(res.message || "Failed to close issue", { id: tid });
    }
  };

  const formatDate = (d: string) => {
    const date = new Date(d);
    return date.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
  };

  const formatTime = (d: string) => {
    const date = new Date(d);
    return date.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
  };

  // ── ISSUE DETAIL VIEW ──
  if (detailLoading) {
    return (
      <div className="space-y-4">
        <div className="flex justify-end">
          <Skeleton className="h-8 w-16" />
        </div>
        <Card>
          <CardContent className="p-5 space-y-4">
            <Skeleton className="h-6 w-2/3" />
            <div className="flex gap-2">
              <Skeleton className="h-5 w-16" />
              <Skeleton className="h-5 w-16" />
              <Skeleton className="h-5 w-24" />
            </div>
            <Skeleton className="h-4 w-1/3" />
            <Skeleton className="h-24 w-full rounded-lg" />
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-5 space-y-3">
            <Skeleton className="h-5 w-32" />
            <Skeleton className="h-16 w-full" />
          </CardContent>
        </Card>
      </div>
    );
  }

  if (selectedIssue) {
    const st = statusConfig[selectedIssue.status] || statusConfig.open;
    const pr = priorityConfig[selectedIssue.priority] || priorityConfig.medium;
    return (
      <div className="space-y-4">
        <div className="flex justify-end">
          <Button variant="ghost" size="icon" onClick={() => setSelectedIssue(null)}>
            <ChevronLeft className="w-5 h-5" />
          </Button>
        </div>

        <Card>
          <CardContent className="p-5 space-y-4">
            <div className="flex items-start justify-between gap-3">
              <div className="flex-1 min-w-0">
                <h2 className="text-lg font-bold text-foreground">{selectedIssue.subject}</h2>
                <div className="flex flex-wrap items-center gap-2 mt-2">
                  <Badge variant="outline" className={cn("text-xs", st.color)}>
                    <span className="mr-1">{st.emoji}</span>{st.label}
                  </Badge>
                  <Badge variant="outline" className={cn("text-xs", pr.color)}>{pr.label}</Badge>
                  {selectedIssue.category && (
                    <Badge variant="outline" className="text-xs">{selectedIssue.category.name}</Badge>
                  )}
                </div>
              </div>
              {selectedIssue.status !== "closed" && (
                <Button variant="outline" size="sm" onClick={handleCloseIssue} className="text-muted-foreground shrink-0">
                  Close Issue
                </Button>
              )}
            </div>

            <div className="text-sm text-muted-foreground">
              Submitted {formatDate(selectedIssue.created_at)} at {formatTime(selectedIssue.created_at)}
            </div>

            <div className="bg-muted/40 rounded-lg p-4">
              <p className="text-sm whitespace-pre-wrap">{selectedIssue.description}</p>
            </div>

            {(selectedIssue.screenshot_urls || []).length > 0 && (
              <div className="flex flex-wrap gap-2">
                {selectedIssue.screenshot_urls.map((url, i) => (
                  <a key={i} href={url} target="_blank" rel="noreferrer">
                    <img src={url} alt={`Screenshot ${i + 1}`} className="w-24 h-24 object-cover rounded-lg border border-border hover:opacity-80 transition" />
                  </a>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Responses */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base flex items-center gap-2">
              <img src={chatIcon} alt="" className="w-4 h-4 dark:invert" />
              Responses ({(selectedIssue.responses || []).length})
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {(selectedIssue.responses || []).length === 0 ? (
              <p className="text-sm text-muted-foreground text-center py-6">No responses yet. Our team will review your issue soon.</p>
            ) : (
              (selectedIssue.responses || []).map((r) => (
                <div key={r.id} className={cn("rounded-lg p-3 text-sm", r.is_admin ? "bg-primary/5 border border-primary/10" : "bg-muted/40")}>
                  <div className="flex items-center gap-2 mb-1.5">
                    <span className="font-medium text-xs">{r.is_admin ? (r.admin_name || "Support Team") : "You"}</span>
                    {r.is_admin && <Badge variant="outline" className="text-[10px] h-4 bg-primary/10 text-primary border-primary/20">Staff</Badge>}
                    <span className="text-xs text-muted-foreground ml-auto">{formatDate(r.created_at)} {formatTime(r.created_at)}</span>
                  </div>
                  <p className="whitespace-pre-wrap">{r.message}</p>
                </div>
              ))
            )}

            {selectedIssue.status !== "closed" && (
              <div className="flex gap-2 pt-2 border-t border-border">
                <Textarea
                  value={replyText}
                  onChange={(e) => setReplyText(e.target.value)}
                  placeholder={t('type_reply')}
                  rows={2}
                  className="flex-1 resize-none text-sm"
                  maxLength={5000}
                  autoComplete="off"
                />
                <Button size="sm" onClick={handleReply} disabled={replying || !replyText.trim()} className="self-end">
                  {replying ? <Loader2 className="w-4 h-4 animate-spin" /> : t("send")}
                </Button>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    );
  }

  // ── MAIN LIST VIEW ──
  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2.5 min-w-0 flex-1">
          <img src={issueIcon} alt="" className="w-6 h-6 dark:invert flex-shrink-0" />
          <div className="min-w-0">
            <h1 className="text-lg sm:text-2xl font-bold truncate">{t('report_issue')}</h1>
            <p className="text-xs sm:text-sm text-muted-foreground mt-0.5 truncate">{t('submit_issues_track')}</p>
          </div>
        </div>
        <Button onClick={() => setShowSubmit(true)} size="sm" className="flex-shrink-0">
          <Plus className="w-4 h-4 mr-1.5" />
          <span className="hidden sm:inline">{t('new_issue')}</span>
          <span className="sm:hidden">New</span>
        </Button>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {[
          { label: t("total"), value: summary.total, color: "text-foreground" },
          { label: t("open"), value: summary.open, color: "text-blue-600" },
          { label: t("in_progress"), value: summary.in_progress, color: "text-amber-600" },
          { label: t("resolved"), value: summary.resolved, color: "text-green-600" },
        ].map((s) => (
          <Card key={s.label}>
            <CardContent className="p-4 text-center">
              <p className={cn("text-2xl font-bold", s.color)}>{s.value}</p>
              <p className="text-xs text-muted-foreground mt-0.5">{s.label}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Filters */}
      <div className="flex items-center gap-2 overflow-x-auto">
        {["all", "open", "in_progress", "resolved", "closed"].map((s) => (
          <Button
            key={s}
            variant={filterStatus === s ? "default" : "outline"}
            size="sm"
            onClick={() => setFilterStatus(s)}
            className="shrink-0"
          >
            {s === "all" ? t("all") : s === "in_progress" ? t("in_progress") : t(s)}
          </Button>
        ))}
      </div>

      {/* Issue List */}
      {loading ? (
        <div className="space-y-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="bg-card border border-border rounded-xl p-4 space-y-2">
              <Skeleton className="h-4 w-1/3" />
              <Skeleton className="h-3 w-2/3" />
              <Skeleton className="h-3 w-1/4" />
            </div>
          ))}
        </div>
      ) : issues.length === 0 ? (
        <Card>
          <CardContent className="p-12 text-center">
            <img src={issueIcon} alt="" className="w-10 h-10 mx-auto mb-3 opacity-30 dark:invert" />
            <p className="text-muted-foreground">{t('no_issues_yet')}</p>
            <Button variant="outline" size="sm" className="mt-3" onClick={() => setShowSubmit(true)}>
              {t('submit_first_issue')}
            </Button>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-2">
          {issues.map((issue) => {
            const st = statusConfig[issue.status] || statusConfig.open;
            const pr = priorityConfig[issue.priority] || priorityConfig.medium;
            return (
              <Card
                key={issue.id}
                className="cursor-pointer hover:shadow-sm transition-shadow"
                onClick={() => openIssueDetail(issue.id)}
              >
                <CardContent className="p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex-1 min-w-0">
                      <p className="font-medium text-sm text-foreground line-clamp-1">{issue.subject}</p>
                      <p className="text-xs text-muted-foreground mt-0.5 line-clamp-1">{issue.description}</p>
                      <div className="flex flex-wrap items-center gap-1.5 mt-2">
                        <Badge variant="outline" className={cn("text-[10px] h-5", st.color)}>
                          <span className="mr-0.5">{st.emoji}</span>{st.label}
                        </Badge>
                        <Badge variant="outline" className={cn("text-[10px] h-5", pr.color)}>{pr.label}</Badge>
                        {issue.category && (
                          <span className="text-[10px] text-muted-foreground">• {issue.category.name}</span>
                        )}
                      </div>
                    </div>
                    <div className="text-right shrink-0">
                      <p className="text-[10px] text-muted-foreground">{formatDate(issue.created_at)}</p>
                      {issue.response_count > 0 && (
                        <div className="flex items-center gap-1 mt-1 justify-end">
                          <img src={chatIcon} alt="" className="w-3 h-3 dark:invert" />
                          <span className="text-[10px] text-muted-foreground">{issue.response_count}</span>
                          {issue.last_response_is_admin && (
                            <Badge className="text-[9px] h-3.5 bg-primary/10 text-primary border-0">New</Badge>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}




      {/* Submit Issue Dialog */}
      <Dialog open={showSubmit} onOpenChange={(open) => {
        setShowSubmit(open);
        if (!open) {
          stagedFiles.forEach(s => URL.revokeObjectURL(s.previewUrl));
          setStagedFiles([]);
        }
      }}>
        <DialogContent className="max-w-lg max-h-[85vh] flex flex-col">
          <DialogHeader>
            <DialogTitle>{t('submit_issue')}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 overflow-y-auto flex-1">
            <div className="space-y-1.5">
              <Label>{t('category')} *</Label>
              <Select value={form.category_id} onValueChange={(v) => setForm({ ...form, category_id: v })}>
                <SelectTrigger>
                  <SelectValue placeholder={t('select_issue_category')} />
                </SelectTrigger>
                <SelectContent>
                  {categories.map((cat) => (
                    <SelectItem key={cat.id} value={cat.id}>
                      <span>{cat.name}</span>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1.5">
              <Label>{t('subject')} *</Label>
              <Input
                value={form.subject}
                onChange={(e) => setForm({ ...form, subject: e.target.value })}
                placeholder={t('brief_summary_issue')}
                maxLength={200}
                autoComplete="off"
              />
            </div>

            <div className="space-y-1.5">
              <Label>{t('description')} *</Label>
              <Textarea
                value={form.description}
                onChange={(e) => setForm({ ...form, description: e.target.value })}
                placeholder={t('describe_issue_detail')}
                rows={5}
                className="resize-none"
                maxLength={5000}
                autoComplete="off"
              />
            </div>

            <div className="space-y-1.5">
              <Label>{t('priority')}</Label>
              <Select value={form.priority} onValueChange={(v) => setForm({ ...form, priority: v })}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="low">Low</SelectItem>
                  <SelectItem value="medium">Medium</SelectItem>
                  <SelectItem value="high">High</SelectItem>
                  <SelectItem value="critical">Critical</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {/* Screenshot upload — staged approach */}
            <div className="space-y-2">
              <Label>Screenshots (max 3)</Label>

              {/* Already uploaded + staged previews */}
              {(form.screenshot_urls.length > 0 || stagedFiles.length > 0) && (
                <div className="flex flex-wrap gap-3">
                  {form.screenshot_urls.map((url, i) => (
                    <div key={`uploaded-${i}`} className="relative group w-20 h-20 rounded-lg overflow-hidden border border-border">
                      <img src={url} alt="" className="w-full h-full object-cover" />
                      <button
                        type="button"
                        className="absolute top-0.5 right-0.5 w-5 h-5 bg-destructive rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
                        onClick={() => removeUploadedScreenshot(i)}
                      >
                        <img src={closeIcon} alt="" className="w-3 h-3 invert" />
                      </button>
                      <div className="absolute bottom-0 inset-x-0 bg-green-600/80 text-white text-[8px] text-center py-0.5">Uploaded</div>
                    </div>
                  ))}
                  {stagedFiles.map((staged, i) => (
                    <div key={`staged-${i}`} className="relative group w-20 h-20 rounded-lg overflow-hidden border-2 border-dashed border-primary/30">
                      <img src={staged.previewUrl} alt="" className="w-full h-full object-cover" />
                      <button
                        type="button"
                        className="absolute top-0.5 right-0.5 w-5 h-5 bg-destructive rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
                        onClick={() => removeStagedFile(i)}
                      >
                        <img src={closeIcon} alt="" className="w-3 h-3 invert" />
                      </button>
                      <div className="absolute bottom-0 inset-x-0 bg-primary/80 text-primary-foreground text-[8px] text-center py-0.5">Ready</div>
                    </div>
                  ))}
                </div>
              )}

              {/* Add button */}
              {(form.screenshot_urls.length + stagedFiles.length) < 3 && (
                <button
                  type="button"
                  onClick={() => fileInputRef.current?.click()}
                  className="w-full border-2 border-dashed border-border rounded-lg p-4 flex flex-col items-center gap-1.5 hover:bg-muted/40 transition cursor-pointer"
                >
                  <img src={imageIcon} alt="" className="w-6 h-6 dark:invert opacity-50" />
                  <span className="text-xs text-muted-foreground">Tap to add screenshot</span>
                  <span className="text-[10px] text-muted-foreground/60">PNG, JPG up to 5MB</span>
                </button>
              )}

              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={handleFileSelect}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowSubmit(false)}>Cancel</Button>
            <Button onClick={handleSubmit} disabled={submitting}>
              {submitting ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}
              Submit Issue
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
