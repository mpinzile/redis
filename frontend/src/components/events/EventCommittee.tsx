import { useState } from 'react';
import nuruLogoUrl from '@/assets/nuru-logo.png';
import { useConfirmDialog } from '@/hooks/useConfirmDialog';
import { 
  Users, 
  Plus, 
  Mail, 
  Phone, 
  MoreVertical,
  Shield,
  Edit,
  Trash,
  Send,
  Loader2,
  FileText
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Checkbox } from '@/components/ui/checkbox';
import { useEventCommittee } from '@/data/useEvents';
import { usePolling } from '@/hooks/usePolling';
import { toast } from 'sonner';
import { showCaughtError } from '@/lib/api';
import UserSearchInput from './UserSearchInput';
import CommitteeSkeletonLoader from './CommitteeSkeletonLoader';
import CommitteePermissionsBadge from './CommitteePermissionsBadge';
import ReportPreviewDialog from '@/components/ReportPreviewDialog';
import type { SearchedUser } from '@/hooks/useUserSearch';
import type { EventPermissions } from '@/hooks/useEventPermissions';
import MemberImportDialog from './MemberImportDialog';
import { Upload } from 'lucide-react';

import { useLanguage } from '@/lib/i18n/LanguageContext';

interface EventCommitteeProps {
  eventId: string;
  permissions?: EventPermissions;
  eventTitle?: string;
}

const AVAILABLE_ROLES = [
  { id: 'coordinator', name: 'Event Coordinator', description: 'Oversees all event planning and execution' },
  { id: 'finance', name: 'Finance Manager', description: 'Manages budget, contributions and payments' },
  { id: 'guest_manager', name: 'Guest Manager', description: 'Handles guest list and invitations' },
  { id: 'vendor_liaison', name: 'Vendor Liaison', description: 'Coordinates with service providers' },
  { id: 'decorator', name: 'Decor Coordinator', description: 'Manages decorations and setup' },
  { id: 'catering', name: 'Catering Manager', description: 'Handles food and beverages' },
  { id: 'entertainment', name: 'Entertainment Lead', description: 'Manages music, MC and activities' },
  { id: 'logistics', name: 'Logistics Coordinator', description: 'Handles transport and venue setup' },
  { id: 'custom', name: 'Custom Role', description: 'Define a custom role' }
];

const AVAILABLE_PERMISSIONS = [
  { id: 'manage_guests', label: 'Manage Guests', description: 'Add, edit, remove guests' },
  { id: 'send_invitations', label: 'Send Invitations', description: 'Send invitations to guests' },
  { id: 'checkin_guests', label: 'Check-in Guests', description: 'Check in guests at the event' },
  { id: 'view_contributions', label: 'View Contributions', description: 'See contribution details' },
  { id: 'manage_contributions', label: 'Manage Contributions', description: 'Record and edit contributions' },
  { id: 'manage_budget', label: 'Manage Budget', description: 'Edit budget items' },
  { id: 'manage_schedule', label: 'Manage Schedule', description: 'Edit event schedule' },
  { id: 'manage_vendors', label: 'Manage Vendors', description: 'Handle service bookings' },
  { id: 'edit_event', label: 'Edit Event Details', description: 'Change event information' },
  { id: 'view_expenses', label: 'View Expenses', description: 'See expense reports' },
  { id: 'manage_expenses', label: 'Manage Expenses', description: 'Record and edit expenses' },
];

const EventCommittee = ({ eventId, permissions, eventTitle }: EventCommitteeProps) => {
  const { t } = useLanguage();
  const canManageCommittee = permissions?.can_manage_committee || permissions?.is_creator;
  const { members, loading, error, addMember, updateMember, removeMember, refetch } = useEventCommittee(eventId);
  
  const { confirm, ConfirmDialog } = useConfirmDialog();

  const [addDialogOpen, setAddDialogOpen] = useState(false);
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [editingMember, setEditingMember] = useState<any>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [selectedRole, setSelectedRole] = useState('');
  const [customRole, setCustomRole] = useState('');
  const [selectedUser, setSelectedUser] = useState<SearchedUser | null>(null);
  const [newMember, setNewMember] = useState({
    role_description: '',
    permissions: [] as string[],
    send_invitation: true,
    invitation_message: ''
  });

  // Edit state
  const [editRole, setEditRole] = useState('');
  const [editCustomRole, setEditCustomRole] = useState('');
  const [editPermissions, setEditPermissions] = useState<string[]>([]);
  const [reportOpen, setReportOpen] = useState(false);
  const [importOpen, setImportOpen] = useState(false);

  // Pause polling when any dialog is open to prevent form disruption
  const anyDialogOpen = addDialogOpen || editDialogOpen || reportOpen || importOpen;

  usePolling(refetch, 15000, !anyDialogOpen);

  const formatPhoneDisplay = (phone?: string | null): string => {
    if (!phone) return '';
    const cleaned = phone.replace(/\s+/g, '').replace(/^\+/, '');
    if (cleaned.startsWith('255') && cleaned.length >= 12) return '0' + cleaned.slice(3);
    return cleaned;
  };

  const generateCommitteeReportHtml = (): string => {
    const now = new Date();
    const timestamp = now.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })
      + ', ' + now.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });

    const sortedMembers = [...members].sort((a, b) => (a.name || '').localeCompare(b.name || ''));

    const rows = sortedMembers.map((m, i) => `
      <tr style="border-bottom:1px solid #eee;">
        <td style="padding:8px 12px;text-align:center;">${i + 1}</td>
        <td style="padding:8px 12px;">${m.name || '—'}</td>
        <td style="padding:8px 12px;">${m.role || '—'}</td>
        <td style="padding:8px 12px;">${formatPhoneDisplay(m.phone)}</td>
        <td style="padding:8px 12px;">${m.email || '—'}</td>
        <td style="padding:8px 12px;text-transform:capitalize;">${m.status || '—'}</td>
      </tr>
    `).join('');

    const active = sortedMembers.filter(m => m.status === 'active').length;
    const invited = sortedMembers.filter(m => m.status === 'invited').length;

    const logoAbsoluteUrl = new URL(nuruLogoUrl, window.location.origin).href;

    return `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Committee Report - ${eventTitle || 'Event'}</title>
      <style>
        body { font-family: Arial, sans-serif; padding: 40px; color: #333; }
        .header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 32px; border-bottom: 2px solid #e5e7eb; padding-bottom: 20px; }
        .brand { display: flex; flex-direction: column; align-items: flex-start; }
        .brand img { height: 40px; margin-bottom: 6px; }
        .brand .slogan { font-size: 11px; color: #888; font-style: italic; }
        .header-right { text-align: right; }
        .header-right h1 { font-size: 20px; margin: 0 0 4px 0; }
        .header-right h2 { font-size: 13px; color: #666; margin: 0; font-weight: normal; }
        table { width: 100%; border-collapse: collapse; margin-top: 16px; }
        th { background: #f8f8f8; padding: 10px 8px; text-align: left; border-bottom: 2px solid #ddd; font-size: 13px; }
        td { font-size: 13px; padding: 8px; border-bottom: 1px solid #eee; }
        .summary { display: flex; gap: 16px; margin-bottom: 24px; flex-wrap: wrap; }
        .summary-card { background: #f9fafb; border-radius: 8px; padding: 14px 18px; flex: 1; min-width: 120px; }
        .summary-card .label { font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 0.5px; }
        .summary-card .value { font-size: 17px; font-weight: bold; margin-top: 4px; }
        .footer { margin-top: 32px; font-size: 11px; color: #999; text-align: center; border-top: 1px solid #eee; padding-top: 12px; }
        @media print { body { padding: 20px; } }
      </style></head><body>
      <div class="header">
        <div class="brand">
          <img src="${logoAbsoluteUrl}" alt="Nuru" />
          <span class="slogan">Plan Smarter</span>
        </div>
        <div class="header-right">
          <h1>Committee Report</h1>
          <h2>${eventTitle || 'Event'} — ${timestamp}</h2>
        </div>
      </div>
      <div class="summary">
        <div class="summary-card"><div class="label">Total Members</div><div class="value">${sortedMembers.length}</div></div>
        <div class="summary-card"><div class="label">Active</div><div class="value" style="color:#16a34a">${active}</div></div>
        <div class="summary-card"><div class="label">Invited</div><div class="value" style="color:#ca8a04">${invited}</div></div>
      </div>
      <table>
        <thead><tr><th style="width:40px;">#</th><th>Name</th><th>Role</th><th>Phone</th><th>Email</th><th>Status</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
      <div class="footer">Generated by Nuru Events Workspace - © ${now.getFullYear()} Nuru | SEWMR TECHNOLOGIES</div>
    </body></html>`;
  };

  const handleAddMember = async () => {
    if (!selectedUser) {
      toast.error('Please search and select a user');
      return;
    }
    if (!selectedRole) {
      toast.error('Please select a role');
      return;
    }

    const roleName = selectedRole === 'custom' 
      ? customRole 
      : AVAILABLE_ROLES.find(r => r.id === selectedRole)?.name || selectedRole;

    setIsSubmitting(true);
    try {
      await addMember({
        user_id: selectedUser.id,
        name: `${selectedUser.first_name} ${selectedUser.last_name}`,
        email: selectedUser.email,
        phone: selectedUser.phone || undefined,
        role: roleName,
        role_description: newMember.role_description || undefined,
        permissions: newMember.permissions,
        send_invitation: newMember.send_invitation,
        invitation_message: newMember.invitation_message || undefined
      });
      toast.success('Committee member added');
      setAddDialogOpen(false);
      resetForm();
    } catch (err: any) {
      showCaughtError(err, 'Failed to add member');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleEditMember = (member: any) => {
    setEditingMember(member);
    // Find matching role
    const matchedRole = AVAILABLE_ROLES.find(r => r.name === member.role);
    if (matchedRole) {
      setEditRole(matchedRole.id);
      setEditCustomRole('');
    } else {
      setEditRole('custom');
      setEditCustomRole(member.role || '');
    }
    // Normalize permissions to string[]
    const perms = Array.isArray(member.permissions)
      ? member.permissions
      : typeof member.permissions === 'object' && member.permissions
        ? Object.entries(member.permissions).filter(([, v]) => v === true).map(([k]) => k)
        : [];
    setEditPermissions(perms);
    setEditDialogOpen(true);
  };

  const handleUpdateMember = async () => {
    if (!editingMember) return;
    const roleName = editRole === 'custom'
      ? editCustomRole
      : AVAILABLE_ROLES.find(r => r.id === editRole)?.name || editRole;

    setIsSubmitting(true);
    try {
      await updateMember(editingMember.id, {
        role: roleName,
        permissions: editPermissions,
      } as any);
      toast.success('Committee member updated');
      setEditDialogOpen(false);
      setEditingMember(null);
    } catch (err: any) {
      showCaughtError(err, 'Failed to update member');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleRemoveMember = async (memberId: string) => {
    const member = members.find((m: any) => m.id === memberId) as any;
    const memberName = member?.user?.full_name || member?.user?.first_name || 'member';
    const confirmed = await confirm({
      title: 'Remove Committee Member',
      description: `Are you sure you want to remove ${memberName}? This action cannot be undone.`,
      confirmLabel: 'Remove',
      destructive: true,
    });
    if (!confirmed) return;
    const toastId = toast.loading(`Removing ${memberName}…`);
    try {
      await removeMember(memberId);
      toast.success('Member removed', { id: toastId });
    } catch (err: any) {
      toast.dismiss(toastId);
      showCaughtError(err, 'Failed to remove member');
    }
  };

  const handleResendInvite = async (memberId: string) => {
    const toastId = toast.loading('Resending invitation…');
    try {
      const { eventsApi } = await import('@/lib/api/events');
      await eventsApi.resendCommitteeInvitation(eventId, memberId);
      toast.success('Invitation resent', { id: toastId });
    } catch (err: any) {
      toast.dismiss(toastId);
      showCaughtError(err, 'Failed to resend invitation');
    }
  };

  const resetForm = () => {
    setSelectedUser(null);
    setNewMember({
      role_description: '',
      permissions: [],
      send_invitation: true,
      invitation_message: ''
    });
    setSelectedRole('');
    setCustomRole('');
  };

  const togglePermission = (permissionId: string) => {
    setNewMember(prev => ({
      ...prev,
      permissions: prev.permissions.includes(permissionId)
        ? prev.permissions.filter(p => p !== permissionId)
        : [...prev.permissions, permissionId]
    }));
  };

  const toggleEditPermission = (permissionId: string) => {
    setEditPermissions(prev =>
      prev.includes(permissionId)
        ? prev.filter(p => p !== permissionId)
        : [...prev, permissionId]
    );
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'active':
        return <Badge className="bg-green-100 text-green-800">Active</Badge>;
      case 'invited':
        return <Badge className="bg-yellow-100 text-yellow-800">Invited</Badge>;
      case 'declined':
        return <Badge className="bg-red-100 text-red-800">Declined</Badge>;
      default:
        return <Badge variant="outline">{status}</Badge>;
    }
  };

  if (loading) return <CommitteeSkeletonLoader />;
  if (error) return <div className="p-6 text-center text-destructive">{error}</div>;

  return (
    <div className="space-y-6">
      <ConfirmDialog />
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-semibold">Event Committee</h2>
          <p className="text-muted-foreground">Manage your event planning team</p>
        </div>
        <div className="flex items-center gap-2">
          {members.length > 0 && (
            <Button variant="outline" size="sm" onClick={() => setReportOpen(true)}>
              <FileText className="w-4 h-4 mr-1.5" />
              Report
            </Button>
          )}
          {canManageCommittee && (
            <Button variant="outline" onClick={() => setImportOpen(true)}>
              <Upload className="w-4 h-4 mr-2" />
              Import
            </Button>
          )}
          {canManageCommittee && (
            <Button onClick={() => setAddDialogOpen(true)}>
              <Plus className="w-4 h-4 mr-2" />
              Add Member
            </Button>
          )}
        </div>
      </div>


      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        {members.length === 0 ? (
          <Card className="col-span-full">
            <CardContent className="p-8 text-center">
              <Users className="w-12 h-12 mx-auto text-muted-foreground mb-4" />
              <h3 className="font-medium mb-2">No committee members yet</h3>
              <p className="text-muted-foreground text-sm mb-4">
                Add team members to help you plan and manage your event
              </p>
              <Button onClick={() => setAddDialogOpen(true)}>
                <Plus className="w-4 h-4 mr-2" />
                Add First Member
              </Button>
            </CardContent>
          </Card>
        ) : (
          members.map((member) => (
            <Card key={member.id}>
              <CardContent className="p-4">
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center gap-3">
                    <Avatar>
                      <AvatarImage src={member.avatar || undefined} />
                      <AvatarFallback>{(member.name || 'U').charAt(0)}</AvatarFallback>
                    </Avatar>
                    <div>
                      <p className="font-medium">{member.name}</p>
                      <p className="text-sm text-primary">{member.role}</p>
                    </div>
                  </div>
                  {canManageCommittee && (
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button variant="ghost" size="icon">
                          <MoreVertical className="w-4 h-4" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem onClick={() => handleEditMember(member)}>
                          <Edit className="w-4 h-4 mr-2" />Edit
                        </DropdownMenuItem>
                        {member.status === 'invited' && (
                          <DropdownMenuItem onClick={() => handleResendInvite(member.id)}>
                            <Send className="w-4 h-4 mr-2" />Resend Invite
                          </DropdownMenuItem>
                        )}
                        <DropdownMenuItem className="text-red-600" onClick={() => handleRemoveMember(member.id)}>
                          <Trash className="w-4 h-4 mr-2" />Remove
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  )}
                </div>
                <div className="space-y-2 text-sm">
                  {member.email && (
                    <div className="flex items-center gap-2 text-muted-foreground">
                      <Mail className="w-3 h-3" /><span className="truncate">{member.email}</span>
                    </div>
                  )}
                  {member.phone && (
                    <div className="flex items-center gap-2 text-muted-foreground">
                      <Phone className="w-3 h-3" /><span>{formatPhoneDisplay(member.phone)}</span>
                    </div>
                  )}
                </div>
                <div className="flex items-center justify-between mt-4 pt-3 border-t">
                  {getStatusBadge(member.status)}
                  <CommitteePermissionsBadge permissions={member.permissions} />
                </div>
              </CardContent>
            </Card>
          ))
        )}
      </div>

      {/* Add Member Dialog */}
      <Dialog open={addDialogOpen} onOpenChange={setAddDialogOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Add Committee Member</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label>Search User *</Label>
              {selectedUser ? (
                <div className="flex items-center gap-3 p-3 bg-muted/50 rounded-lg">
                  <Avatar className="w-8 h-8">
                    <AvatarImage src={selectedUser.avatar || undefined} />
                    <AvatarFallback>{selectedUser.first_name?.charAt(0)}</AvatarFallback>
                  </Avatar>
                  <div className="flex-1">
                    <p className="text-sm font-medium">{selectedUser.first_name} {selectedUser.last_name}</p>
                    <p className="text-xs text-muted-foreground">{selectedUser.email}</p>
                  </div>
                  <Button variant="ghost" size="sm" onClick={() => setSelectedUser(null)}>Change</Button>
                </div>
              ) : (
                <UserSearchInput onSelect={setSelectedUser} />
              )}
            </div>

            <div className="space-y-2">
              <Label>Role *</Label>
              <Select value={selectedRole} onValueChange={setSelectedRole}>
                <SelectTrigger><SelectValue placeholder="Select a role" /></SelectTrigger>
                <SelectContent>
                  {AVAILABLE_ROLES.map(role => (
                    <SelectItem key={role.id} value={role.id}>
                      <div>
                        <p className="font-medium">{role.name}</p>
                        <p className="text-xs text-muted-foreground">{role.description}</p>
                      </div>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {selectedRole === 'custom' && (
              <div className="space-y-2">
                <Label>Custom Role Name</Label>
                <Input value={customRole} onChange={(e) => setCustomRole(e.target.value)} placeholder="Enter role name" />
              </div>
            )}

            <div className="space-y-2">
              <Label>Permissions</Label>
              <div className="grid gap-2 max-h-40 overflow-y-auto border rounded-md p-3">
                {AVAILABLE_PERMISSIONS.map(perm => (
                  <div key={perm.id} className="flex items-start gap-2">
                    <Checkbox id={perm.id} checked={newMember.permissions.includes(perm.id)} onCheckedChange={() => togglePermission(perm.id)} />
                    <div>
                      <Label htmlFor={perm.id} className="text-sm font-medium cursor-pointer">{perm.label}</Label>
                      <p className="text-xs text-muted-foreground">{perm.description}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            <div className="flex items-center gap-2">
              <Checkbox id="send-invite" checked={newMember.send_invitation} onCheckedChange={(checked) => setNewMember(prev => ({ ...prev, send_invitation: !!checked }))} />
              <Label htmlFor="send-invite" className="cursor-pointer">Send invitation to join committee</Label>
            </div>

            {newMember.send_invitation && (
              <div className="space-y-2">
                <Label>Custom Invitation Message (optional)</Label>
                <Textarea
                  value={newMember.invitation_message}
                  onChange={(e) => setNewMember(prev => ({ ...prev, invitation_message: e.target.value }))}
                  placeholder="Add a personal message..."
                  rows={2}
                />
              </div>
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => { setAddDialogOpen(false); resetForm(); }}>Cancel</Button>
            <Button onClick={handleAddMember} disabled={isSubmitting}>
              {isSubmitting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Adding...</> : 'Add Member'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Edit Member Dialog */}
      <Dialog open={editDialogOpen} onOpenChange={(open) => { setEditDialogOpen(open); if (!open) setEditingMember(null); }}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Edit Committee Member — {editingMember?.name}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label>Role *</Label>
              <Select value={editRole} onValueChange={setEditRole}>
                <SelectTrigger><SelectValue placeholder="Select a role" /></SelectTrigger>
                <SelectContent>
                  {AVAILABLE_ROLES.map(role => (
                    <SelectItem key={role.id} value={role.id}>
                      <div>
                        <p className="font-medium">{role.name}</p>
                        <p className="text-xs text-muted-foreground">{role.description}</p>
                      </div>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {editRole === 'custom' && (
              <div className="space-y-2">
                <Label>Custom Role Name</Label>
                <Input value={editCustomRole} onChange={(e) => setEditCustomRole(e.target.value)} placeholder="Enter role name" />
              </div>
            )}

            <div className="space-y-2">
              <Label>Permissions</Label>
              <div className="grid gap-2 max-h-40 overflow-y-auto border rounded-md p-3">
                {AVAILABLE_PERMISSIONS.map(perm => (
                  <div key={perm.id} className="flex items-start gap-2">
                    <Checkbox id={`edit-${perm.id}`} checked={editPermissions.includes(perm.id)} onCheckedChange={() => toggleEditPermission(perm.id)} />
                    <div>
                      <Label htmlFor={`edit-${perm.id}`} className="text-sm font-medium cursor-pointer">{perm.label}</Label>
                      <p className="text-xs text-muted-foreground">{perm.description}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => { setEditDialogOpen(false); setEditingMember(null); }}>Cancel</Button>
            <Button onClick={handleUpdateMember} disabled={isSubmitting}>
              {isSubmitting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving...</> : 'Save Changes'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ReportPreviewDialog
        open={reportOpen}
        onOpenChange={setReportOpen}
        title="Committee Report"
        html={generateCommitteeReportHtml()}
      />

      <MemberImportDialog
        eventId={eventId}
        mode="committee"
        open={importOpen}
        onClose={() => setImportOpen(false)}
        onCompleted={() => refetch()}
      />
    </div>

  );
};

export default EventCommittee;
