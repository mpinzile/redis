/**
 * Guest follow-up labels — UI-only visual hints organizers attach to guests
 * while chasing RSVPs (e.g. "Not reachable", "Call later"). Never included
 * in reports or business logic; purely a colour-coded visual cue.
 *
 * Each label maps to:
 *   - badge:   classes for the inline pill shown next to the RSVP badge
 *   - row:     soft tinted classes applied to the guest row background
 *   - dot:     small dot used in dropdown menu items
 */
export interface GuestFollowUpLabel {
  slug: string;
  label: string;
  badge: string;
  row: string;
  dot: string;
}

export const GUEST_FOLLOW_UP_LABELS: GuestFollowUpLabel[] = [
  {
    slug: 'not_reachable',
    label: 'Not reachable',
    badge:
      'bg-amber-50 text-amber-800 border-amber-200 dark:bg-amber-500/10 dark:text-amber-300 dark:border-amber-500/30',
    row: 'bg-amber-50/40 dark:bg-amber-500/[0.04]',
    dot: 'bg-amber-500',
  },
  {
    slug: 'no_pickup',
    label: 'Did not pick up',
    badge:
      'bg-slate-100 text-slate-700 border-slate-200 dark:bg-slate-500/10 dark:text-slate-300 dark:border-slate-500/30',
    row: 'bg-slate-50/60 dark:bg-slate-500/[0.04]',
    dot: 'bg-slate-500',
  },
  {
    slug: 'call_later',
    label: 'Call later',
    badge:
      'bg-sky-50 text-sky-700 border-sky-200 dark:bg-sky-500/10 dark:text-sky-300 dark:border-sky-500/30',
    row: 'bg-sky-50/50 dark:bg-sky-500/[0.04]',
    dot: 'bg-sky-500',
  },
  {
    slug: 'left_voicemail',
    label: 'Left voicemail',
    badge:
      'bg-violet-50 text-violet-700 border-violet-200 dark:bg-violet-500/10 dark:text-violet-300 dark:border-violet-500/30',
    row: 'bg-violet-50/50 dark:bg-violet-500/[0.04]',
    dot: 'bg-violet-500',
  },
  {
    slug: 'wrong_number',
    label: 'Wrong number',
    badge:
      'bg-rose-50 text-rose-700 border-rose-200 dark:bg-rose-500/10 dark:text-rose-300 dark:border-rose-500/30',
    row: 'bg-rose-50/50 dark:bg-rose-500/[0.04]',
    dot: 'bg-rose-500',
  },
  {
    slug: 'spoke_undecided',
    label: 'Spoke, undecided',
    badge:
      'bg-orange-50 text-orange-700 border-orange-200 dark:bg-orange-500/10 dark:text-orange-300 dark:border-orange-500/30',
    row: 'bg-orange-50/50 dark:bg-orange-500/[0.04]',
    dot: 'bg-orange-500',
  },
  {
    slug: 'needs_info',
    label: 'Needs more info',
    badge:
      'bg-teal-50 text-teal-700 border-teal-200 dark:bg-teal-500/10 dark:text-teal-300 dark:border-teal-500/30',
    row: 'bg-teal-50/50 dark:bg-teal-500/[0.04]',
    dot: 'bg-teal-500',
  },
];

export const getGuestFollowUpLabel = (slug?: string | null): GuestFollowUpLabel | undefined =>
  slug ? GUEST_FOLLOW_UP_LABELS.find((l) => l.slug === slug) : undefined;
