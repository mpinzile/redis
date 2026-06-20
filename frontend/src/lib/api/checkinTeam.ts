/**
 * Check-In Team API — manage the people authorized to scan guests/tickets
 * for a specific event without sharing the organizer's account.
 */
import { get, post, del } from "./helpers";
import type { ApiResponse } from "./types";

export interface CheckinTeamMember {
  id: string;
  user: {
    id: string;
    first_name?: string;
    last_name?: string;
    full_name?: string;
    email?: string;
    phone?: string | null;
    avatar?: string | null;
  };
  added_by?: { id?: string; full_name?: string; avatar?: string | null } | null;
  added_at?: string | null;
}

export interface CheckinCode {
  id: string;
  prefix: string;            // e.g. NRU-AB12-••••
  status: "active" | "revoked" | "expired";
  created_at?: string | null;
  expires_at?: string | null;
  code?: string;             // ONLY present at generation time
}

export interface CheckinTeamPermissions {
  can_manage: boolean;
  can_scan: boolean;
}

export interface CheckinTeamResponse {
  members: CheckinTeamMember[];
  code: CheckinCode | null;
  permissions?: CheckinTeamPermissions;
}

export interface CheckinLogEntry {
  kind: "guest" | "ticket";
  id: string;
  name: string;
  ref: string;
  checked_in_at: string | null;
  checked_in_by: { id: string; full_name: string; avatar?: string | null } | null;
  device_ref?: string | null;
}

export interface CheckinLogResponse {
  entries: CheckinLogEntry[];
  total: number;
}

export const checkinTeamApi = {
  list: (eventId: string): Promise<ApiResponse<CheckinTeamResponse>> =>
    get(`/user-events/${eventId}/checkin-team`),

  addMember: (eventId: string, userId: string): Promise<ApiResponse<{ id: string }>> =>
    post(`/user-events/${eventId}/checkin-team`, { user_id: userId }),

  removeMember: (eventId: string, memberId: string): Promise<ApiResponse<unknown>> =>
    del(`/user-events/${eventId}/checkin-team/${memberId}`),

  generateCode: (eventId: string): Promise<ApiResponse<CheckinCode>> =>
    post(`/user-events/${eventId}/checkin-code/generate`, {}),

  revokeCode: (eventId: string): Promise<ApiResponse<{ revoked: number }>> =>
    post(`/user-events/${eventId}/checkin-code/revoke`, {}),

  revealCode: (eventId: string, password: string): Promise<ApiResponse<CheckinCode>> =>
    post(`/user-events/${eventId}/checkin-code/reveal`, { password }),

  log: (eventId: string, limit = 100): Promise<ApiResponse<CheckinLogResponse>> =>
    get(`/user-events/${eventId}/checkin-log?limit=${limit}`),
};

export default checkinTeamApi;
