/**
 * Contributors API - User contributor address book & event contributors
 */

import { get, post, put, del, buildQueryString } from "./helpers";
import type { PaginatedResponse } from "./types";

// ============================================================================
// TYPES
// ============================================================================

export type WhatsAppAvailabilityStatus =
  | "available"
  | "unavailable"
  | "unknown"
  | "error"
  | "checking"
  | "invalid"
  // Newer state: API accepted the message, waiting for Meta's delivery
  // webhook before we can confirm the number is on WhatsApp. Rendered as
  // neutral (same as "unknown") — we never claim "WhatsApp" prematurely.
  | "pending"
  // Legacy values still returned by some endpoints — kept for compatibility.
  | "whatsapp"
  | "not_whatsapp"
  | "failed";


export interface WhatsAppAvailability {
  whatsapp_status: WhatsAppAvailabilityStatus;
  is_whatsapp: boolean | null;
  whatsapp_last_checked_at: string | null;
}

export interface UserContributor extends Partial<WhatsAppAvailability> {
  id: string;
  user_id: string;
  contributor_user_id?: string | null;
  name: string;
  /** Original address-book name when `name` has been overridden by a per-event display_name. */
  global_name?: string | null;
  email?: string | null;
  phone?: string | null;
  notes?: string | null;
  /** Default secondary phone for contribution notifications. Comms-only — never used to map a Nuru user. */
  secondary_phone?: string | null;
  /** WhatsApp availability for the secondary phone, if present. */
  secondary_whatsapp?: WhatsAppAvailability | null;
  /** Default notification routing applied when adding to an event. */
  notify_target?: ContributorNotifyTarget;
  created_at?: string;
  updated_at?: string;
}

/** A row returned by GET /user-contributors/my-contributions */
export interface MyContributionEvent {
  event_id: string;
  event_name: string;
  event_cover_image_url?: string | null;
  event_start_date?: string | null;
  event_location?: string | null;
  organizer_name?: string | null;
  event_contributor_id: string;
  currency: string;
  pledge_amount: number;
  total_paid: number;
  pending_amount: number;
  balance: number;
  last_payment_at?: string | null;
}

export type ContributorNotifyTarget = "primary" | "secondary" | "both";

export interface EventContributorSummary {
  id: string;
  event_id: string;
  contributor_id: string;
  contributor: UserContributor | null;
  /** Per-event override of the contributor's display name (null when same as global). */
  display_name?: string | null;
  /** The original address-book name, regardless of any per-event override. */
  global_name?: string | null;
  pledge_amount: number;
  total_paid: number;
  balance: number;
  notes?: string | null;
  currency?: string | null;
  /** Optional secondary phone notified for contribution events. NEVER used to map a Nuru user. */
  secondary_phone?: string | null;
  /** Which numbers receive notifications: primary (default), secondary, or both. */
  notify_target?: ContributorNotifyTarget;
  /** True if this contributor has a live (un-revoked) guest payment link. */
  has_share_link?: boolean;
  /** ISO timestamp the contributor last opened their /c/:token page, if any. */
  share_link_last_opened_at?: string | null;
  /** ISO timestamp we last sent the share-link SMS, if any. */
  share_link_sms_last_sent_at?: string | null;
  created_at?: string;
  updated_at?: string;
}


export interface ContributorPayment {
  id: string;
  amount: number;
  payment_method?: string;
  payment_reference?: string;
  created_at?: string;
}

export interface ContributorQueryParams {
  page?: number;
  limit?: number;
  search?: string;
  sort_by?: "name" | "created_at";
  sort_order?: "asc" | "desc";
}

export interface EventContributorQueryParams {
  page?: number;
  limit?: number;
  search?: string;
}

// ============================================================================
// USER CONTRIBUTORS (Address Book)
// ============================================================================

export const contributorsApi = {
  /** Get all contributors in user's address book */
  getAll: (params?: ContributorQueryParams) =>
    get<{
      contributors: UserContributor[];
      pagination: PaginatedResponse<UserContributor>["pagination"];
    }>(`/user-contributors/${buildQueryString(params)}`),

  /** Get a single contributor */
  getById: (contributorId: string) =>
    get<UserContributor>(`/user-contributors/${contributorId}`),

  /** Create a new contributor in address book */
  create: (data: { name: string; email?: string; phone?: string; notes?: string; secondary_phone?: string; notify_target?: ContributorNotifyTarget }) =>
    post<UserContributor>("/user-contributors/", data),

  /** Update a contributor */
  update: (contributorId: string, data: Partial<UserContributor>) =>
    put<UserContributor>(`/user-contributors/${contributorId}`, data),

  /** Delete a contributor from address book */
  delete: (contributorId: string) =>
    del(`/user-contributors/${contributorId}`),

  // ============================================================================
  // EVENT CONTRIBUTORS
  // ============================================================================

  /** Get contributors linked to an event */
  getEventContributors: (eventId: string, params?: EventContributorQueryParams) =>
    get<{
      event_contributors: EventContributorSummary[];
      summary: { total_pledged: number; total_paid: number; total_balance: number; count: number; currency?: string };
      pagination: PaginatedResponse<EventContributorSummary>["pagination"];
    }>(`/user-contributors/events/${eventId}/contributors${buildQueryString(params)}`),

  /** Add contributor to event (with optional inline creation) */
  addToEvent: (eventId: string, data: {
    contributor_id?: string;
    name?: string;
    email?: string;
    phone?: string;
    pledge_amount?: number;
    notes?: string;
    /** Optional second phone notified about contribution events. */
    secondary_phone?: string;
    /** Routing preference for SMS / WhatsApp / in-app. Defaults to "primary". */
    notify_target?: ContributorNotifyTarget;
  }) =>
    post<EventContributorSummary>(`/user-contributors/events/${eventId}/contributors`, data),

  /** Update event contributor (pledge amount, notes, secondary contact prefs) */
  updateEventContributor: (eventId: string, eventContributorId: string, data: {
    pledge_amount?: number;
    notes?: string;
    secondary_phone?: string | null;
    notify_target?: ContributorNotifyTarget;
    /** Per-event-only display name override. Empty string clears the override. */
    display_name?: string | null;
  }) =>
    put<EventContributorSummary>(`/user-contributors/events/${eventId}/contributors/${eventContributorId}`, data),

  /** Remove contributor from event */
  removeFromEvent: (eventId: string, eventContributorId: string) =>
    del(`/user-contributors/events/${eventId}/contributors/${eventContributorId}`),

  /** Bulk-remove multiple contributors from an event (or all). */
  bulkRemoveFromEvent: (
    eventId: string,
    payload: { ids?: string[]; all?: boolean },
  ) =>
    post<{ removed: number }>(
      `/user-contributors/events/${eventId}/contributors/bulk-remove`,
      payload,
    ),

  /** Record payment for an event contributor */
  recordPayment: (eventId: string, eventContributorId: string, data: {
    amount: number;
    payment_method?: string;
    payment_reference?: string;
  }) =>
    post<ContributorPayment>(`/user-contributors/events/${eventId}/contributors/${eventContributorId}/payments`, data),

  /** Get payment history for an event contributor */
  getPaymentHistory: (eventId: string, eventContributorId: string) =>
    get<{
      contributor: UserContributor | null;
      pledge_amount: number;
      total_paid: number;
      payments: ContributorPayment[];
    }>(`/user-contributors/events/${eventId}/contributors/${eventContributorId}/payments`),

  /** Send thank you SMS to an event contributor */
  sendThankYou: (eventId: string, eventContributorId: string, data: { custom_message?: string }) =>
    post<{ sent: boolean }>(`/user-contributors/events/${eventId}/contributors/${eventContributorId}/thank-you`, data),

  /**
   * Bulk add/update contributors to an event.
   *
   * The backend now processes large uploads asynchronously: it enqueues a
   * background job and returns immediately with a ``job_id``. Call
   * ``getImportJobStatus`` to poll progress and ``getImportJobErrors``
   * to fetch per-row errors once the job has finished.
   */
  bulkAddToEvent: (eventId: string, data: {
    contributors: { name: string; phone: string; amount: number }[];
    send_sms?: boolean;
    mode?: "targets" | "contributions";
    payment_method?: string;
  }) =>
    post<{
      job_id: string;
      status: "queued" | "processing" | "completed" | "failed" | "partially_completed";
      total_rows: number;
    }>(`/user-contributors/events/${eventId}/contributors/bulk`, data),

  /** Poll a contributor-import job for status & progress. */
  getImportJobStatus: (eventId: string, jobId: string) =>
    get<{
      job_id: string;
      status: "queued" | "processing" | "completed" | "failed" | "partially_completed";
      mode: "targets" | "contributions" | "resend";
      total_rows: number;
      processed_rows: number;
      successful_rows: number;
      failed_rows: number;
      error_message?: string | null;
      summary?: {
        inserted?: number;
        updated?: number;
        duplicates_in_file?: number;
        notified?: number;
        notify_failed?: number;
        notify_errors?: { row?: number; ec_id?: string; name?: string; phone?: string; errors: string[] }[];
      };
      started_at?: string | null;
      finished_at?: string | null;
      created_at?: string | null;
    }>(`/user-contributors/events/${eventId}/contributor-imports/${jobId}`),

  /** Get per-row errors for a finished contributor-import job. */
  getImportJobErrors: (eventId: string, jobId: string) =>
    get<{
      job_id: string;
      errors: { row: number; message: string }[];
    }>(`/user-contributors/events/${eventId}/contributor-imports/${jobId}/errors`),

  /** Queue a single-contributor "Target Notification" resend. */
  resendTargetNotification: (eventId: string, eventContributorId: string) =>
    post<{ job_id: string; status: string; total_rows: number }>(
      `/user-contributors/events/${eventId}/contributors/${eventContributorId}/resend-notification`,
      {},
    ),

  /** Queue a bulk "Target Notification" resend for selected contributors. */
  bulkResendTargetNotification: (eventId: string, eventContributorIds: string[]) =>
    post<{ job_id: string; status: string; total_rows: number }>(
      `/user-contributors/events/${eventId}/contributors/resend-notifications`,
      { event_contributor_ids: eventContributorIds },
    ),

  /** Get pending contributions awaiting creator confirmation */
  getPendingContributions: (eventId: string) =>
    get<{
      contributions: {
        id: string;
        contributor_name: string;
        contributor_phone?: string;
        amount: number;
        payment_method?: string;
        transaction_ref?: string;
        recorded_by?: string;
        created_at?: string;
        // Offline-claim audit fields (organiser/auditor view)
        payment_channel?: "mobile_money" | "bank" | null;
        provider_name?: string | null;
        provider_id?: string | null;
        payer_account?: string | null;
        receipt_image_url?: string | null;
        claim_submitted_at?: string | null;
      }[];
      count: number;
    }>(`/user-contributors/events/${eventId}/pending-contributions`),

  /** Get contributions recorded by the current committee member */
  getMyRecordedContributions: (eventId: string) =>
    get<{
      contributions: {
        id: string;
        contributor_name: string;
        contributor_phone?: string;
        amount: number;
        payment_method?: string;
        transaction_ref?: string;
        confirmation_status: string;
        confirmed_at?: string;
        created_at?: string;
      }[];
      count: number;
    }>(`/user-contributors/events/${eventId}/my-recorded-contributions`),

  /** Confirm one or more pending contributions */
  confirmContributions: (eventId: string, contributionIds: string[]) =>
    post<{ confirmed: number }>(`/user-contributors/events/${eventId}/confirm-contributions`, { contribution_ids: contributionIds }),

  /** Reject one or more pending contributions (deletes record + notifies contributor) */
  rejectContributions: (eventId: string, contributionIds: string[]) =>
    post<{ rejected: number }>(`/user-contributors/events/${eventId}/reject-contributions`, { contribution_ids: contributionIds }),

  /** Delete a specific transaction from payment history */
  deleteTransaction: (eventId: string, eventContributorId: string, paymentId: string) =>
    del(`/user-contributors/events/${eventId}/contributors/${eventContributorId}/payments/${paymentId}`),

  /** Get date-filtered contribution report */
  getContributionReport: (eventId: string, params?: { date_from?: string; date_to?: string }) =>
    get<{
      contributors: { name: string; phone?: string; pledged: number; paid: number; balance: number }[];
      full_summary: { total_pledged: number; total_paid: number; total_balance: number; count: number; currency?: string };
      filtered_summary: { total_paid: number; contributor_count: number };
      date_from?: string;
      date_to?: string;
      is_filtered: boolean;
    }>(`/user-contributors/events/${eventId}/contribution-report${buildQueryString(params)}`),

  /** Send bulk reminder SMS. Server auto-saves the customisation per (event, case_type). */
  sendBulkReminder: (eventId: string, data: {
    case_type: 'no_contribution' | 'partial' | 'completed' | 'not_pledged';
    message_template: string;
    payment_info?: string;
    contact_phone?: string;
    contributor_ids: string[];
  }) =>
    post<{
      // New async batch response
      batch_id?: string;
      queued?: number;
      skipped_self?: number;
      skipped_duplicate?: number;
      skipped_invalid_phone?: number | string[];
      mode?: 'queued' | 'inline';
      idempotent_replay?: boolean;
      // Legacy synchronous response (kept for backward compatibility)
      sent?: number;
      failed?: number;
      errors?: string[];
    }>(`/user-contributors/events/${eventId}/bulk-message`, data),

  /** Fetch saved per-event messaging customisations keyed by case_type. */
  getMessagingTemplates: (eventId: string) =>
    get<{
      templates: Partial<Record<'no_contribution' | 'partial' | 'completed' | 'not_pledged', {
        message_template: string | null;
        payment_info: string | null;
        contact_phone: string | null;
        updated_at: string | null;
      }>>;
    }>(`/user-contributors/events/${eventId}/messaging-templates`),

  /** Save (without sending) a per-event messaging customisation. */
  saveMessagingTemplate: (
    eventId: string,
    caseType: 'no_contribution' | 'partial' | 'completed' | 'not_pledged',
    data: { message_template?: string; payment_info?: string; contact_phone?: string },
  ) =>
    put<{
      case_type: string;
      message_template: string | null;
      payment_info: string | null;
      contact_phone: string | null;
    }>(`/user-contributors/events/${eventId}/messaging-templates/${caseType}`, data),

  // ============================================================================
  // SELF-CONTRIBUTE — events where the logged-in user is a contributor
  // ============================================================================

  /** Events where the current user is recorded as a contributor */
  getMyContributions: (params?: { search?: string }) =>
    get<{ events: MyContributionEvent[]; count: number }>(`/user-contributors/my-contributions${params?.search ? `?search=${encodeURIComponent(params.search)}` : ""}`),

  /** Submit a pending self-contribution; organiser approves/rejects later */
  selfContribute: (
    eventId: string,
    data: { amount: number; payment_reference?: string; note?: string },
  ) =>
    post<{ contribution_id: string; amount: number; status: 'pending' }>(
      `/user-contributors/events/${eventId}/self-contribute`,
      data,
    ),

  // ============================================================================
  // GUEST PAYMENT LINKS — host-side actions for the /c/:token flow
  // ============================================================================

  /**
   * Generate (or rotate) a share token for a single contributor.
   * The plain token is returned ONCE inside `url`; the server stores only the hash.
   */
  generateShareLink: (
    eventId: string,
    eventContributorId: string,
    data?: { regenerate?: boolean },
  ) =>
    post<{
      url: string;
      token: string;
      host: string;
      currency_code: string;
      expires_at: string | null;
      sms_supported: boolean;
    }>(
      `/user-contributors/events/${eventId}/contributors/${eventContributorId}/share-link`,
      data ?? {},
    ),

  /** Send the freshly-issued share link to the contributor by SMS (TZ for now). */
  sendShareLinkSms: (
    eventId: string,
    eventContributorId: string,
    data?: { custom_message?: string },
  ) =>
    post<{ sent: boolean; sms_supported?: boolean; sms_last_sent_at?: string | null }>(
      `/user-contributors/events/${eventId}/contributors/${eventContributorId}/send-share-sms`,
      data ?? {},
    ),

  /** Disable the contributor's share link so the URL stops working. */
  revokeShareLink: (eventId: string, eventContributorId: string) =>
    post<{ revoked: boolean }>(
      `/user-contributors/events/${eventId}/contributors/${eventContributorId}/revoke-share-link`,
      {},
    ),
};
