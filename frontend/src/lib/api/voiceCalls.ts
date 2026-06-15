/**
 * Voice Calls API — Nuru Voice Assistant / Smart RSVP Calls
 * Wraps the backend /voice-calls/* endpoints (Phase 3/4 of nuru_voice.md).
 * Uses the regular user token; the backend grants admin-wide access when
 * the current user has `is_admin`.
 */
import type { ApiResponse } from "./types";
import { get, post, patch, del, buildQueryString } from "./helpers";

export type VoicePurpose =
  | "rsvp"
  | "contribution"
  | "verification"
  | "committee"
  | "vendor"
  | "feedback"
  | "general";

export type CampaignStatus =
  | "draft"
  | "queued"
  | "running"
  | "paused"
  | "completed"
  | "cancelled";

export type JobStatus =
  | "pending"
  | "queued"
  | "in_progress"
  | "completed"
  | "failed"
  | "no_answer"
  | "busy"
  | "opted_out"
  | "blocked"
  | "cancelled";

export interface VoiceCampaign {
  id: string;
  event_id: string | null;
  owner_id: string | null;
  purpose: VoicePurpose;
  language: string;
  status: CampaignStatus;
  title: string | null;
  notes: string | null;
  estimated_cost_usd: number | null;
  started_at: string | null;
  completed_at: string | null;
  created_at: string;
  updated_at: string;
  counts: Record<string, number>;
}

export interface VoiceCallJob {
  id: string;
  campaign_id: string;
  recipient_type: string;
  recipient_ref_id: string | null;
  recipient_name: string;
  phone_e164: string;
  country: string | null;
  timezone: string | null;
  language: string | null;
  status: JobStatus;
  block_reason: string | null;
  attempt: number;
  max_attempts: number;
  scheduled_at: string | null;
  next_retry_at: string | null;
  last_called_at: string | null;
  ai_outcome: string | null;
  ai_confidence: number | null;
  summary: string | null;
  extra: Record<string, unknown> | null;
  created_at: string;
  updated_at: string;
}

export interface VoiceCallLog {
  id: string;
  job_id: string;
  provider: string;
  provider_call_sid: string | null;
  status: string;
  end_reason: string | null;
  started_at: string | null;
  answered_at: string | null;
  ended_at: string | null;
  duration_seconds: number;
  cost_estimate_usd: number | null;
  recording_url: string | null;
  transcript: string | null;
  summary: string | null;
  ai_outcome: string | null;
  ai_confidence: number | null;
  ai_tool_calls: unknown;
  error_code: string | null;
  error_message: string | null;
  created_at: string;
}

export interface VoiceOptOut {
  id: string;
  phone_e164: string;
  reason: string | null;
  source: string;
  added_by_user_id: string | null;
  created_at: string;
}

export interface JobRecipientInput {
  recipient_type?: string;
  recipient_ref_id?: string | null;
  recipient_name?: string;
  phone: string;
  language?: string | null;
  timezone?: string | null;
  scheduled_at?: string | null;
  max_attempts?: number | null;
}

export interface CampaignCreateInput {
  event_id?: string | null;
  purpose?: VoicePurpose;
  language?: string;
  title?: string | null;
  notes?: string | null;
}

export interface CampaignUpdateInput {
  title?: string | null;
  notes?: string | null;
  language?: string;
  purpose?: VoicePurpose;
  status?: CampaignStatus;
}

export interface Pagination {
  page: number;
  page_size: number;
  total_items: number;
  total_pages: number;
}

type Paged<T> = ApiResponse<T[]> & { pagination?: Pagination };

export const voiceCallsApi = {
  // Campaigns
  listCampaigns(params?: {
    event_id?: string;
    status?: CampaignStatus;
    page?: number;
    page_size?: number;
  }) {
    return get<VoiceCampaign[]>(
      `/voice-calls/campaigns${buildQueryString(params)}`,
    ) as Promise<Paged<VoiceCampaign>>;
  },
  getCampaign(id: string) {
    return get<VoiceCampaign>(`/voice-calls/campaigns/${id}`);
  },
  createCampaign(payload: CampaignCreateInput) {
    return post<VoiceCampaign>("/voice-calls/campaigns", payload);
  },
  updateCampaign(id: string, payload: CampaignUpdateInput) {
    return patch<VoiceCampaign>(`/voice-calls/campaigns/${id}`, payload);
  },
  deleteCampaign(id: string) {
    return del<null>(`/voice-calls/campaigns/${id}`);
  },
  startCampaign(id: string) {
    return post<VoiceCampaign>(`/voice-calls/campaigns/${id}/start`);
  },
  pauseCampaign(id: string) {
    return post<VoiceCampaign>(`/voice-calls/campaigns/${id}/pause`);
  },
  cancelCampaign(id: string) {
    return post<VoiceCampaign>(`/voice-calls/campaigns/${id}/cancel`);
  },

  // Jobs
  listJobs(campaignId: string, params?: {
    status?: JobStatus;
    page?: number;
    page_size?: number;
  }) {
    return get<VoiceCallJob[]>(
      `/voice-calls/campaigns/${campaignId}/jobs${buildQueryString(params)}`,
    ) as Promise<Paged<VoiceCallJob>>;
  },
  addJobs(campaignId: string, recipients: JobRecipientInput[], enforce_hours = true) {
    return post<{ accepted: VoiceCallJob[]; rejected: unknown[] }>(
      `/voice-calls/campaigns/${campaignId}/jobs`,
      { recipients, enforce_hours },
    );
  },
  getJob(jobId: string) {
    return get<{ job: VoiceCallJob; logs: VoiceCallLog[] }>(
      `/voice-calls/jobs/${jobId}`,
    );
  },
  retryJob(jobId: string) {
    return post<VoiceCallJob>(`/voice-calls/jobs/${jobId}/retry`);
  },
  placeCall(jobId: string) {
    return post<{ job: VoiceCallJob; log: VoiceCallLog }>(
      `/voice-calls/jobs/${jobId}/place-call`,
    );
  },

  // Logs
  listLogs(jobId: string) {
    return get<VoiceCallLog[]>(`/voice-calls/logs/${jobId}`);
  },

  // Opt-outs
  listOptOuts(params?: { page?: number; page_size?: number; q?: string }) {
    return get<VoiceOptOut[]>(
      `/voice-calls/opt-outs${buildQueryString(params)}`,
    ) as Promise<Paged<VoiceOptOut>>;
  },
  addOptOut(phone: string, reason?: string, source: "organiser" | "admin" | "recipient" | "system" = "organiser") {
    return post<VoiceOptOut>("/voice-calls/opt-outs", { phone, reason, source });
  },
  removeOptOut(phone: string) {
    return del<null>(`/voice-calls/opt-outs/${encodeURIComponent(phone)}`);
  },

  // Twilio health
  twilioHealth() {
    return get<{ missing: string[]; webhook_url: string; stream_url: string }>(
      "/voice-calls/twilio/health",
    );
  },
};
