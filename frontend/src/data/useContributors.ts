/**
 * Data hooks for user contributors and event contributors
 * FIXED: Auto-pagination to load all contributors (not just first 50)
 * Uses initialLoad pattern to prevent skeleton re-renders.
 */
import { useState, useEffect, useCallback } from "react";
import { contributorsApi, UserContributor, EventContributorSummary, ContributorPayment } from "@/lib/api/contributors";
import { throwApiError } from "@/lib/api/showApiErrors";

// ============================================================================
// EVENT CONTRIBUTORS
// ============================================================================

const _eventContributorsCache = new Map<string, { contributors: EventContributorSummary[]; summary: any; pagination: any }>();

export const useEventContributors = (eventId: string | null) => {
  const cached = eventId ? _eventContributorsCache.get(eventId) : null;
  const [eventContributors, setEventContributors] = useState<EventContributorSummary[]>(cached?.contributors || []);
  const [summary, setSummary] = useState<any>(cached?.summary || null);
  const [loading, setLoading] = useState(!cached);
  const [error, setError] = useState<string | null>(null);
  const [pagination, setPagination] = useState<any>(cached?.pagination || null);

  const fetchEventContributors = useCallback(async (params?: { page?: number; limit?: number; search?: string }) => {
    if (!eventId) return;
    if (!_eventContributorsCache.has(eventId)) setLoading(true);
    try {
      // Fetch ALL event contributors in a single request.
      const response = await contributorsApi.getEventContributors(eventId, {
        ...params,
        page: 1,
        limit: 5000,
      });

      if (response.success) {
        const contributors = response.data.event_contributors;
        const backendSummary = response.data.summary || { total_pledged: 0, total_paid: 0, total_balance: 0, count: 0, currency: 'TZS' };

        const enrichedSummary = {
          ...backendSummary,
          total_balance: contributors.reduce((sum, c) => {
            const explicit = Number(c.balance ?? NaN);
            if (Number.isFinite(explicit)) return sum + Math.max(0, explicit);
            return sum + Math.max(0, (c.pledge_amount || 0) - (c.total_paid || 0));
          }, 0),
          count: contributors.length,
          pledged_count: contributors.filter(c => (c.pledge_amount || 0) > 0).length,
          paid_count: contributors.filter(c => (c.total_paid || 0) > 0).length,
        };

        _eventContributorsCache.set(eventId, { contributors, summary: enrichedSummary, pagination: response.data.pagination });
        setEventContributors(contributors);
        setSummary(enrichedSummary);
        setPagination(response.data.pagination);
      } else {
        setError(response.message || "Failed to fetch event contributors");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  }, [eventId]);

  useEffect(() => {
    if (eventId) fetchEventContributors();
  }, [fetchEventContributors, eventId]);

  const addToEvent = async (data: Parameters<typeof contributorsApi.addToEvent>[1]) => {
    if (!eventId) return null;
    try {
      const response = await contributorsApi.addToEvent(eventId, data);
      if (response.success) {
        await fetchEventContributors();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const updateEventContributor = async (ecId: string, data: { pledge_amount?: number; notes?: string; secondary_phone?: string | null; notify_target?: 'primary' | 'secondary' | 'both'; display_name?: string | null }) => {
    if (!eventId) return null;
    try {
      const response = await contributorsApi.updateEventContributor(eventId, ecId, data);
      if (response.success) {
        await fetchEventContributors();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const removeFromEvent = async (ecId: string) => {
    if (!eventId) return;
    try {
      const response = await contributorsApi.removeFromEvent(eventId, ecId);
      if (response.success) {
        await fetchEventContributors();
      } else {
        throwApiError(response);
      }
    } catch (err) {
      throw err;
    }
  };

  const recordPayment = async (ecId: string, data: { amount: number; payment_method?: string; payment_reference?: string }) => {
    if (!eventId) return null;
    try {
      const response = await contributorsApi.recordPayment(eventId, ecId, data);
      if (response.success) {
        await fetchEventContributors();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const getPaymentHistory = async (ecId: string) => {
    if (!eventId) return null;
    try {
      const response = await contributorsApi.getPaymentHistory(eventId, ecId);
      if (response.success) {
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  return {
    eventContributors,
    summary,
    loading,
    error,
    pagination,
    refetch: fetchEventContributors,
    addToEvent,
    updateEventContributor,
    removeFromEvent,
    recordPayment,
    getPaymentHistory,
  };
};
