import { useState, useMemo, useRef, useEffect } from 'react';
import {
  Plus, Search, MoreVertical, Edit, Trash, Loader2, ChevronRight, ChevronLeft,
  DollarSign, CheckCircle2, Clock, AlertCircle,
  BarChart3, FileText
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { FormattedNumberInput } from '@/components/ui/formatted-number-input';
import { Skeleton } from '@/components/ui/skeleton';
import DeleteOverlay from '@/components/ui/DeleteOverlay';
import { cn } from '@/lib/utils';
import { usePolling } from '@/hooks/usePolling';
import { useDeleteTracker } from '@/hooks/useDeleteTracker';
import { toast } from 'sonner';
import { useConfirmDialog } from '@/hooks/useConfirmDialog';
import { showCaughtError } from '@/lib/api';
import { useCurrency } from '@/hooks/useCurrency';
import { useEventBudget } from '@/data/useEvents';
import { generateBudgetReportHtml } from '@/utils/generateBudgetItemsReport';
import ReportPreviewDialog from '@/components/ReportPreviewDialog';
import BudgetAssistant from '@/components/BudgetAssistant';
import type { BudgetAssistantItem } from '@/components/BudgetAssistant';
import type { EventPermissions } from '@/hooks/useEventPermissions';
import type { EventBudgetItem } from '@/lib/api/types';
import writeXlsxFile from 'write-excel-file';
import ServiceProviderSearch from '@/components/events/ServiceProviderSearch';
import SvgIcon from '@/components/ui/svg-icon';
import PackageIcon from '@/assets/icons/package-icon.svg';
import { useLanguage } from '@/lib/i18n/LanguageContext';

// Module-level import state so it survives unmount/remount
let _importProgress: { current: number; total: number } | null = null;
let _importAbort = false;
const _importListeners = new Set<(p: { current: number; total: number } | null) => void>();
const _broadcastImport = (p: { current: number; total: number } | null) => {
  _importProgress = p;
  _importListeners.forEach(fn => fn(p));
};

interface EventBudgetProps {
  eventId: string;
  eventTitle?: string;
  eventBudget?: number;
  eventType?: string;
  eventTypeName?: string;
  eventLocation?: string;
  expectedGuests?: string;
  permissions?: EventPermissions;
}

const BUDGET_CATEGORIES = [
  'Venue', 'Catering', 'Decorations', 'Entertainment', 'Photography',
  'Transport', 'Printing', 'Gifts & Favors', 'Equipment Rental',
  'Marketing', 'Staffing', 'Audio & Visual', 'Flowers', 'Invitations',
  'Security', 'Miscellaneous'
];

const STATUS_OPTIONS = [
  { value: 'pending', label: 'Pending', color: 'bg-amber-500', textColor: 'text-amber-700', bgColor: 'bg-amber-50' },
  { value: 'deposit_paid', label: 'Deposit Paid', color: 'bg-blue-500', textColor: 'text-blue-700', bgColor: 'bg-blue-50' },
  { value: 'paid', label: 'Paid', color: 'bg-green-500', textColor: 'text-green-700', bgColor: 'bg-green-50' },
];

const ITEMS_PER_PAGE = 10;

const getStatusStyle = (status: string) => STATUS_OPTIONS.find(s => s.value === status) || STATUS_OPTIONS[0];

const EventBudget = ({ eventId, eventTitle, eventBudget, eventType, eventTypeName, eventLocation, expectedGuests, permissions }: EventBudgetProps) => {
  const canManage = permissions?.can_manage_budget || permissions?.is_creator;
  const canView = permissions?.can_view_budget || permissions?.can_manage_budget || permissions?.is_creator;
  const { currency, format: formatPrice } = useCurrency();

  const { items, summary, loading, refetch, addItem, updateItem, deleteItem } = useEventBudget(eventId);
  const { trackDelete, isDeleting } = useDeleteTracker();

  const [dialogOpen, setDialogOpen] = useState(false);
  const [reportOpen, setReportOpen] = useState(false);
  const [aiAssistantOpen, setAiAssistantOpen] = useState(false);

  // Module-level import state - survives navigation
  const [importProgress, setImportProgress] = useState<{ current: number; total: number } | null>(_importProgress);

  useEffect(() => {
    const handler = (p: { current: number; total: number } | null) => setImportProgress(p);
    _importListeners.add(handler);
    setImportProgress(_importProgress);
    return () => { _importListeners.delete(handler); };
  }, []);

  // Stop polling when dialogs are open
  usePolling(refetch, 30000, !dialogOpen && !reportOpen && !aiAssistantOpen);

  const [search, setSearch] = useState('');
  const [categoryFilter, setCategoryFilter] = useState<string>('all');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [editingItem, setEditingItem] = useState<EventBudgetItem | null>(null);
  const [saving, setSaving] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const [customCategoryMode, setCustomCategoryMode] = useState(false);
  const [customCategory, setCustomCategory] = useState('');

  // Form state
  const [formCategory, setFormCategory] = useState('');
  const [formItemName, setFormItemName] = useState('');
  const [formEstimatedCost, setFormEstimatedCost] = useState('');
  const [formActualCost, setFormActualCost] = useState('');
  const [formVendorName, setFormVendorName] = useState('');
  const [formStatus, setFormStatus] = useState<'pending' | 'deposit_paid' | 'paid'>('pending');
  const [formNotes, setFormNotes] = useState('');

  const { ConfirmDialog, confirm } = useConfirmDialog();

  // Filtered items
  const filtered = useMemo(() => {
    let result = [...items];
    if (search) {
      const q = search.toLowerCase();
      result = result.filter(i =>
        i.item_name.toLowerCase().includes(q) ||
        i.category.toLowerCase().includes(q) ||
        (i.vendor_name || '').toLowerCase().includes(q)
      );
    }
    if (categoryFilter !== 'all') result = result.filter(i => i.category === categoryFilter);
    if (statusFilter !== 'all') result = result.filter(i => i.status === statusFilter);
    return result;
  }, [items, search, categoryFilter, statusFilter]);

  // Pagination
  const totalPages = Math.ceil(filtered.length / ITEMS_PER_PAGE);
  const paginated = filtered.slice((currentPage - 1) * ITEMS_PER_PAGE, currentPage * ITEMS_PER_PAGE);

  // Reset page when filters change
  useEffect(() => { setCurrentPage(1); }, [search, categoryFilter, statusFilter]);

  // Category breakdown
  const categoryBreakdown = useMemo(() => {
    const map = new Map<string, { estimated: number; actual: number; effective: number; count: number }>();
    items.forEach(i => {
      const existing = map.get(i.category) || { estimated: 0, actual: 0, effective: 0, count: 0 };
      existing.estimated += i.estimated_cost || 0;
      existing.actual += i.actual_cost || 0;
      existing.effective += (i.actual_cost && i.actual_cost > 0) ? i.actual_cost : (i.estimated_cost || 0);
      existing.count += 1;
      map.set(i.category, existing);
    });
    return Array.from(map.entries()).map(([category, data]) => ({ category, ...data })).sort((a, b) => a.category.localeCompare(b.category));
  }, [items]);

  // Effective cost per item: actual if > 0, else estimate
  const getEffectiveCost = (item: EventBudgetItem) =>
    (item.actual_cost && item.actual_cost > 0) ? item.actual_cost : (item.estimated_cost || 0);
  const isItemEstimate = (item: EventBudgetItem) =>
    !(item.actual_cost && item.actual_cost > 0) && (item.estimated_cost || 0) > 0;

  // Summary computed
  const totalEstimated = items.reduce((s, i) => s + (i.estimated_cost || 0), 0);
  const totalActual = items.reduce((s, i) => s + (i.actual_cost || 0), 0);
  const overallBudget = items.reduce((s, i) => s + getEffectiveCost(i), 0);
  const includesEstimates = items.some(i => isItemEstimate(i));
  const pendingItems = items.filter(i => i.status === 'pending').length;

  const resetForm = () => {
    setFormCategory('');
    setFormItemName('');
    setFormEstimatedCost('');
    setFormActualCost('');
    setFormVendorName('');
    setFormStatus('pending');
    setFormNotes('');
    setEditingItem(null);
    setCustomCategoryMode(false);
    setCustomCategory('');
  };

  const openAdd = () => {
    resetForm();
    setDialogOpen(true);
  };

  const openEdit = (item: EventBudgetItem) => {
    setEditingItem(item);
    // Match category case-insensitively to BUDGET_CATEGORIES list
    const matchedCategory = BUDGET_CATEGORIES.find(
      c => c.toLowerCase() === (item.category || '').toLowerCase()
    ) || item.category || '';
    setFormCategory(matchedCategory);
    setFormItemName(item.item_name);
    setFormEstimatedCost(item.estimated_cost ? String(item.estimated_cost) : '');
    setFormActualCost(item.actual_cost ? String(item.actual_cost) : '');
    setFormVendorName(item.vendor_name || '');
    setFormStatus(item.status);
    setFormNotes(item.notes || '');
    setDialogOpen(true);
  };

  const handleSave = async () => {
    if (!formCategory || !formItemName) {
      toast.error('Category and item name are required');
      return;
    }
    setSaving(true);
    try {
      const data = {
        category: formCategory,
        item_name: formItemName,
        estimated_cost: formEstimatedCost ? parseFloat(formEstimatedCost) : null,
        actual_cost: formActualCost ? parseFloat(formActualCost) : null,
        vendor_name: formVendorName || null,
        status: formStatus as 'pending' | 'deposit_paid' | 'paid',
        notes: formNotes || null,
      };
      if (editingItem) {
        await updateItem(editingItem.id, data);
        toast.success('Budget item updated');
      } else {
        await addItem(data);
        toast.success('Budget item added');
      }
      setDialogOpen(false);
      resetForm();
    } catch (err) {
      showCaughtError(err);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (item: EventBudgetItem) => {
    const yes = await confirm({
      title: 'Delete Budget Item',
      description: `Remove "${item.item_name}" from the budget? This cannot be undone.`,
      confirmLabel: 'Delete',
      destructive: true,
    });
    if (!yes) return;
    await trackDelete(item.id, async () => {
      try {
        await deleteItem(item.id);
        toast.success('Budget item deleted');
      } catch (err) {
        showCaughtError(err);
      }
    });
  };

  const handleQuickStatusChange = async (item: EventBudgetItem, newStatus: 'pending' | 'deposit_paid' | 'paid') => {
    try {
      await updateItem(item.id, { status: newStatus });
      toast.success(`Status updated to ${getStatusStyle(newStatus).label}`);
    } catch (err) {
      showCaughtError(err);
    }
  };

  const handleImportAiItems = async (aiItems: BudgetAssistantItem[]) => {
    _importAbort = false;
    _broadcastImport({ current: 0, total: aiItems.length });
    let success = 0;
    for (const item of aiItems) {
      if (_importAbort) break;
      try {
        await addItem({
          category: item.category,
          item_name: item.item_name,
          estimated_cost: item.estimated_cost,
          status: 'pending',
        });
        success++;
        _broadcastImport({ current: success, total: aiItems.length });
      } catch (err) {
        // continue importing remaining items
      }
    }
    _broadcastImport(null);
    if (success > 0) {
      toast.success(`Imported ${success} of ${aiItems.length} budget items`);
    } else {
      toast.error('Failed to import budget items');
    }
  };

  // Report generation
  const reportHtml = useMemo(() => {
    if (!reportOpen) return '';
    return generateBudgetReportHtml(
      eventTitle || 'Event',
      items,
      {
        total_estimated: totalEstimated,
        total_actual: totalActual,
        overall_budget: overallBudget,
        includes_estimates: includesEstimates,
        event_budget: eventBudget,
        category_breakdown: categoryBreakdown,
      }
    );
  }, [reportOpen, eventTitle, items, totalEstimated, totalActual, overallBudget, includesEstimates, eventBudget, categoryBreakdown]);

  const handleExportExcel = async () => {
    const writeXlsxFile = (await import('write-excel-file')).default;
    const headerRow = [
      { value: 'S/N', type: String, fontWeight: 'bold' as const },
      { value: 'Category', type: String, fontWeight: 'bold' as const },
      { value: 'Item', type: String, fontWeight: 'bold' as const },
      { value: 'Vendor', type: String, fontWeight: 'bold' as const },
      { value: 'Budget', type: String, fontWeight: 'bold' as const },
      { value: 'Type', type: String, fontWeight: 'bold' as const },
      { value: 'Status', type: String, fontWeight: 'bold' as const },
      { value: 'Notes', type: String, fontWeight: 'bold' as const },
    ];
    const dataRows = items.map((item, i) => [
      { value: String(i + 1), type: String },
      { value: item.category || '', type: String },
      { value: item.item_name || '', type: String },
      { value: item.vendor_name || '', type: String },
      { value: Number(getEffectiveCost(item)) || 0, type: Number },
      { value: isItemEstimate(item) ? 'Estimate' : 'Actual', type: String },
      { value: getStatusStyle(item.status).label || '', type: String },
      { value: item.notes || '', type: String },
    ]);
    const totalRow = [
      { value: '', type: String },
      { value: 'TOTAL', type: String, fontWeight: 'bold' as const },
      { value: '', type: String },
      { value: '', type: String },
      { value: overallBudget || 0, type: Number, fontWeight: 'bold' as const },
      { value: includesEstimates ? 'Includes estimates' : 'All actual', type: String },
      { value: '', type: String },
      { value: '', type: String },
    ];
    await writeXlsxFile([headerRow, ...dataRows, totalRow] as any, {
      fileName: `${(eventTitle || 'event').replace(/\s+/g, '_')}_budget.xlsx`,
      columns: [
        { width: 6 }, { width: 18 }, { width: 25 }, { width: 18 },
        { width: 15 }, { width: 12 }, { width: 12 }, { width: 25 },
      ],
    });
  };

  if (!canView) {
    return (
      <div className="flex flex-col items-center justify-center py-16 text-center">
        <AlertCircle className="w-12 h-12 text-muted-foreground mb-4" />
        <p className="text-muted-foreground">You don't have permission to view the budget.</p>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="space-y-4">
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          {[1, 2, 3, 4].map(i => <Skeleton key={i} className="h-24 rounded-xl" />)}
        </div>
        <Skeleton className="h-12 rounded-xl" />
        {[1, 2, 3].map(i => <Skeleton key={i} className="h-20 rounded-xl" />)}
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <ConfirmDialog />

      {/* Non-blocking import progress indicator */}
      {importProgress && (
        <div className="sticky top-0 z-30 bg-background/95 backdrop-blur-sm border border-border rounded-xl p-3 shadow-sm">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <Loader2 className="w-4 h-4 animate-spin text-primary" />
              <span className="text-sm font-medium">
                Importing budget items... {importProgress.current}/{importProgress.total}
              </span>
            </div>
            <Button
              variant="ghost"
              size="sm"
              className="h-7 text-xs text-muted-foreground"
              onClick={() => { _importAbort = true; }}
            >
              Cancel
            </Button>
          </div>
          <Progress value={(importProgress.current / importProgress.total) * 100} className="h-1.5" />
        </div>
      )}

      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <Card className="border-0 shadow-sm bg-gradient-to-br from-blue-50 to-blue-100/50 dark:from-blue-950/30 dark:to-blue-900/20">
          <CardContent className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <div className="w-8 h-8 rounded-lg bg-blue-500/10 flex items-center justify-center">
                <DollarSign className="w-4 h-4 text-blue-600" />
              </div>
            </div>
            <p className="text-[11px] text-muted-foreground uppercase tracking-wider font-medium">Total Estimate</p>
            <p className="text-lg font-bold text-foreground mt-0.5">{formatPrice(totalEstimated)}</p>
          </CardContent>
        </Card>

        <Card className="border-0 shadow-sm bg-gradient-to-br from-emerald-50 to-emerald-100/50 dark:from-emerald-950/30 dark:to-emerald-900/20">
          <CardContent className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <div className="w-8 h-8 rounded-lg bg-emerald-500/10 flex items-center justify-center">
                <CheckCircle2 className="w-4 h-4 text-emerald-600" />
              </div>
            </div>
            <p className="text-[11px] text-muted-foreground uppercase tracking-wider font-medium">Total Actual</p>
            <p className="text-lg font-bold text-foreground mt-0.5">{formatPrice(totalActual)}</p>
          </CardContent>
        </Card>

        <Card className="border-0 shadow-sm bg-gradient-to-br from-amber-50 to-amber-100/50 dark:from-amber-950/30 dark:to-amber-900/20">
          <CardContent className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <div className="w-8 h-8 rounded-lg bg-amber-500/10 flex items-center justify-center">
                <BarChart3 className="w-4 h-4 text-amber-600" />
              </div>
            </div>
            <p className="text-[11px] text-muted-foreground uppercase tracking-wider font-medium">
              {includesEstimates ? 'Overall Budget (incl. estimates)' : 'Overall Event Budget'}
            </p>
            <p className="text-lg font-bold text-foreground mt-0.5">{formatPrice(overallBudget)}</p>
            <p className="text-[11px] text-muted-foreground mt-1">{pendingItems} pending - {items.length} total</p>
          </CardContent>
        </Card>
      </div>

      {/* Category Breakdown - no progress bars, grid layout like expenses */}
      {categoryBreakdown.length > 0 && (
        <Card className="border shadow-sm">
          <CardContent className="p-4">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                <BarChart3 className="w-4 h-4 text-muted-foreground" />
                <span className="text-sm font-semibold">Category Breakdown</span>
              </div>
              <span className="text-xs text-muted-foreground">{categoryBreakdown.length} categories</span>
            </div>
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
              {categoryBreakdown.map(cat => {
                const effective = cat.effective;
                const isEst = cat.effective !== cat.actual;
                return (
                  <div key={cat.category} className="flex items-center justify-between p-2 rounded-md bg-muted/30">
                    <div>
                      <p className="text-xs font-medium text-foreground">{cat.category}</p>
                      <p className="text-[10px] text-muted-foreground">{cat.count} item{cat.count !== 1 ? 's' : ''}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-xs font-semibold text-foreground">{formatPrice(effective)}</p>
                      {isEst && <p className="text-[9px] text-amber-600">est.</p>}
                    </div>
                  </div>
                );
              })}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Actions Bar */}
      <div className="flex items-center gap-2 flex-wrap">
        {canManage && (
          <Button size="sm" onClick={openAdd} className="gap-1.5">
            <Plus className="w-4 h-4" />
            Add Item
          </Button>
        )}
        {canManage && (
          <Button size="sm" variant="outline" onClick={() => setAiAssistantOpen(true)} className="gap-1.5">
            <SvgIcon src={PackageIcon} alt="" className="w-4 h-4" />
            AI Budget
          </Button>
        )}
        {items.length > 0 && (
          <Button size="sm" variant="outline" onClick={() => setReportOpen(true)} className="gap-1.5">
            <FileText className="w-4 h-4" />
            Report
          </Button>
        )}
        <div className="flex-1" />
        <div className="relative">
          <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-muted-foreground" />
          <Input
            placeholder="Search items..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-8 h-9 w-44 text-sm"
            autoComplete="off"
          />
        </div>
        <Select value={categoryFilter} onValueChange={setCategoryFilter}>
          <SelectTrigger className="h-9 w-32 text-xs">
            <SelectValue placeholder="Category" />
          </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Categories</SelectItem>
              {(() => {
                const allCats = new Set(BUDGET_CATEGORIES);
                items.forEach(i => { if (i.category) allCats.add(i.category); });
                return Array.from(allCats).sort().map(c => <SelectItem key={c} value={c}>{c}</SelectItem>);
              })()}
            </SelectContent>
        </Select>
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="h-9 w-28 text-xs">
            <SelectValue placeholder="Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            {STATUS_OPTIONS.map(s => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>

      {/* Budget Items List - scrollable */}
      {filtered.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="w-16 h-16 rounded-2xl bg-muted/60 flex items-center justify-center mb-4">
            <DollarSign className="w-7 h-7 text-muted-foreground" />
          </div>
          <h3 className="text-sm font-semibold mb-1">
            {items.length === 0 ? 'No budget items yet' : 'No matching items'}
          </h3>
          <p className="text-xs text-muted-foreground max-w-xs">
            {items.length === 0
              ? 'Start planning your event budget by adding your first item.'
              : 'Try adjusting your search or filters.'}
          </p>
          {items.length === 0 && canManage && (
            <Button size="sm" className="mt-4 gap-1.5" onClick={openAdd}>
              <Plus className="w-4 h-4" />
              Add First Item
            </Button>
          )}
        </div>
      ) : (
        <div className="max-h-[50vh] overflow-y-auto space-y-2 pr-1">
          {paginated.map((item) => {
            const statusStyle = getStatusStyle(item.status);
            const cost = getEffectiveCost(item);
            const isEst = isItemEstimate(item);
            return (
              <Card key={item.id} className="border shadow-sm hover:shadow-md transition-shadow relative">
                <DeleteOverlay visible={isDeleting(item.id)} />
                <CardContent className="p-4">
                  <div className="flex items-start gap-3">
                    {/* Status indicator */}
                    <div className={cn("w-1 self-stretch rounded-full flex-shrink-0", statusStyle.color)} />

                    <div className="flex-1 min-w-0">
                      {/* Top row: name + actions */}
                      <div className="flex items-start justify-between gap-2">
                        <div className="min-w-0">
                          <p className="text-sm font-semibold text-foreground truncate">{item.item_name}</p>
                          <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                            <Badge variant="secondary" className="text-[10px] px-1.5 py-0 h-5 font-medium">
                              {item.category}
                            </Badge>
                            {item.vendor_name && (
                              <span className="text-[11px] text-muted-foreground">{item.vendor_name}</span>
                            )}
                          </div>
                        </div>
                        <div className="flex items-center gap-1 flex-shrink-0">
                          {/* Quick status toggle */}
                          {canManage && (
                            <DropdownMenu>
                              <DropdownMenuTrigger asChild>
                                <button className={cn("text-[10px] px-2 py-0.5 rounded-full font-medium", statusStyle.textColor, statusStyle.bgColor)}>
                                  {statusStyle.label}
                                </button>
                              </DropdownMenuTrigger>
                              <DropdownMenuContent align="end" className="w-36">
                                {STATUS_OPTIONS.map(s => (
                                  <DropdownMenuItem
                                    key={s.value}
                                    onClick={() => handleQuickStatusChange(item, s.value as 'pending' | 'deposit_paid' | 'paid')}
                                    className="text-xs gap-2"
                                  >
                                    <span className={cn("w-2 h-2 rounded-full", s.color)} />
                                    {s.label}
                                    {s.value === item.status && <CheckCircle2 className="w-3 h-3 ml-auto text-primary" />}
                                  </DropdownMenuItem>
                                ))}
                              </DropdownMenuContent>
                            </DropdownMenu>
                          )}
                          {!canManage && (
                            <span className={cn("text-[10px] px-2 py-0.5 rounded-full font-medium", statusStyle.textColor, statusStyle.bgColor)}>
                              {statusStyle.label}
                            </span>
                          )}
                          {canManage && (
                            <DropdownMenu>
                              <DropdownMenuTrigger asChild>
                                <Button variant="ghost" size="sm" className="h-7 w-7 p-0">
                                  <MoreVertical className="w-3.5 h-3.5" />
                                </Button>
                              </DropdownMenuTrigger>
                              <DropdownMenuContent align="end" className="w-36">
                                <DropdownMenuItem onClick={() => openEdit(item)} className="text-xs gap-2">
                                  <Edit className="w-3.5 h-3.5" /> Edit
                                </DropdownMenuItem>
                                <DropdownMenuItem onClick={() => handleDelete(item)} className="text-xs gap-2 text-destructive">
                                  <Trash className="w-3.5 h-3.5" /> Delete
                                </DropdownMenuItem>
                              </DropdownMenuContent>
                            </DropdownMenu>
                          )}
                        </div>
                      </div>

                      {/* Bottom row: cost */}
                      <div className="flex items-center gap-3 mt-2.5 text-xs">
                        <div>
                          <span className="font-semibold">{formatPrice(cost)}</span>
                          {isEst && <span className="text-amber-600 ml-1.5 text-[10px]">estimate</span>}
                        </div>
                      </div>

                      {/* Notes */}
                      {item.notes && (
                        <p className="text-[11px] text-muted-foreground mt-1.5 line-clamp-1">{item.notes}</p>
                      )}
                    </div>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between pt-2">
          <p className="text-xs text-muted-foreground">{filtered.length} item{filtered.length !== 1 ? 's' : ''}</p>
          <div className="flex items-center gap-1">
            <Button variant="outline" size="icon" className="h-8 w-8" disabled={currentPage <= 1} onClick={() => setCurrentPage(p => p - 1)}>
              <ChevronLeft className="w-4 h-4" />
            </Button>
            <span className="text-xs px-2">{currentPage} / {totalPages}</span>
            <Button variant="outline" size="icon" className="h-8 w-8" disabled={currentPage >= totalPages} onClick={() => setCurrentPage(p => p + 1)}>
              <ChevronRight className="w-4 h-4" />
            </Button>
          </div>
        </div>
      )}

      {/* Add/Edit Dialog */}
      <Dialog open={dialogOpen} onOpenChange={(open) => { if (!open) resetForm(); setDialogOpen(open); }}>
        <DialogContent className="sm:max-w-[480px] max-h-[85vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editingItem ? 'Edit Budget Item' : 'Add Budget Item'}</DialogTitle>
            <DialogDescription>
              {editingItem ? 'Update the details of this budget item.' : 'Add a new item to your event budget.'}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label className="text-xs">Category *</Label>
                {customCategoryMode ? (
                  <div className="flex gap-2">
                    <Input
                      value={customCategory}
                      onChange={e => setCustomCategory(e.target.value)}
                      placeholder="Enter custom category"
                      className="flex-1"
                      autoFocus
                      onKeyDown={e => {
                        if (e.key === 'Enter' && customCategory.trim()) {
                          setFormCategory(customCategory.trim());
                          setCustomCategoryMode(false);
                          setCustomCategory('');
                        }
                      }}
                    />
                    <Button variant="outline" size="sm" onClick={() => {
                      if (customCategory.trim()) {
                        setFormCategory(customCategory.trim());
                      }
                      setCustomCategoryMode(false);
                      setCustomCategory('');
                    }}>Set</Button>
                    <Button variant="ghost" size="sm" onClick={() => {
                      setCustomCategoryMode(false);
                      setCustomCategory('');
                    }}>✕</Button>
                  </div>
                ) : (
                  <Select value={formCategory} onValueChange={v => {
                    if (v === '__custom__') {
                      setCustomCategoryMode(true);
                      setCustomCategory('');
                    } else {
                      setFormCategory(v);
                    }
                  }}>
                    <SelectTrigger><SelectValue placeholder="Select category" /></SelectTrigger>
                    <SelectContent>
                      {(() => {
                        const allCats = new Set(BUDGET_CATEGORIES);
                        items.forEach(i => { if (i.category) allCats.add(i.category); });
                        if (formCategory && !allCats.has(formCategory)) allCats.add(formCategory);
                        return Array.from(allCats).sort().map(c => <SelectItem key={c} value={c}>{c}</SelectItem>);
                      })()}
                      <SelectItem value="__custom__">+ Add custom category</SelectItem>
                    </SelectContent>
                  </Select>
                )}
              </div>
              <div className="space-y-1.5">
                <Label className="text-xs">Status</Label>
                <Select value={formStatus} onValueChange={(v) => setFormStatus(v as 'pending' | 'deposit_paid' | 'paid')}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {STATUS_OPTIONS.map(s => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs">Item Name *</Label>
              <Input value={formItemName} onChange={(e) => setFormItemName(e.target.value)} placeholder="e.g. Main hall booking" autoComplete="off" />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label className="text-xs">Estimated Cost</Label>
                <FormattedNumberInput value={formEstimatedCost} onChange={setFormEstimatedCost} prefix={`${currency} `} placeholder={`${currency} 0`} />
              </div>
              <div className="space-y-1.5">
                <Label className="text-xs">Actual Cost</Label>
                <FormattedNumberInput value={formActualCost} onChange={setFormActualCost} prefix={`${currency} `} placeholder={`${currency} 0`} />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs">Vendor / Supplier</Label>
              <ServiceProviderSearch
                value={formVendorName}
                onChange={setFormVendorName}
                placeholder="Search or type vendor name"
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs">Notes</Label>
              <Textarea value={formNotes} onChange={(e) => setFormNotes(e.target.value)} placeholder="Optional notes..." className="resize-none min-h-[60px]" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => { setDialogOpen(false); resetForm(); }}>Cancel</Button>
            <Button onClick={handleSave} disabled={saving}>
              {saving && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
              {editingItem ? 'Update' : 'Add Item'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Report Preview */}
      <ReportPreviewDialog
        open={reportOpen}
        onOpenChange={setReportOpen}
        title="Budget Report"
        html={reportHtml}
        onDownloadExcel={handleExportExcel}
      />

      {/* AI Budget Assistant */}
      <BudgetAssistant
        open={aiAssistantOpen}
        onOpenChange={setAiAssistantOpen}
        eventContext={{
          eventType: eventType || '',
          eventTypeName: eventTypeName,
          title: eventTitle || '',
          location: eventLocation || '',
          expectedGuests: expectedGuests || '',
          budget: eventBudget ? String(eventBudget) : '',
        }}
        onSaveBudget={() => {}}
        onImportItems={handleImportAiItems}
      />
    </div>
  );
};

export default EventBudget;