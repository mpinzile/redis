/**
 * Events Data Hooks
 * All hooks use initialLoad ref pattern to prevent skeleton re-renders on background refetch.
 */

import { useState, useEffect, useCallback, useRef } from "react";
import { eventsApi, EventQueryParams, GuestQueryParams, ContributionQueryParams } from "@/lib/api/events";
import { throwApiError } from "@/lib/api/showApiErrors";
import type { 
  Event, 
  EventGuest, 
  CommitteeMember, 
  EventContribution, 
  EventScheduleItem,
  EventBudgetItem 
} from "@/lib/api/types";

// Module-level cache for events list
let _eventsCache: Event[] = [];
let _eventsPaginationCache: any = null;
let _eventsHasLoaded = false;

export const useEvents = (initialParams?: EventQueryParams) => {
  const hasSearch = !!initialParams?.search;
  const [events, setEvents] = useState<Event[]>(hasSearch ? [] : _eventsCache);
  const [loading, setLoading] = useState(hasSearch ? true : !_eventsHasLoaded);
  const [error, setError] = useState<string | null>(null);
  const [pagination, setPagination] = useState<any>(hasSearch ? null : _eventsPaginationCache);

  const fetchEvents = useCallback(async (params?: EventQueryParams) => {
    const effective = params || initialParams;
    const isSearch = !!effective?.search;
    if (!_eventsHasLoaded || isSearch) setLoading(true);
    setError(null);
    try {
      const response = await eventsApi.getAll(effective);
      if (response.success) {
        if (!isSearch) {
          _eventsCache = response.data.events;
          _eventsPaginationCache = response.data.pagination;
          _eventsHasLoaded = true;
        }
        setEvents(response.data.events);
        setPagination(response.data.pagination);
      } else {
        setError(response.message || "Failed to fetch events");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  }, [initialParams]);

  useEffect(() => {
    fetchEvents();
  }, [fetchEvents]);

  return { events, loading, error, pagination, refetch: fetchEvents };
};

// ============================================================================
// SINGLE EVENT (with initialLoad ref)
// ============================================================================

// Module-level cache for single events
const _eventCache = new Map<string, Event>();
const _eventInflight = new Map<string, Promise<void>>();

/**
 * Hover-prefetch: warm the cache for a single event so navigation feels instant.
 * Safe to call repeatedly — dedupes inflight requests and skips when cached.
 */
export const prefetchEvent = (eventId: string): void => {
  if (!eventId || _eventCache.has(eventId) || _eventInflight.has(eventId)) return;
  const p = (async () => {
    try {
      const response = await eventsApi.getById(eventId);
      if (response.success) {
        _eventCache.set(eventId, response.data);
        try {
          const inlinePerms = (response.data as any)?.permissions;
          if (inlinePerms) {
            const { seedEventPermissions } = await import('@/hooks/useEventPermissions');
            seedEventPermissions(eventId, inlinePerms);
          }
        } catch { /* non-fatal */ }
      }
    } catch { /* non-fatal */ }
    finally { _eventInflight.delete(eventId); }
  })();
  _eventInflight.set(eventId, p);
};

export const useEvent = (eventId: string | null) => {
  const cached = eventId ? _eventCache.get(eventId) : null;
  const [event, setEvent] = useState<Event | null>(cached || null);
  const [loading, setLoading] = useState(!cached);
  const [error, setError] = useState<string | null>(null);

  const fetchEvent = useCallback(async () => {
    if (!eventId) return;
    if (!_eventCache.has(eventId)) setLoading(true);
    try {
      const response = await eventsApi.getById(eventId);
      if (response.success) {
        _eventCache.set(eventId, response.data);
        setEvent(response.data);
        // Seed the permissions cache if the essential payload included them.
        // This avoids a second round-trip from useEventPermissions.
        try {
          const inlinePerms = (response.data as any)?.permissions;
          if (inlinePerms) {
            const { seedEventPermissions } = await import('@/hooks/useEventPermissions');
            seedEventPermissions(eventId, inlinePerms);
          }
        } catch { /* non-fatal */ }
      } else {
        setError(response.message || "Failed to fetch event");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  }, [eventId]);

  useEffect(() => {
    if (eventId) fetchEvent();
  }, [fetchEvent, eventId]);

  return { event, loading, error, refetch: fetchEvent };
};

// ============================================================================
// EVENT GUESTS (with initialLoad ref)
// ============================================================================

const _guestsCache = new Map<string, { guests: EventGuest[]; summary: any; pagination: any }>();

export const useEventGuests = (eventId: string | null, initialParams?: GuestQueryParams) => {
  const cached = eventId ? _guestsCache.get(eventId) : null;
  const [guests, setGuests] = useState<EventGuest[]>(cached?.guests || []);
  const [summary, setSummary] = useState<any>(cached?.summary || null);
  const [loading, setLoading] = useState(!cached);
  const [error, setError] = useState<string | null>(null);
  const [pagination, setPagination] = useState<any>(cached?.pagination || null);

  const fetchGuests = useCallback(async (params?: GuestQueryParams) => {
    if (!eventId) return;
    if (!_guestsCache.has(eventId)) setLoading(true);
    try {
      const merged: GuestQueryParams = { ...(initialParams || {}), ...(params || {}) };
      // If the caller has not explicitly paginated, auto-page through every
      // invited guest so RSVP reports/exports never silently truncate at 50.
      // The backend enforces a max page size of 100 — we respect it and loop.
      if (merged.page == null) {
        const pageSize = Math.min(merged.limit ?? 100, 100);
        let page = 1;
        let allGuests: EventGuest[] = [];
        let lastSummary: any = null;
        let lastPagination: any = null;
        while (true) {
          const res = await eventsApi.getGuests(eventId, { ...merged, page, limit: pageSize });
          if (!res.success) {
            setError(res.message || "Failed to fetch guests");
            break;
          }
          allGuests = allGuests.concat(res.data.guests || []);
          lastSummary = res.data.summary;
          lastPagination = res.data.pagination;
          const totalPages = res.data.pagination?.total_pages ?? 1;
          if (page >= totalPages) break;
          page++;
          // Hard safety cap so a mis-reported total never hangs the UI.
          if (page > 200) break;
        }
        // Deduplicate by id (cross-page collisions if records shift between fetches)
        // and sort alphabetically by name so the list reads naturally.
        const seen = new Set<string>();
        const deduped: EventGuest[] = [];
        for (const g of allGuests) {
          if (!g || seen.has(g.id)) continue;
          seen.add(g.id);
          deduped.push(g);
        }
        deduped.sort((a, b) => (a.name || '').localeCompare(b.name || '', undefined, { sensitivity: 'base' }));
        _guestsCache.set(eventId, { guests: deduped, summary: lastSummary, pagination: lastPagination });
        setGuests(deduped);
        setSummary(lastSummary);
        setPagination(lastPagination);
      } else {
        const response = await eventsApi.getGuests(eventId, merged);
        if (response.success) {
          const seen = new Set<string>();
          const deduped = (response.data.guests || []).filter((g: EventGuest) => {
            if (!g || seen.has(g.id)) return false;
            seen.add(g.id);
            return true;
          }).sort((a: EventGuest, b: EventGuest) => (a.name || '').localeCompare(b.name || '', undefined, { sensitivity: 'base' }));
          _guestsCache.set(eventId, { guests: deduped, summary: response.data.summary, pagination: response.data.pagination });
          setGuests(deduped);
          setSummary(response.data.summary);
          setPagination(response.data.pagination);
        } else {
          setError(response.message || "Failed to fetch guests");
        }
      }

    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  }, [eventId, initialParams]);


  useEffect(() => {
    if (eventId) fetchGuests();
  }, [fetchGuests, eventId]);

  const addGuest = async (data: Partial<EventGuest>) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.addGuest(eventId, data);
      if (response.success) {
        await fetchGuests();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const updateGuest = async (guestId: string, data: Partial<EventGuest>) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.updateGuest(eventId, guestId, data);
      if (response.success) {
        await fetchGuests();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const deleteGuest = async (guestId: string) => {
    if (!eventId) return;
    try {
      const response = await eventsApi.deleteGuest(eventId, guestId);
      if (response.success) {
        await fetchGuests();
      } else {
        throwApiError(response);
      }
    } catch (err) {
      throw err;
    }
  };

  const sendInvitation = async (guestId: string, method: "email" | "sms" | "whatsapp" | "whatsapp_text", customMessage?: string) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.sendInvitation(eventId, guestId, { method, custom_message: customMessage });
      if (response.success) {
        await fetchGuests();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const checkinGuest = async (guestId: string) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.checkinGuest(eventId, guestId);
      if (response.success) {
        await fetchGuests();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const undoCheckinGuest = async (guestId: string) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.undoCheckin(eventId, guestId);
      if (response.success) {
        await fetchGuests();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  return {
    guests,
    summary,
    loading,
    error,
    pagination,
    refetch: fetchGuests,
    addGuest,
    updateGuest,
    deleteGuest,
    sendInvitation,
    checkinGuest,
    undoCheckinGuest,
  };
};

// ============================================================================
// EVENT COMMITTEE (with initialLoad ref)
// ============================================================================

const _committeeCache = new Map<string, CommitteeMember[]>();

export const useEventCommittee = (eventId: string | null) => {
  const cached = eventId ? _committeeCache.get(eventId) : null;
  const [members, setMembers] = useState<CommitteeMember[]>(cached || []);
  const [loading, setLoading] = useState(!cached);
  const [error, setError] = useState<string | null>(null);

  const fetchCommittee = useCallback(async () => {
    if (!eventId) return;
    if (!_committeeCache.has(eventId)) setLoading(true);
    try {
      const response = await eventsApi.getCommittee(eventId);
      if (response.success) {
        _committeeCache.set(eventId, response.data);
        setMembers(response.data);
      } else {
        setError(response.message || "Failed to fetch committee");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  }, [eventId]);

  useEffect(() => {
    if (eventId) fetchCommittee();
  }, [fetchCommittee, eventId]);

  const addMember = async (data: Parameters<typeof eventsApi.addCommitteeMember>[1]) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.addCommitteeMember(eventId, data);
      if (response.success) {
        await fetchCommittee();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const updateMember = async (memberId: string, data: Partial<CommitteeMember>) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.updateCommitteeMember(eventId, memberId, data);
      if (response.success) {
        await fetchCommittee();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const removeMember = async (memberId: string) => {
    if (!eventId) return;
    try {
      const response = await eventsApi.removeCommitteeMember(eventId, memberId);
      if (response.success) {
        await fetchCommittee();
      } else {
        throwApiError(response);
      }
    } catch (err) {
      throw err;
    }
  };

  return { members, loading, error, refetch: fetchCommittee, addMember, updateMember, removeMember };
};

// ============================================================================
// EVENT CONTRIBUTIONS (with initialLoad ref)
// ============================================================================

const _contributionsCache = new Map<string, { contributions: EventContribution[]; summary: any; pagination: any }>();

export const useEventContributions = (eventId: string | null, initialParams?: ContributionQueryParams) => {
  const cached = eventId ? _contributionsCache.get(eventId) : null;
  const [contributions, setContributions] = useState<EventContribution[]>(cached?.contributions || []);
  const [summary, setSummary] = useState<any>(cached?.summary || null);
  const [loading, setLoading] = useState(!cached);
  const [error, setError] = useState<string | null>(null);
  const [pagination, setPagination] = useState<any>(cached?.pagination || null);

  const fetchContributions = useCallback(async (params?: ContributionQueryParams) => {
    if (!eventId) return;
    if (!_contributionsCache.has(eventId)) setLoading(true);
    try {
      const merged = { ...(initialParams || {}), ...(params || {}) } as ContributionQueryParams;
      // Auto-page when caller hasn't specified pagination, so reports never truncate.
      if ((merged as any).page == null) {
        const pageSize = Math.min((merged as any).limit ?? 100, 100);
        let page = 1;
        let all: EventContribution[] = [];
        let lastSummary: any = null;
        let lastPagination: any = null;
        while (true) {
          const res = await eventsApi.getContributions(eventId, { ...merged, page, limit: pageSize } as any);
          if (!res.success) {
            setError(res.message || 'Failed to fetch contributions');
            break;
          }
          all = all.concat(res.data.contributions || []);
          lastSummary = res.data.summary;
          lastPagination = res.data.pagination;
          const totalPages = res.data.pagination?.total_pages ?? 1;
          if (page >= totalPages) break;
          page++;
          if (page > 200) break;
        }
        const seen = new Set<string>();
        const deduped = all.filter(c => {
          if (!c || seen.has(c.id)) return false;
          seen.add(c.id);
          return true;
        }).sort((a, b) => (a.contributor_name || '').localeCompare(b.contributor_name || '', undefined, { sensitivity: 'base' }));
        _contributionsCache.set(eventId, { contributions: deduped, summary: lastSummary, pagination: lastPagination });
        setContributions(deduped);
        setSummary(lastSummary);
        setPagination(lastPagination);
      } else {
        const response = await eventsApi.getContributions(eventId, merged);
        if (response.success) {
          const seen = new Set<string>();
          const deduped = (response.data.contributions || []).filter((c: EventContribution) => {
            if (!c || seen.has(c.id)) return false;
            seen.add(c.id);
            return true;
          }).sort((a: EventContribution, b: EventContribution) => (a.contributor_name || '').localeCompare(b.contributor_name || '', undefined, { sensitivity: 'base' }));
          _contributionsCache.set(eventId, { contributions: deduped, summary: response.data.summary, pagination: response.data.pagination });
          setContributions(deduped);
          setSummary(response.data.summary);
          setPagination(response.data.pagination);
        } else {
          setError(response.message || "Failed to fetch contributions");
        }
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  }, [eventId, initialParams]);


  useEffect(() => {
    if (eventId) fetchContributions();
  }, [fetchContributions, eventId]);

  const addContribution = async (data: Partial<EventContribution>) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.addContribution(eventId, data);
      if (response.success) {
        await fetchContributions();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const updateContribution = async (contributionId: string, data: Partial<EventContribution>) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.updateContribution(eventId, contributionId, data);
      if (response.success) {
        await fetchContributions();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const deleteContribution = async (contributionId: string) => {
    if (!eventId) return;
    try {
      const response = await eventsApi.deleteContribution(eventId, contributionId);
      if (response.success) {
        await fetchContributions();
      } else {
        throwApiError(response);
      }
    } catch (err) {
      throw err;
    }
  };

  const sendThankYou = async (contributionId: string, method: "email" | "sms" | "whatsapp", customMessage?: string) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.sendThankYou(eventId, contributionId, { method, custom_message: customMessage });
      if (response.success) {
        await fetchContributions();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  return { contributions, summary, loading, error, pagination, refetch: fetchContributions, addContribution, updateContribution, deleteContribution, sendThankYou };
};

// ============================================================================
// EVENT SCHEDULE (with initialLoad ref)
// ============================================================================

const _scheduleCache = new Map<string, EventScheduleItem[]>();

export const useEventSchedule = (eventId: string | null) => {
  const cached = eventId ? _scheduleCache.get(eventId) : null;
  const [schedule, setSchedule] = useState<EventScheduleItem[]>(cached || []);
  const [loading, setLoading] = useState(!cached);
  const [error, setError] = useState<string | null>(null);

  const fetchSchedule = useCallback(async () => {
    if (!eventId) return;
    if (!_scheduleCache.has(eventId)) setLoading(true);
    setError(null);
    try {
      const response = await eventsApi.getSchedule(eventId);
      if (response.success) {
        _scheduleCache.set(eventId, response.data);
        setSchedule(response.data);
      } else {
        setError(response.message || "Failed to fetch schedule");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  }, [eventId]);

  useEffect(() => {
    if (eventId) fetchSchedule();
  }, [fetchSchedule, eventId]);

  const addItem = async (data: Partial<EventScheduleItem>) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.addScheduleItem(eventId, data);
      if (response.success) {
        await fetchSchedule();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const updateItem = async (itemId: string, data: Partial<EventScheduleItem>) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.updateScheduleItem(eventId, itemId, data);
      if (response.success) {
        await fetchSchedule();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const deleteItem = async (itemId: string) => {
    if (!eventId) return;
    try {
      const response = await eventsApi.deleteScheduleItem(eventId, itemId);
      if (response.success) {
        await fetchSchedule();
      } else {
        throwApiError(response);
      }
    } catch (err) {
      throw err;
    }
  };

  return { schedule, loading, error, refetch: fetchSchedule, addItem, updateItem, deleteItem };
};

// ============================================================================
// EVENT BUDGET (with initialLoad ref)
// ============================================================================

const _budgetCache = new Map<string, { items: EventBudgetItem[]; summary: any }>();

export const useEventBudget = (eventId: string | null) => {
  const cached = eventId ? _budgetCache.get(eventId) : null;
  const [items, setItems] = useState<EventBudgetItem[]>(cached?.items || []);
  const [summary, setSummary] = useState<any>(cached?.summary || null);
  const [loading, setLoading] = useState(!cached);
  const [error, setError] = useState<string | null>(null);
  const initialLoadDone = useRef(!!cached);

  const fetchBudget = useCallback(async () => {
    if (!eventId) return;
    if (!initialLoadDone.current) setLoading(true);
    setError(null);
    try {
      const response = await eventsApi.getBudget(eventId);
      if (response.success) {
        _budgetCache.set(eventId, { items: response.data.items, summary: response.data.summary });
        setItems(response.data.items);
        setSummary(response.data.summary);
      } else {
        setError(response.message || "Failed to fetch budget");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
      initialLoadDone.current = true;
    }
  }, [eventId]);

  useEffect(() => {
    if (eventId) fetchBudget();
  }, [fetchBudget, eventId]);

  const addItem = async (data: Partial<EventBudgetItem>) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.addBudgetItem(eventId, data);
      if (response.success) {
        await fetchBudget();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const updateItem = async (itemId: string, data: Partial<EventBudgetItem>) => {
    if (!eventId) return null;
    try {
      const response = await eventsApi.updateBudgetItem(eventId, itemId, data);
      if (response.success) {
        await fetchBudget();
        return response.data;
      }
      throwApiError(response);
    } catch (err) {
      throw err;
    }
  };

  const deleteItem = async (itemId: string) => {
    if (!eventId) return;
    try {
      const response = await eventsApi.deleteBudgetItem(eventId, itemId);
      if (response.success) {
        await fetchBudget();
      } else {
        throwApiError(response);
      }
    } catch (err) {
      throw err;
    }
  };

  return { items, summary, loading, error, refetch: fetchBudget, addItem, updateItem, deleteItem };
};

// ============================================================================
// DELETE EVENT
// ============================================================================

export const useDeleteEvent = () => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const deleteEvent = async (eventId: string) => {
    setLoading(true);
    setError(null);
    try {
      const response = await eventsApi.delete(eventId);
      if (!response.success) {
        throwApiError(response, "Failed to delete event");
      }
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
      throw err;
    } finally {
      setLoading(false);
    }
  };

  return { deleteEvent, loading, error };
};
