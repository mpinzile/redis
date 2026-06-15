/**
 * Events API - User events management
 */

import { get, post, put, del, postFormData, putFormData, buildQueryString } from "./helpers";
import type { ChecklistItem } from "./templates";

export interface EventPermissions {
  is_creator: boolean;
  role: string | null;
  can_view_guests: boolean;
  can_manage_guests: boolean;
  can_send_invitations: boolean;
  can_check_in_guests: boolean;
  can_view_budget: boolean;
  can_manage_budget: boolean;
  can_view_contributions: boolean;
  can_manage_contributions: boolean;
  can_view_vendors: boolean;
  can_manage_vendors: boolean;
  can_approve_bookings: boolean;
  can_edit_event: boolean;
  can_manage_committee: boolean;
  can_view_expenses: boolean;
  can_manage_expenses: boolean;
}


import type { 
  Event, 
  EventGuest, 
  CommitteeMember, 
  EventContribution, 
  EventScheduleItem, 
  EventBudgetItem,
  PaginatedResponse 
} from "./types";

export interface EventQueryParams {
  page?: number;
  limit?: number;
  status?: "draft" | "published" | "cancelled" | "completed" | "all";
  sort_by?: "created_at" | "start_date" | "title";
  sort_order?: "asc" | "desc";
  search?: string;
}

export interface GuestQueryParams {
  page?: number;
  limit?: number;
  search?: string;
  rsvp_status?: "pending" | "confirmed" | "declined" | "maybe" | "all";
  invitation_status?: "sent" | "not_sent" | "all";
  checked_in?: boolean;
  table_number?: string;
  sort_by?: "name" | "created_at" | "rsvp_status" | "table_number";
  sort_order?: "asc" | "desc";
}

export interface ContributionQueryParams {
  page?: number;
  limit?: number;
  status?: "pending" | "confirmed" | "failed" | "all";
  sort_by?: "created_at" | "amount" | "contributor_name";
  sort_order?: "asc" | "desc";
}

export const eventsApi = {
  // ============================================================================
  // EVENT CRUD
  // ============================================================================
  
  getAll: (params?: EventQueryParams) => 
    get<{ events: Event[]; pagination: PaginatedResponse<Event>["pagination"] }>(`/user-events/${buildQueryString(params)}`),

  // ============================================================================
  // INVITED & COMMITTEE EVENTS (Dashboard visibility)
  // ============================================================================

  getInvitedEvents: (params?: { page?: number; limit?: number }) =>
    get<{ events: any[]; pagination: PaginatedResponse<Event>["pagination"] }>(`/user-events/invited${buildQueryString(params)}`),

  respondToInvitation: (eventId: string, data: { rsvp_status: "confirmed" | "declined" | "pending"; meal_preference?: string; dietary_restrictions?: string; special_requests?: string }) =>
    put<{ event_id: string; rsvp_status: string; rsvp_at: string; attendee_id?: string }>(`/user-events/invited/${eventId}/rsvp`, data),

  getCommitteeEvents: (params?: { page?: number; limit?: number }) =>
    get<{ events: any[]; pagination: PaginatedResponse<Event>["pagination"] }>(`/user-events/committee${buildQueryString(params)}`),

  getInvitationCard: (eventId: string, guestId?: string) =>
    get<{ event: any; guest: any; organizer: any; invitation_code: string; qr_code_data: string; rsvp_deadline?: string }>(`/user-events/${eventId}/invitation-card${buildQueryString(guestId ? { guest_id: guestId, attendee_id: guestId, guestId, attendeeId: guestId } : undefined)}`),

  /**
   * Get current user's permissions for an event
   */
  getMyPermissions: (eventId: string) => get<EventPermissions>(`/user-events/${eventId}/my-permissions`),

  /**
   * Aggregated KPIs for the Event Management overview (tickets, revenue,
   * contributions, sponsors). All numbers come from the backend — never
   * hardcode values on the client.
   */
  getManagementOverview: (eventId: string) =>
    get<{
      is_ticketed: boolean;
      kpis: { tickets_sold: number; tickets_capacity: number; total_revenue: number; contributions_count: number; days_to_go: number };
      ticket_sales: { total_sold: number; total_capacity: number; classes: { id: string; name: string; price: number; quantity: number; sold: number; revenue: number }[] };
      contribution_status: {
        paid_count: number;
        fully_paid_count?: number;
        in_progress_count?: number;
        pledged_count: number;
        outstanding_count: number;
        paid_total: number;
        pledged_total: number;
      };
      revenue_summary: { total_revenue: number; tickets: number; contributions: number; sponsors: number; trend_pct: number | null; trend_window_days: number };
      sponsors: { total: number; accepted: number; pending: number; declined: number; revenue: number };
    }>(`/user-events/${eventId}/management-overview`),

  // ============================================================================
  // EVENT SPONSORS
  // ============================================================================
  listSponsors: (eventId: string) =>
    get<{ items: any[]; summary: { total: number; accepted: number; pending: number; declined: number; contribution_total: number } }>(
      `/user-events/${eventId}/sponsors`
    ),
  inviteSponsor: (eventId: string, data: { user_service_id: string; message?: string; contribution_amount?: number }) =>
    post<any>(`/user-events/${eventId}/sponsors`, data),
  cancelSponsor: (eventId: string, sponsorId: string) =>
    del<any>(`/user-events/${eventId}/sponsors/${sponsorId}`),

  // Vendor-side sponsor inbox
  getMySponsorRequests: (status?: string) =>
    get<{ items: any[]; pending_count: number }>(`/sponsor-requests${status ? `?status=${status}` : ''}`),
  respondToSponsorRequest: (sponsorId: string, data: { action: 'accept' | 'decline'; response_note?: string; contribution_amount?: number }) =>
    post<any>(`/sponsor-requests/${sponsorId}/respond`, data),

  /**
   * Get a single event by ID
   */
  getById: (eventId: string) => get<Event>(`/user-events/${eventId}`),

  /**
   * Create a new event
   */
  create: (formData: FormData) => postFormData<Event>("/user-events/", formData),

  /**
   * Update an event
   */
  update: (eventId: string, formData: FormData) => putFormData<Event>(`/user-events/${eventId}`, formData),

  /**
   * Delete an event
   */
  delete: (eventId: string) => del(`/user-events/${eventId}`),

  /**
   * Update event status (draft, published, confirmed, cancelled, completed)
   */
  updateStatus: (eventId: string, status: "draft" | "published" | "confirmed" | "cancelled" | "completed") =>
    put<{ id: string; status: string; updated_at: string }>(`/user-events/${eventId}/status`, { status }),

  /**
   * Publish an event (convenience alias)
   */
  publish: (eventId: string) =>
    put<{ id: string; status: string; updated_at: string }>(`/user-events/${eventId}/status`, { status: "published" }),

  /**
   * Cancel an event (convenience alias)
   */
  cancel: (eventId: string, _data?: { reason?: string; notify_guests?: boolean; notify_vendors?: boolean }) =>
    put<{ id: string; status: string; updated_at: string }>(`/user-events/${eventId}/status`, { status: "cancelled" }),

  // ============================================================================
  // EVENT GUESTS
  // ============================================================================

  /**
   * Get event guests
   */
  getGuests: (eventId: string, params?: GuestQueryParams) => 
    get<{ 
      guests: EventGuest[]; 
      summary: { total: number; confirmed: number; pending: number; declined: number; maybe: number; checked_in: number };
      pagination: PaginatedResponse<EventGuest>["pagination"];
    }>(`/user-events/${eventId}/guests${buildQueryString(params)}`),

  /**
   * Get single guest
   */
  getGuest: (eventId: string, guestId: string) => get<EventGuest>(`/user-events/${eventId}/guests/${guestId}`),

  /**
   * Add a guest
   */
  addGuest: (eventId: string, data: Partial<EventGuest>) => post<EventGuest>(`/user-events/${eventId}/guests`, data),

  /**
   * Bulk add guests
   */
  addGuestsBulk: (eventId: string, data: { guests: Partial<EventGuest>[]; skip_duplicates?: boolean; default_tags?: string[] }) => 
    post<{ imported: number; skipped: number; errors: Array<{ row: number; name?: string; error: string }>; guests: EventGuest[] }>(`/user-events/${eventId}/guests/bulk`, data),

  /**
   * Add contributors as guests (batch)
   */
  addContributorsAsGuests: (eventId: string, data: { contributor_ids: string[]; send_sms?: boolean }) =>
    post<{ added: number; skipped: number; errors: Array<{ contributor_id: string; error: string }> }>(`/user-events/${eventId}/guests/from-contributors`, data),

  /**
   * Import guests from CSV
   */
  importGuestsCSV: (eventId: string, formData: FormData) => 
    postFormData<{ imported: number; skipped: number; errors: Array<{ row: number; error: string }> }>(`/user-events/${eventId}/guests/import`, formData),

  /**
   * Update a guest
   */
  updateGuest: (eventId: string, guestId: string, data: Partial<EventGuest>) => 
    put<EventGuest>(`/user-events/${eventId}/guests/${guestId}`, data),

  /**
   * Delete a guest
   */
  deleteGuest: (eventId: string, guestId: string) => del(`/user-events/${eventId}/guests/${guestId}`),

  /**
   * Delete multiple guests
   */
  deleteGuestsBulk: (eventId: string, guest_ids: string[]) => 
    del<{ deleted: number }>(`/user-events/${eventId}/guests/bulk`, { guest_ids }),

  /**
   * Send invitation to guest
   */
  sendInvitation: (eventId: string, guestId: string, data: { method: "email" | "sms" | "whatsapp" | "whatsapp_text"; custom_message?: string; include_calendar?: boolean; include_map?: boolean }) => 
    post<{ guest_id: string; method: string; sent_at: string; invitation_url: string }>(`/user-events/${eventId}/guests/${guestId}/invite`, data),

  /**
   * Send bulk invitations
   */
  sendBulkInvitations: (eventId: string, data: { method: "email" | "sms" | "whatsapp" | "whatsapp_text"; guest_ids?: string[]; filter?: { rsvp_status?: string; invitation_sent?: boolean; tags?: string[] }; custom_message?: string }) => 
    post<{ total_selected: number; sent_count: number; failed_count: number; failures: Array<{ guest_id: string; name: string; reason: string }> }>(`/user-events/${eventId}/guests/invite-all`, data),

  /**
   * Resend invitation
   */
  resendInvitation: (eventId: string, guestId: string, data: { method: "email" | "sms" | "whatsapp" | "whatsapp_text"; custom_message?: string }) => 
    post<{ guest_id: string; method: string; sent_at: string; resend_count: number }>(`/user-events/${eventId}/guests/${guestId}/resend-invite`, data),

  /**
   * Check-in guest
   */
  checkinGuest: (eventId: string, guestId: string, data?: { plus_ones_checked_in?: number; notes?: string }) => 
    post<{ guest_id: string; name: string; checked_in: boolean; checked_in_at: string; table_number?: string; seat_number?: number }>(`/user-events/${eventId}/guests/${guestId}/checkin`, data),

  /**
   * Check-in guest by QR code
   */
  checkinGuestByQR: (eventId: string, data: { qr_code: string; plus_ones_checked_in?: number }) => 
    post<{ guest_id: string; name: string; checked_in: boolean; checked_in_at: string; table_number?: string }>(`/user-events/${eventId}/guests/checkin-qr`, data),

  /**
   * Undo check-in
   */
  undoCheckin: (eventId: string, guestId: string) => 
    post<{ guest_id: string; checked_in: boolean }>(`/user-events/${eventId}/guests/${guestId}/undo-checkin`),

  /**
   * Export guests
   */
  exportGuests: (eventId: string, params?: { format?: "csv" | "xlsx" | "pdf"; fields?: string; rsvp_status?: string }) => 
    get<Blob>(`/user-events/${eventId}/guests/export${buildQueryString(params)}`),

  // ============================================================================
  // PUBLIC RSVP (No Auth)
  // ============================================================================

  /**
   * Get public RSVP page data
   */
  getPublicRSVP: (eventId: string, guestId: string, token: string) => 
    get<{ event: Partial<Event>; guest: Partial<EventGuest>; rsvp_options: { allow_plus_ones: boolean; max_plus_ones: number; require_dietary_info: boolean; deadline_passed: boolean } }>(`/events/${eventId}/rsvp/${guestId}?token=${token}`),

  /**
   * Submit public RSVP
   */
  submitPublicRSVP: (eventId: string, data: { guest_id: string; token: string; rsvp_status: "confirmed" | "declined" | "maybe"; plus_ones?: number; plus_one_names?: string[]; dietary_requirements?: string; allergies?: string; message?: string }) => 
    post<{ event: Partial<Event>; rsvp_status: string; calendar_link?: string; map_link?: string }>(`/events/${eventId}/rsvp`, data),

  // ============================================================================
  // COMMITTEE
  // ============================================================================

  /**
   * Get committee members
   */
  getCommittee: (eventId: string) => get<CommitteeMember[]>(`/user-events/${eventId}/committee`),

  /**
   * Add committee member
   */
  addCommitteeMember: (eventId: string, data: { user_id?: string; name: string; email?: string; phone?: string; role: string; role_description?: string; permissions: string[]; send_invitation?: boolean; invitation_message?: string }) => 
    post<CommitteeMember>(`/user-events/${eventId}/committee`, data),

  /**
   * Update committee member
   */
  updateCommitteeMember: (eventId: string, memberId: string, data: Partial<CommitteeMember>) => 
    put<CommitteeMember>(`/user-events/${eventId}/committee/${memberId}`, data),

  /**
   * Remove committee member
   */
  removeCommitteeMember: (eventId: string, memberId: string) => 
    del(`/user-events/${eventId}/committee/${memberId}`),

  /**
   * Resend committee invitation
   */
  resendCommitteeInvitation: (eventId: string, memberId: string) => 
    post<{ member_id: string; sent_at: string }>(`/user-events/${eventId}/committee/${memberId}/resend-invite`),

  // ============================================================================
  // CONTRIBUTIONS
  // ============================================================================

  /**
   * Get event contributions
   */
  getContributions: (eventId: string, params?: ContributionQueryParams) => 
    get<{ 
      contributions: EventContribution[]; 
      summary: { total_contributions: number; total_amount: number; target_amount?: number; progress_percentage: number; confirmed_count: number; pending_count: number; currency: string };
      pagination: PaginatedResponse<EventContribution>["pagination"];
    }>(`/user-events/${eventId}/contributions${buildQueryString(params)}`),

  /**
   * Record manual contribution
   */
  addContribution: (eventId: string, data: Partial<EventContribution>) => 
    post<EventContribution>(`/user-events/${eventId}/contributions`, data),

  /**
   * Update contribution
   */
  updateContribution: (eventId: string, contributionId: string, data: Partial<EventContribution>) => 
    put<EventContribution>(`/user-events/${eventId}/contributions/${contributionId}`, data),

  /**
   * Delete contribution
   */
  deleteContribution: (eventId: string, contributionId: string) => 
    del(`/user-events/${eventId}/contributions/${contributionId}`),

  /**
   * Send thank you to contributor
   */
  sendThankYou: (eventId: string, contributionId: string, data: { method: "email" | "sms" | "whatsapp"; custom_message?: string }) => 
    post<{ contribution_id: string; thank_you_sent: boolean; thank_you_sent_at: string; method: string }>(`/user-events/${eventId}/contributions/${contributionId}/thank`, data),

  /**
   * Send bulk thank you
   */
  sendBulkThankYou: (eventId: string, data: { contribution_ids?: string[]; filter?: { thank_you_sent?: boolean; status?: string }; method: "email" | "sms" | "whatsapp"; custom_message?: string }) => 
    post<{ sent_count: number; failed_count: number; failures: Array<{ contribution_id: string; reason: string }> }>(`/user-events/${eventId}/contributions/thank-all`, data),

  /**
   * Get public contribution page
   */
  getPublicContributionPage: (eventId: string) => 
    get<{ event: Partial<Event>; contribution_info: { enabled: boolean; description?: string; target_amount?: number; current_amount: number; progress_percentage: number; contributor_count: number; currency: string; suggested_amounts?: number[] }; payment_methods: Array<{ id: string; name: string; icon: string; instructions: string }>; recent_contributions: Array<{ contributor_name: string; amount: number; message?: string; created_at: string }> }>(`/events/${eventId}/contribute`),

  /**
   * Submit public contribution
   */
  submitPublicContribution: (eventId: string, data: { contributor_name: string; contributor_email?: string; contributor_phone?: string; amount: number; payment_method: string; message?: string; is_anonymous?: boolean }) => 
    post<{ contribution_id: string; status: string; payment_instructions?: { paybill?: string; account?: string; phone?: string } }>(`/events/${eventId}/contribute`, data),

  // ============================================================================
  // SCHEDULE
  // ============================================================================

  /**
   * Get event schedule
   */
  getSchedule: (eventId: string) => get<EventScheduleItem[]>(`/user-events/${eventId}/schedule`),

  /**
   * Add schedule item
   */
  addScheduleItem: (eventId: string, data: Partial<EventScheduleItem>) => 
    post<EventScheduleItem>(`/user-events/${eventId}/schedule`, data),

  /**
   * Update schedule item
   */
  updateScheduleItem: (eventId: string, itemId: string, data: Partial<EventScheduleItem>) => 
    put<EventScheduleItem>(`/user-events/${eventId}/schedule/${itemId}`, data),

  /**
   * Delete schedule item
   */
  deleteScheduleItem: (eventId: string, itemId: string) => 
    del(`/user-events/${eventId}/schedule/${itemId}`),

  /**
   * Reorder schedule items
   */
  reorderSchedule: (eventId: string, data: { items: Array<{ id: string; display_order: number }> }) => 
    put<EventScheduleItem[]>(`/user-events/${eventId}/schedule/reorder`, data),

  // ============================================================================
  // BUDGET
  // ============================================================================

  /**
   * Get event budget items
   */
  getBudget: (eventId: string) => 
    get<{ items: EventBudgetItem[]; summary: { total_estimated: number; total_actual: number; variance: number; currency: string } }>(`/user-events/${eventId}/budget`),

  /**
   * Add budget item
   */
  addBudgetItem: (eventId: string, data: Partial<EventBudgetItem>) => 
    post<EventBudgetItem>(`/user-events/${eventId}/budget`, data),

  /**
   * Update budget item
   */
  updateBudgetItem: (eventId: string, itemId: string, data: Partial<EventBudgetItem>) => 
    put<EventBudgetItem>(`/user-events/${eventId}/budget/${itemId}`, data),

  /**
   * Delete budget item
   */
  deleteBudgetItem: (eventId: string, itemId: string) => 
    del(`/user-events/${eventId}/budget/${itemId}`),

  // ============================================================================
  // EVENT SERVICES (Assign providers to event)
  // ============================================================================

  /**
   * Get event services
   */
  getEventServices: (eventId: string) =>
    get<any[]>(`/user-events/${eventId}/services`),

  /**
   * Assign a service provider to event
   */
  addEventService: (eventId: string, data: { provider_service_id?: string; service_id?: string; provider_user_id?: string; quoted_price?: number; notes?: string }) =>
    post<any>(`/user-events/${eventId}/services`, data),

  /** Add an off-platform (manual) vendor to event */
  addManualVendor: (eventId: string, data: { manual_vendor_name: string; manual_vendor_category_id?: string; manual_vendor_phone?: string; manual_vendor_email?: string; quoted_price?: number; manual_vendor_notes?: string }) =>
    post<any>(`/user-events/${eventId}/services`, { ...data, is_manual: true }),

  /** Download confirmed-vendors report (pdf or xlsx) — returns Blob */
  downloadVendorsReport: async (eventId: string, format: 'pdf' | 'xlsx'): Promise<Blob> => {
    const { resolveApiBaseUrl, getAuthHeaders } = await import('./helpers');
    const base = resolveApiBaseUrl();
    const res = await fetch(`${base}/user-events/${eventId}/vendors/report?format=${format}`, {
      headers: getAuthHeaders(),
    });
    if (!res.ok) throw new Error('Failed to download report');
    return await res.blob();
  },

  /**
   * Update event service
   */
  updateEventService: (eventId: string, serviceId: string, data: { agreed_price?: number; notes?: string; service_status?: string }) =>
    put<any>(`/user-events/${eventId}/services/${serviceId}`, data),

  /**
   * Remove service from event
   */
  removeEventService: (eventId: string, serviceId: string) =>
    del(`/user-events/${eventId}/services/${serviceId}`),

  /**
   * Record service payment
   */
  recordServicePayment: (eventId: string, serviceId: string, data: { amount: number; method: string; transaction_ref?: string }) =>
    post<any>(`/user-events/${eventId}/services/${serviceId}/payment`, data),

  // ============================================================================
  // CHECKLIST
  // ============================================================================

  getAssignableMembers: (eventId: string) =>
    get<Array<{ id: string; first_name: string; last_name: string; full_name: string; avatar?: string; role: string }>>(`/user-events/${eventId}/assignable-members`),

  getChecklist: (eventId: string) =>
    get<{
      items: ChecklistItem[];
      summary: { total: number; completed: number; in_progress: number; pending: number; progress_percentage: number };
    }>(`/user-events/${eventId}/checklist`),

  addChecklistItem: (eventId: string, data: Partial<ChecklistItem>) =>
    post<ChecklistItem>(`/user-events/${eventId}/checklist`, data),

  updateChecklistItem: (eventId: string, itemId: string, data: Partial<ChecklistItem>) =>
    put<ChecklistItem>(`/user-events/${eventId}/checklist/${itemId}`, data),

  deleteChecklistItem: (eventId: string, itemId: string) =>
    del(`/user-events/${eventId}/checklist/${itemId}`),

  applyTemplate: (eventId: string, data: { template_id: string; clear_existing?: boolean }) =>
    post<{ added: number; template_name: string }>(`/user-events/${eventId}/checklist/from-template`, data),

  reorderChecklist: (eventId: string, data: { items: Array<{ id: string; display_order: number }> }) =>
    put<void>(`/user-events/${eventId}/checklist/reorder`, data),

  // ============================================================================
  // EXPENSES
  // ============================================================================

  /**
   * Get event expenses
   */
  getExpenses: (eventId: string, params?: { page?: number; limit?: number; category?: string; search?: string }) =>
    get<{
      expenses: Array<{
        id: string;
        category: string;
        description: string;
        amount: number;
        payment_method?: string;
        payment_reference?: string;
        vendor_name?: string;
        receipt_url?: string;
        expense_date: string;
        notes?: string;
        recorded_by_name?: string;
        recorded_by_id?: string;
        created_at: string;
      }>;
      summary: {
        total_expenses: number;
        category_breakdown: Array<{ category: string; total: number; count: number }>;
        count: number;
        currency: string;
      };
      pagination: PaginatedResponse<any>["pagination"];
    }>(`/user-events/${eventId}/expenses${buildQueryString(params)}`),

  /**
   * Add an expense
   */
  addExpense: (eventId: string, data: {
    category: string;
    description: string;
    amount: number;
    payment_method?: string;
    payment_reference?: string;
    vendor_name?: string;
    expense_date?: string;
    notes?: string;
    notify_committee?: boolean;
  }) => post<any>(`/user-events/${eventId}/expenses`, data),

  /**
   * Update an expense
   */
  updateExpense: (eventId: string, expenseId: string, data: Partial<{
    category: string;
    description: string;
    amount: number;
    payment_method?: string;
    payment_reference?: string;
    vendor_name?: string;
    expense_date?: string;
    notes?: string;
  }>) => put<any>(`/user-events/${eventId}/expenses/${expenseId}`, data),

  /**
   * Delete an expense
   */
  deleteExpense: (eventId: string, expenseId: string) =>
    del(`/user-events/${eventId}/expenses/${expenseId}`),

  /**
   * Get expense report
   */
  getExpenseReport: (eventId: string, params?: { date_from?: string; date_to?: string }) =>
    get<{
      expenses: Array<{ category: string; description: string; amount: number; vendor_name?: string; expense_date: string; recorded_by_name?: string }>;
      summary: { total_expenses: number; category_breakdown: Array<{ category: string; total: number; count: number }>; currency: string };
    }>(`/user-events/${eventId}/expenses/report${buildQueryString(params)}`),
};
