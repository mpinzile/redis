/**
 * Universal QR scan resolver — single entry point that figures out what
 * a scanned code represents (ticket, guest, contribution receipt or link,
 * check-in access code, unknown) without mutating anything.
 *
 * The UI keeps using its existing result-card components — it just reads
 * the `route` discriminator on the response to pick which card variant
 * to render, and the `actions[]` list to know which follow-up endpoint
 * (if any) to call on user confirmation.
 */
import { post } from "./helpers";
import type { ApiResponse } from "./types";

export type ScanRoute =
  | "ticket"
  | "guest"
  | "contribution_receipt"
  | "contribution_pay"
  | "checkin_code"
  | "unknown";

export type ScanStatus = "ok" | "warning" | "error";

export interface ScanAction {
  label: string;
  method: "GET" | "POST";
  endpoint: string;
  body?: Record<string, unknown>;
}

export interface ScanEventBrief {
  id: string;
  name: string;
  start_date?: string | null;
  location?: string | null;
  cover_image?: string | null;
}

export interface ScanPerformer {
  id: string;
  full_name: string;
  avatar?: string | null;
}

export interface ScanResolveResponse {
  route: ScanRoute;
  status: ScanStatus;
  kind: string;
  name: string | null;
  code: string;
  event: ScanEventBrief | null;
  payload: Record<string, any> & {
    checked_in?: boolean;
    checked_in_at?: string | null;
    checked_in_by?: ScanPerformer | null;
    cross_event?: boolean;
    summary?: Record<string, any>;
    [k: string]: any;
  };
  actions: ScanAction[];
  reason?: string | null;
  message: string;
  scan_time: string;
}

export const scanApi = {
  /**
   * Resolve any QR payload. Pass `event_id` when the scanner is opened
   * inside a specific event — the response will then include a
   * "Check in" action for matching guests/tickets.
   */
  resolve: (input: {
    code: string;
    event_id?: string;
    client_scan_id?: string;
    device_ref?: string;
  }): Promise<ApiResponse<ScanResolveResponse>> =>
    post(`/scan/resolve`, input),
};

export default scanApi;
