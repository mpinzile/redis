import { useState, useEffect, useMemo, useCallback } from 'react'
import {
  Search,
  Briefcase,
  AlertTriangle,
  LucideIcon,
  Sparkles,
  BookOpen,
  Wallet,
  HandCoins,
  ChevronDown,
  Command as CommandIcon,
  Star,
  Clock,
  StarOff,
  MessageSquare,
  Activity,
} from 'lucide-react'
import { useLanguage } from '@/lib/i18n/LanguageContext'

import { Button } from '@/components/ui/button'
import { NavLink, useNavigate, useLocation } from 'react-router-dom'
import SvgIcon from '@/components/ui/svg-icon'
import HomeIcon from '@/assets/icons/home-icon.svg'
import CalendarIcon from '@/assets/icons/calendar-icon.svg'
import ChatIcon from '@/assets/icons/chat-icon.svg'
import BellIcon from '@/assets/icons/bell-icon.svg'
import CardIcon from '@/assets/icons/card-icon.svg'
import TicketIcon from '@/assets/icons/ticket-icon.svg'
import AddSquareIcon from '@/assets/icons/add-square-icon.svg'
import IssueIcon from '@/assets/icons/issue-icon.svg'
import SettingsIcon from '@/assets/icons/settings-icon.svg'
import CircleIcon from '@/assets/icons/circle-icon.svg'
import CommunitiesIcon from '@/assets/icons/communities-icon.svg'
import UserProfileIcon from '@/assets/icons/user-profile-icon.svg'
import ContributorsIcon from '@/assets/icons/contributors-icon.svg'
import HelpIcon from '@/assets/icons/help-icon.svg'
import GroupsIcon from '@/assets/icons/groups-icon.svg'
import {
  HoverCard,
  HoverCardContent,
  HoverCardTrigger,
} from '@/components/ui/hover-card'
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible'
import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandShortcut,
  CommandSeparator,
} from '@/components/ui/command'
import { cn } from '@/lib/utils'

interface SidebarProps {
  onNavigate?: () => void;
  onReplayTour?: () => void;
  /** When true, renders the full expanded desktop layout regardless of viewport (used inside the mobile drawer). */
  inDrawer?: boolean;
}

type NavItem = {
  label: string;
  path: string;
  hint?: string;
  shortcut?: string; // shown as a kbd hint, e.g. "G H"
} & (
  | { customIcon: string; lucideIcon?: never }
  | { lucideIcon: LucideIcon; customIcon?: never }
);

type NavSection = {
  id: string;
  label: string;
  defaultOpen?: boolean;
  items: NavItem[];
};

const HINTS_KEY = 'nuru_sidebar_hints';
const SECTION_STATE_KEY = 'nuru_sidebar_sections_v1';
const FAVORITES_KEY = 'nuru_sidebar_favorites_v1';
const RECENTS_KEY = 'nuru_sidebar_recents_v1';
const MAX_RECENTS = 5;

const Sidebar = ({ onNavigate, onReplayTour, inDrawer = false }: SidebarProps) => {
  // When inside the mobile drawer, force the expanded "lg" layout instead of the icon-rail "md" layout.
  const lg = (cls: string) => (inDrawer ? cls.replace(/(^|\s)lg:/g, '$1') : cls);
  const showLabel = inDrawer ? 'inline' : 'md:hidden lg:inline';
  const showLgBlock = inDrawer ? 'block' : 'hidden lg:block';
  const showLgFlex = inDrawer ? 'flex' : 'hidden lg:flex';
  const showLgInlineFlex = inDrawer ? 'inline-flex' : 'hidden lg:inline-flex';
  const hideOnLg = inDrawer ? 'hidden' : 'md:block lg:hidden';
  const navigate = useNavigate();
  const location = useLocation();
  const { t } = useLanguage();

  const [hintsEnabled, setHintsEnabled] = useState(() => {
    const stored = localStorage.getItem(HINTS_KEY);
    return stored !== 'false';
  });
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [filter, setFilter] = useState('');
  const [sectionState, setSectionState] = useState<Record<string, boolean>>(() => {
    try {
      const raw = localStorage.getItem(SECTION_STATE_KEY);
      return raw ? JSON.parse(raw) : {};
    } catch {
      return {};
    }
  });
  const [favorites, setFavorites] = useState<string[]>(() => {
    try {
      const raw = localStorage.getItem(FAVORITES_KEY);
      return raw ? JSON.parse(raw) : [];
    } catch { return []; }
  });
  const [recents, setRecents] = useState<string[]>(() => {
    try {
      const raw = localStorage.getItem(RECENTS_KEY);
      return raw ? JSON.parse(raw) : [];
    } catch { return []; }
  });

  useEffect(() => {
    const handler = () => setHintsEnabled(localStorage.getItem(HINTS_KEY) !== 'false');
    window.addEventListener('sidebar-hints-changed', handler);
    return () => window.removeEventListener('sidebar-hints-changed', handler);
  }, []);

  // Cmd/Ctrl+K opens the palette
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setPaletteOpen((o) => !o);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const persistSections = useCallback((next: Record<string, boolean>) => {
    setSectionState(next);
    try { localStorage.setItem(SECTION_STATE_KEY, JSON.stringify(next)); } catch {}
  }, []);

  const persistFavorites = useCallback((next: string[]) => {
    setFavorites(next);
    try { localStorage.setItem(FAVORITES_KEY, JSON.stringify(next)); } catch {}
  }, []);

  const toggleFavorite = useCallback((path: string) => {
    persistFavorites(
      favorites.includes(path) ? favorites.filter((p) => p !== path) : [...favorites, path]
    );
  }, [favorites, persistFavorites]);

  // Track recent route visits
  useEffect(() => {
    const path = location.pathname;
    if (!path || path === '/') return; // skip Home (always pinned)
    setRecents((prev) => {
      const next = [path, ...prev.filter((p) => p !== path)].slice(0, MAX_RECENTS);
      try { localStorage.setItem(RECENTS_KEY, JSON.stringify(next)); } catch {}
      return next;
    });
  }, [location.pathname]);

  // ── Pinned (always visible) ──────────────────────────────────────────────
  const pinned: NavItem[] = [
    { customIcon: HomeIcon, label: t('home'), path: '/', shortcut: 'G H', hint: 'Your feed: posts, trending moments, updates from people and events you follow.' },
    { customIcon: CalendarIcon, label: t('my_events'), path: '/my-events', shortcut: 'G E', hint: 'Events you organize, attend, or help run as a committee member.' },
    { customIcon: ChatIcon, label: t('messages'), path: '/messages', shortcut: 'G M', hint: 'Private chats with organizers, providers, and your circle.' },
    { customIcon: BellIcon, label: t('notifications'), path: '/notifications', shortcut: 'G N', hint: 'RSVPs, follows, bookings, contributions, and content updates.' },
  ];

  // ── Grouped sections ─────────────────────────────────────────────────────
  const sections: NavSection[] = [
    {
      id: 'discover', label: 'Discover', defaultOpen: true,
      items: [
        { customIcon: TicketIcon, label: t('browse_tickets'), path: '/tickets', hint: 'Discover upcoming events near you and buy tickets.' },
        { lucideIcon: Search, label: t('find_services'), path: '/find-services', hint: 'Find verified DJs, caterers, photographers, and more.' },
        { customIcon: CommunitiesIcon, label: t('communities'), path: '/communities', hint: 'Join community groups by interest or profession.' },
      ],
    },
    {
      id: 'money', label: 'Money', defaultOpen: true,
      items: [
        { lucideIcon: Wallet, label: 'Wallet', path: '/wallet', hint: 'Wallet balance, top-ups, and transaction history.' },
        { lucideIcon: BookOpen, label: 'Bookings', path: '/bookings', hint: 'Booking requests in and out · accept, decline, pay deposits.' },
        { lucideIcon: HandCoins, label: 'My Contributions', path: '/my-contributions', hint: 'Receipts for every contribution you have paid.' },
        { customIcon: ContributorsIcon, label: 'My Contributors', path: '/my-contributors', hint: 'People who have contributed to your events.' },
      ],
    },
    {
      id: 'network', label: 'Network', defaultOpen: false,
      items: [
        { customIcon: CircleIcon, label: t('circle'), path: '/circle', hint: 'People you follow, your followers, and pending requests.' },
        { customIcon: GroupsIcon, label: 'My Groups', path: '/my-groups', hint: 'All your event group chats with unread counts.' },
        { lucideIcon: Briefcase, label: t('my_services'), path: '/my-services', hint: 'Manage your services, bookings, and reviews.' },
        { customIcon: CardIcon, label: t('nuru_pass'), path: '/nuru-cards', hint: 'Order your Nuru Pass for tap-to-check-in at events.' },
      ],
    },
    {
      id: 'account', label: 'Account', defaultOpen: false,
      items: [
        { customIcon: IssueIcon, label: t('my_issues'), path: '/my-issues', hint: 'Submit and track issues or disputes.' },
        { lucideIcon: MessageSquare, label: 'WhatsApp Logs', path: '/whatsapp-logs', hint: 'Track every WhatsApp message Nuru sent · what worked and what failed.' },
        { lucideIcon: Activity, label: 'Background Tasks', path: '/background-tasks', hint: 'Live progress of uploads, bulk actions, exports and other work Nuru is doing for you.' },
        { lucideIcon: AlertTriangle, label: t('removed_content'), path: '/removed-content', hint: 'Removed posts, reasons, and appeals.' },
        { customIcon: HelpIcon, label: t('help'), path: '/help', hint: 'FAQs and contact support.' },
        { customIcon: SettingsIcon, label: t('settings'), path: '/settings', hint: 'Notifications, privacy, theme, and account settings.' },
      ],
    },
  ];

  // Lookup: path → NavItem (for Favorites + Recents rendering)
  const itemsByPath = useMemo<Record<string, NavItem>>(() => {
    const map: Record<string, NavItem> = {};
    [...pinned, ...sections.flatMap((s) => s.items)].forEach((i) => { map[i.path] = i; });
    map['/profile'] = { customIcon: UserProfileIcon, label: t('your_profile'), path: '/profile' };
    map['/create-event'] = { customIcon: AddSquareIcon, label: t('create_event'), path: '/create-event' };
    return map;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [t]);

  const allItems = useMemo<NavItem[]>(
    () => Object.values(itemsByPath),
    [itemsByPath]
  );

  // Auto-expand the section that contains the active route
  const activeSectionId = useMemo(() => {
    const p = location.pathname;
    return sections.find((s) => s.items.some((i) => i.path === p))?.id ?? null;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.pathname]);

  const isOpen = (s: NavSection) => {
    if (sectionState[s.id] !== undefined) return sectionState[s.id];
    if (activeSectionId === s.id) return true;
    return s.defaultOpen ?? false;
  };

  // ── Renderers ────────────────────────────────────────────────────────────
  const renderIcon = (item: NavItem) => {
    if (item.customIcon) {
      return <SvgIcon src={item.customIcon} alt={item.label} className="w-[18px] h-[18px] flex-shrink-0" />
    }
    const IconComponent = item.lucideIcon!;
    return <IconComponent className="w-[18px] h-[18px] flex-shrink-0" />;
  };

  const linkClass = ({ isActive }: { isActive: boolean }) =>
    cn(
      'group/nav relative w-full flex items-center gap-2.5 px-2.5 lg:px-2.5 md:px-0 md:justify-center lg:justify-start py-1.5 md:py-2 rounded-lg font-medium transition-all duration-150 text-left text-[13px]',
      isActive
        ? 'bg-gradient-to-r from-nuru-yellow/25 via-nuru-yellow/10 to-transparent text-foreground shadow-[0_1px_0_0_hsl(var(--border))] font-semibold'
        : 'text-sidebar-foreground/75 hover:bg-sidebar-accent/60 hover:text-sidebar-accent-foreground hover:translate-x-[1px]'
    );

  const renderNavItem = (item: NavItem, opts?: { showStar?: boolean }) => {
    const showStar = opts?.showStar ?? true;
    const isFav = favorites.includes(item.path);

    const link = (
      <NavLink to={item.path} className={linkClass} onClick={onNavigate} title={item.label} end={item.path === '/'}>
        {({ isActive }) => (
          <>
            <span
              aria-hidden
              className={cn(
                'absolute left-0 top-1/2 -translate-y-1/2 h-5 w-[3px] rounded-r-full transition-all',
                isActive ? 'bg-nuru-yellow opacity-100' : 'opacity-0'
              )}
            />
            {renderIcon(item)}
            <span className={cn(showLabel, 'truncate flex-1')}>{item.label}</span>
            {showStar && (
              <button
                type="button"
                onClick={(e) => { e.preventDefault(); e.stopPropagation(); toggleFavorite(item.path); }}
                className={cn(
                  showLgInlineFlex, 'p-1 -mr-1 rounded transition-opacity',
                  isFav ? 'opacity-100 text-nuru-yellow' : 'opacity-0 group-hover/nav:opacity-60 hover:!opacity-100 text-muted-foreground'
                )}
                title={isFav ? 'Remove from favorites' : 'Add to favorites'}
                aria-label={isFav ? 'Remove favorite' : 'Add favorite'}
              >
                {isFav ? <Star className="w-3.5 h-3.5 fill-current" /> : <Star className="w-3.5 h-3.5" />}
              </button>
            )}
          </>
        )}
      </NavLink>
    );

    if (!hintsEnabled || !item.hint) return <div key={item.path}>{link}</div>;

    return (
      <HoverCard key={item.path} openDelay={500} closeDelay={100}>
        <HoverCardTrigger asChild>
          <div>{link}</div>
        </HoverCardTrigger>
        <HoverCardContent side="right" align="start" className="hidden lg:block w-72 bg-popover border border-border shadow-lg rounded-xl p-4">
          <div className="flex items-center justify-between mb-1">
            <p className="text-sm font-semibold text-foreground">{item.label}</p>
            {item.shortcut && (
              <kbd className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-muted text-muted-foreground">{item.shortcut}</kbd>
            )}
          </div>
          <p className="text-xs text-muted-foreground leading-relaxed">{item.hint}</p>
          <button
            onClick={(e) => {
              e.stopPropagation();
              localStorage.setItem(HINTS_KEY, 'false');
              setHintsEnabled(false);
              window.dispatchEvent(new Event('sidebar-hints-changed'));
            }}
            className="mt-2 text-[11px] text-muted-foreground/60 hover:text-muted-foreground transition-colors"
          >
            Don't show again
          </button>
        </HoverCardContent>
      </HoverCard>
    );
  };

  const normalizedFilter = filter.trim().toLowerCase();
  const matches = (i: NavItem) => i.label.toLowerCase().includes(normalizedFilter);

  // Resolved favorites/recents → existing NavItems (skip unknown paths)
  const favItems = favorites.map((p) => itemsByPath[p]).filter(Boolean) as NavItem[];
  const recentItems = recents
    .filter((p) => !favorites.includes(p))
    .map((p) => itemsByPath[p])
    .filter(Boolean) as NavItem[];

  return (
    <aside className={cn('flex flex-col h-full overflow-hidden bg-sidebar-background', inDrawer ? 'w-full' : 'w-full md:w-14 lg:w-64 md:border-r md:border-sidebar-border')}>
      {/* Quick jump trigger (desktop) */}
      <div className={cn(showLgBlock, 'px-3 pt-3 pb-2')}>
        <button
          type="button"
          onClick={() => setPaletteOpen(true)}
          className="w-full flex items-center gap-2 rounded-md border border-sidebar-border bg-background/50 hover:bg-sidebar-accent/60 transition-colors px-2.5 py-1.5 text-left text-xs text-muted-foreground"
        >
          <Search className="w-3.5 h-3.5" />
          <span className="flex-1">Quick jump…</span>
          <kbd className="hidden xl:inline-flex items-center gap-0.5 rounded bg-muted px-1.5 py-0.5 text-[10px] font-mono text-muted-foreground">
            <CommandIcon className="w-3 h-3" />K
          </kbd>
        </button>
      </div>

      {/* Inline filter */}
      <div className={cn(showLgBlock, 'px-3 pb-2')}>
        <input
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder="Filter menu"
          className="w-full bg-transparent border-0 px-1 py-0.5 text-xs text-muted-foreground placeholder:text-muted-foreground/60 focus:outline-none focus:ring-0"
        />
      </div>

      <div className={cn('flex-1 overflow-y-auto overscroll-y-contain', inDrawer ? 'px-3 pb-4 pt-0' : 'p-1.5 lg:px-3 lg:pb-4 lg:pt-0')}>
        {/* Pinned */}
        <nav className="space-y-0.5">
          {(normalizedFilter ? pinned.filter(matches) : pinned).map((i) => renderNavItem(i))}
        </nav>

        {/* Create Event CTA */}
        <div className="mt-3 mb-2">
          <NavLink to="/create-event" onClick={onNavigate}>
            <Button className={cn('w-full bg-nuru-yellow hover:bg-nuru-yellow/90 text-foreground font-semibold justify-center shadow-sm h-9', inDrawer ? 'px-4' : 'lg:px-4 md:px-0 px-4')}>
              <SvgIcon src={AddSquareIcon} alt={t('create_event')} className={cn('w-4 h-4', inDrawer ? 'mr-2' : 'lg:mr-2')} />
              <span className={showLabel}>{t('create_event')}</span>
            </Button>
          </NavLink>
        </div>

        {/* Favorites — show only when there are some, hidden in filter mode */}
        {!normalizedFilter && favItems.length > 0 && (
          <div className={cn(showLgBlock, 'mt-3')}>
            <div className="flex items-center gap-1.5 px-2.5 py-1.5 text-[11px] uppercase tracking-wider font-semibold text-muted-foreground/70">
              <Star className="w-3 h-3" /> <span>Favorites</span>
            </div>
            <nav className="space-y-0.5">
              {favItems.map((i) => renderNavItem(i))}
            </nav>
          </div>
        )}

        {/* Recents — surfaced when not filtering and we have a couple */}
        {!normalizedFilter && recentItems.length > 0 && (
          <div className={cn(showLgBlock, 'mt-3')}>
            <div className="flex items-center gap-1.5 px-2.5 py-1.5 text-[11px] uppercase tracking-wider font-semibold text-muted-foreground/70">
              <Clock className="w-3 h-3" /> <span>Recents</span>
            </div>
            <nav className="space-y-0.5">
              {recentItems.slice(0, 3).map((i) => renderNavItem(i, { showStar: true }))}
            </nav>
          </div>
        )}

        {/* Sections */}
        {normalizedFilter ? (
          <nav className="mt-2 space-y-0.5">
            {sections.flatMap((s) => s.items).filter(matches).map((i) => renderNavItem(i))}
          </nav>
        ) : (
          <div className="mt-3 space-y-0.5">
            {sections.map((s) => {
              const open = isOpen(s);
              return (
                <Collapsible
                  key={s.id}
                  open={open}
                  onOpenChange={(v) => persistSections({ ...sectionState, [s.id]: v })}
                >
                  <CollapsibleTrigger
                    className={cn(
                      showLgFlex, 'w-full items-center gap-1.5 px-2.5 py-1.5 rounded-md text-[10.5px] uppercase tracking-[0.08em] font-semibold transition-colors',
                      open ? 'text-foreground/80' : 'text-muted-foreground/60 hover:text-foreground/80'
                    )}
                  >
                    <ChevronDown className={cn('w-3 h-3 transition-transform duration-200 shrink-0', open ? 'rotate-0' : '-rotate-90')} />
                    <span className="flex-1 text-left">{s.label}</span>
                    <span className={cn('text-[10px] font-mono tabular-nums px-1.5 rounded bg-muted/60 transition-opacity', open ? 'opacity-0' : 'opacity-100')}>
                      {s.items.length}
                    </span>
                  </CollapsibleTrigger>

                  {/* md (icon-only) view: always show items */}
                  <div className={hideOnLg}>
                    <nav className="space-y-0.5">{s.items.map((i) => renderNavItem(i, { showStar: false }))}</nav>
                  </div>

                  <CollapsibleContent className={cn(showLgBlock, 'overflow-hidden data-[state=open]:animate-accordion-down data-[state=closed]:animate-accordion-up')}>
                    <div className="relative pl-3 ml-[11px] mt-0.5 mb-1 border-l border-sidebar-border/70">
                      <nav className="space-y-px">{s.items.map((i) => renderNavItem(i))}</nav>
                    </div>
                  </CollapsibleContent>
                </Collapsible>
              );
            })}
          </div>
        )}

        {/* Replay tour */}
        {onReplayTour && (
          <div className="mt-3">
            <button
              onClick={onReplayTour}
              className={cn('w-full flex items-center gap-3 py-2 rounded-md font-medium text-sm text-muted-foreground hover:bg-sidebar-accent/70 hover:text-sidebar-accent-foreground transition-colors', inDrawer ? 'px-2.5 justify-start' : 'px-2.5 lg:px-2.5 md:px-0 md:justify-center lg:justify-start')}
            >
              <Sparkles className="w-[18px] h-[18px] flex-shrink-0" />
              <span className={showLabel}>{t('replay_tour')}</span>
            </button>
          </div>
        )}
      </div>

      {/* Sticky profile footer */}
      <div className={cn('border-t border-sidebar-border', inDrawer ? 'p-3' : 'p-2 lg:p-3')}>
        <NavLink to="/profile" className={linkClass} onClick={onNavigate} title={t('your_profile')}>
          {({ isActive }) => (
            <>
              <span
                aria-hidden
                className={cn(
                  'absolute left-0 top-1/2 -translate-y-1/2 h-5 w-[3px] rounded-r-full transition-all',
                  isActive ? 'bg-nuru-yellow opacity-100' : 'opacity-0'
                )}
              />
              <SvgIcon src={UserProfileIcon} className="w-[18px] h-[18px]" />
              <span className={showLabel}>{t('your_profile')}</span>
            </>
          )}
        </NavLink>
      </div>

      {/* Cmd/Ctrl+K command palette */}
      <CommandDialog open={paletteOpen} onOpenChange={setPaletteOpen}>
        <CommandInput placeholder="Jump to anything in Nuru…" />
        <CommandList>
          <CommandEmpty>No results found.</CommandEmpty>

          {favItems.length > 0 && (
            <>
              <CommandGroup heading="Favorites">
                {favItems.map((item) => (
                  <CommandItem
                    key={`fav-${item.path}`}
                    value={`★ ${item.label} ${item.path}`}
                    onSelect={() => { setPaletteOpen(false); navigate(item.path); onNavigate?.(); }}
                  >
                    {renderIcon(item)}
                    <span className="ml-2">{item.label}</span>
                    <CommandShortcut>★</CommandShortcut>
                  </CommandItem>
                ))}
              </CommandGroup>
              <CommandSeparator />
            </>
          )}

          {recentItems.length > 0 && (
            <>
              <CommandGroup heading="Recents">
                {recentItems.map((item) => (
                  <CommandItem
                    key={`rec-${item.path}`}
                    value={`recent ${item.label} ${item.path}`}
                    onSelect={() => { setPaletteOpen(false); navigate(item.path); onNavigate?.(); }}
                  >
                    {renderIcon(item)}
                    <span className="ml-2">{item.label}</span>
                  </CommandItem>
                ))}
              </CommandGroup>
              <CommandSeparator />
            </>
          )}

          <CommandGroup heading="Pages">
            {allItems.map((item) => (
              <CommandItem
                key={item.path}
                value={`${item.label} ${item.path}`}
                onSelect={() => { setPaletteOpen(false); navigate(item.path); onNavigate?.(); }}
              >
                {renderIcon(item)}
                <span className="ml-2">{item.label}</span>
                <CommandShortcut className="flex items-center gap-1">
                  {item.shortcut && <kbd className="text-[10px] font-mono">{item.shortcut}</kbd>}
                  <button
                    type="button"
                    onClick={(e) => { e.preventDefault(); e.stopPropagation(); toggleFavorite(item.path); }}
                    className="p-0.5 rounded hover:bg-muted"
                    aria-label="Toggle favorite"
                  >
                    {favorites.includes(item.path)
                      ? <Star className="w-3 h-3 text-nuru-yellow fill-current" />
                      : <StarOff className="w-3 h-3" />}
                  </button>
                </CommandShortcut>
              </CommandItem>
            ))}
          </CommandGroup>
        </CommandList>
      </CommandDialog>
    </aside>
  )
}

export default Sidebar
