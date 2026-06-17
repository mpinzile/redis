/**
 * WhatsApp Logs API
 * -----------------
 * Backend records every outgoing WhatsApp attempt in `wa_message_logs`.
 * These helpers power the user-facing WhatsApp Logs dashboard so silent
 * delivery failures, fallback SMS attempts, and per-event activity are
 * all visible.
 */
import { get, post, del, buildQueryString } from "./helpers";
import type { ApiResponse, PaginatedResponse } from "./types";

export type WaLogStatus =
  | "queued" | "sent" | "delivered" | "read"
  | "failed" | "rejected" | "pending" | "unknown";

export interface WaLog {
  id: string;
  recipient_phone: string;
  recipient_name: string | null;
  normalized_phone: string | null;
  user_id: string | null;
  event_id: string | null;
  event_name_snapshot: string | null;
  recipient_type: string | null;
  recipient_id: string | null;
  message_purpose: string | null;
  source_module: string | null;
  related_entity_type: string | null;
  related_entity_id: string | null;
  whatsapp_available: boolean | null;
  category: string;
  action: string | null;
  template_name: string | null;
  message_type: string;
  language: string | null;
  direction: string;
  summary: string | null;
  media_url: string | null;
  media_type: string | null;
  provider: string;
  provider_message_id: string | null;
  status: WaLogStatus;
  error_code: string | null;
  error_message: string | null;
  error_title: string | null;
  fbtrace_id: string | null;
  failure_reason: string | null;
  retry_count: number;
  parent_log_id: string | null;
  fallback_channel: string | null;
  fallback_attempted: boolean;
  fallback_status: string | null;
  fallback_provider: string | null;
  fallback_message_id: string | null;
  fallback_error: string | null;
  fallback_sent_at: string | null;
  queued_at: string | null;
  sent_at: string | null;
  delivered_at: string | null;
  read_at: string | null;
  failed_at: string | null;
  last_status_at: string | null;
  deleted_at: string | null;
  created_at: string | null;
  updated_at: string | null;
  retryable: boolean;
}

export interface WaLogDetail extends WaLog {
  request_payload: any;
  response_payload: any;
  webhook_payload: any;
  error_details: any;
  history: WaLog[];
}

export interface WaLogQuery {
  page?: number;
  limit?: number;
  status?: string;
  category?: string;
  message_type?: string;
  template_name?: string;
  event_id?: string;
  recipient?: string;
  q?: string;
  date_from?: string;
  date_to?: string;
  message_purpose?: string;
  recipient_type?: string;
  whatsapp_available?: "true" | "false" | "unknown" | "";
  source_module?: string;
  error_code?: string;
  fallback_status?: string;
  with_deleted?: 0 | 1;
}

export interface WaEventOption { event_id: string; event_name: string }

export function listWhatsappLogs(params: WaLogQuery = {}): Promise<PaginatedResponse<WaLog>> {
  return get<WaLog[]>(`/whatsapp/logs${buildQueryString(params)}`) as unknown as Promise<PaginatedResponse<WaLog>>;
}
export function getWhatsappLogStats(
  daysOrParams: number | (WaLogQuery & { days?: number }) = 7,
): Promise<ApiResponse<Record<string, number>>> {
  const params = typeof daysOrParams === "number" ? { days: daysOrParams } : daysOrParams;
  return get<Record<string, number>>(`/whatsapp/logs/stats${buildQueryString(params)}`);
}
export function getWhatsappLog(id: string): Promise<ApiResponse<WaLogDetail>> {
  return get<WaLogDetail>(`/whatsapp/logs/${id}`);
}
export function resendWhatsappLog(id: string): Promise<ApiResponse<WaLog>> {
  return post<WaLog>(`/whatsapp/logs/${id}/resend`, {});
}
export interface WaBulkResendResult {
  queued: number;
  skipped: number;
  failures: { id: string; reason: string }[];
}
export function bulkResendWhatsappLogs(ids: string[]): Promise<ApiResponse<WaBulkResendResult>> {
  return post<WaBulkResendResult>(`/whatsapp/logs/bulk-resend`, { ids });
}
export function deleteWhatsappLog(id: string): Promise<ApiResponse<WaLog>> {
  return del<WaLog>(`/whatsapp/logs/${id}`);
}
export function bulkDeleteWhatsappLogs(ids: string[]): Promise<ApiResponse<{ deleted: number }>> {
  return post<{ deleted: number }>(`/whatsapp/logs/bulk-delete`, { ids });
}
export function restoreWhatsappLog(id: string): Promise<ApiResponse<WaLog>> {
  return post<WaLog>(`/whatsapp/logs/${id}/restore`, {});
}
export function listWhatsappLogEvents(): Promise<ApiResponse<WaEventOption[]>> {
  return get<WaEventOption[]>(`/whatsapp/logs/events`);
}
export function listWhatsappLogPurposes(): Promise<ApiResponse<string[]>> {
  return get<string[]>(`/whatsapp/logs/purposes`);
}
