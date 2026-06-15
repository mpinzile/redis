import { useState, useEffect, useRef } from "react";
import { NavLink, Outlet, useNavigate, useLocation } from "react-router-dom";
import {
  LayoutDashboard, Users, ShieldCheck, CalendarDays,
  MessageSquare, HeadphonesIcon, HelpCircle, Bell,
  LogOut, Menu,
  Package, Briefcase, Newspaper, Sparkles, Users2,
  BookOpen, CreditCard, Tag, UserCog, BadgeCheck, AlertTriangle,
  BarChart3, MessageCircle, PanelLeftClose, PanelLeft, FileCheck,
  Ticket, Flag, Activity, Banknote, Inbox, Trash2, PhoneCall,
} from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import nuruLogo from "@/assets/nuru-logo.png";

const navItems = [
  { label: "Dashboard", icon: LayoutDashboard, to: "/admin" },
  { label: "Users", icon: Users, to: "/admin/users" },
  { label: "Name Flags", icon: Flag, to: "/admin/name-flags" },
  { label: "KYC Verification", icon: ShieldCheck, to: "/admin/kyc" },
  { label: "Identity Verification", icon: BadgeCheck, to: "/admin/user-verifications" },
  { label: "Services", icon: Briefcase, to: "/admin/services" },
  { label: "Service Categories", icon: Tag, to: "/admin/service-categories" },
  { label: "Events", icon: CalendarDays, to: "/admin/events" },
  { label: "Event Types", icon: Package, to: "/admin/event-types" },
  { label: "Ticketed Events", icon: Ticket, to: "/admin/ticketed-events" },
  { label: "Posts / Feed", icon: Newspaper, to: "/admin/posts" },
  { label: "Moments", icon: Sparkles, to: "/admin/moments" },
  { label: "Content Appeals", icon: AlertTriangle, to: "/admin/appeals" },
  { label: "Communities", icon: Users2, to: "/admin/communities" },
  { label: "Bookings", icon: BookOpen, to: "/admin/bookings" },
  { label: "NuruCard Orders", icon: CreditCard, to: "/admin/nuru-cards" },
  { label: "Live Chats", icon: MessageSquare, to: "/admin/chats" },
  { label: "Contact Messages", icon: Inbox, to: "/admin/contact-messages" },
  { label: "Deletion Requests", icon: Trash2, to: "/admin/deletion-requests" },
  { label: "WhatsApp", icon: MessageCircle, to: "/admin/whatsapp" },
  { label: "WhatsApp Templates", icon: MessageCircle, to: "/admin/whatsapp/templates" },
  { label: "WhatsApp Logs", icon: MessageSquare, to: "/admin/whatsapp-logs" },
  { label: "Voice Calls", icon: PhoneCall, to: "/admin/voice-calls" },
  { label: "Support Tickets", icon: HeadphonesIcon, to: "/admin/tickets" },
  { label: "FAQs", icon: HelpCircle, to: "/admin/faqs" },
  { label: "Notifications", icon: Bell, to: "/admin/notifications" },
  { label: "Admin Accounts", icon: UserCog, to: "/admin/admins" },
  { label: "Analytics", icon: BarChart3, to: "/admin/analytics" },
  { label: "User Issues", icon: AlertTriangle, to: "/admin/issues" },
  { label: "Issue Categories", icon: Tag, to: "/admin/issue-categories" },
  { label: "Agreements", icon: FileCheck, to: "/admin/agreements" },
  { label: "Monitoring", icon: Activity, to: "/admin/monitoring" },
  { label: "Payments", icon: Banknote, to: "/admin/payments" },
];

export default function AdminLayout() {
  const navigate = useNavigate();
  const location = useLocation();
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [mobileSidebarOpen, setMobileSidebarOpen] = useState(false);
  const [adminUser, setAdminUser] = useState<{ full_name: string; email: string; role: string } | null>(null);

  useEffect(() => {
    const token = localStorage.getItem("admin_token");
    if (!token) {
      navigate("/admin/login", { replace: true });
      return;
    }
    try {
      const stored = localStorage.getItem("admin_user");
      if (stored) setAdminUser(JSON.parse(stored));
    } catch { /* ignore */ }
  }, [navigate]);

  const handleLogout = () => {
    localStorage.removeItem("admin_token");
    localStorage.removeItem("admin_refresh_token");
    localStorage.removeItem("admin_user");
    toast.success("Logged out from admin panel");
    navigate("/admin/login", { replace: true });
  };

  const isActive = (path: string) => {
    if (path === "/admin") return location.pathname === "/admin";
    // If a more specific nav entry starts with this path, require exact match
    // (prevents /admin/whatsapp from also matching /admin/whatsapp/templates).
    const hasMoreSpecific = navItems.some(
      (n) => n.to !== path && n.to.startsWith(path + "/"),
    );
    if (hasMoreSpecific) return location.pathname === path;
    return location.pathname === path || location.pathname.startsWith(path + "/");
  };

  // Prefer the most-specific (longest) matching nav entry for the page title.
  const currentLabel =
    [...navItems]
      .sort((a, b) => b.to.length - a.to.length)
      .find((n) => isActive(n.to))?.label || "Admin Panel";

  // When mobile sidebar opens, ensure it shows text labels
  const handleMobileToggle = () => {
    setMobileSidebarOpen((prev) => !prev);
  };

  // Persist sidebar scroll position — identical approach to workspace Sidebar.tsx
  // The workspace sidebar is a plain <aside> with overflow-y-auto; the browser keeps
  // scroll position automatically because the element is never unmounted.
  // We replicate that here: the <nav> element is also never unmounted, so we only
  // need to save/restore when the user explicitly scrolls, NOT on every route change.
  const sidebarScrollRef = useRef<HTMLElement>(null);
  const mobileSidebarScrollRef = useRef<HTMLElement>(null);
  const SCROLL_KEY = "admin_sidebar_scroll";

  // On mount: restore saved scroll position immediately (no rAF = no flicker)
  useEffect(() => {
    const saved = sessionStorage.getItem(SCROLL_KEY);
    if (saved && sidebarScrollRef.current) {
      sidebarScrollRef.current.scrollTop = parseInt(saved, 10);
    }
  }, []); // run once on mount only

  const handleNavScroll = (e: React.UIEvent<HTMLElement>) => {
    sessionStorage.setItem(SCROLL_KEY, String(e.currentTarget.scrollTop));
  };

  const SidebarContent = ({ mobile = false, scrollRef }: { mobile?: boolean; scrollRef?: React.RefObject<HTMLElement> }) => (
    <div className="flex flex-col h-full min-h-0">
      {/* Logo — left-aligned */}
      <div className="p-4 border-b border-border/60 shrink-0">
        <div className="flex items-center gap-2">
          <img
            src={nuruLogo}
            alt="Nuru"
            className={(sidebarOpen || mobile) ? "h-8 w-auto" : "h-7 w-auto"}
          />
        </div>
        {(sidebarOpen || mobile) && (
          <p className="text-[10px] font-bold tracking-[0.2em] text-muted-foreground/70 mt-1.5 uppercase">
            Admin Console
          </p>
        )}
      </div>

      {/* Nav — scrollable, position preserved via sessionStorage */}
      <nav
        ref={scrollRef as any}
        onScroll={!mobile ? handleNavScroll : undefined}
        className="flex-1 p-2.5 space-y-0.5 overflow-y-auto"
      >
        {navItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.to === "/admin"}
            onClick={() => { if (mobile) setMobileSidebarOpen(false); }}
            className={cn(
              "flex items-center gap-3 px-3 py-2 rounded-lg text-[13px] font-medium transition-all duration-200",
              isActive(item.to)
                ? "bg-foreground text-background shadow-sm"
                : "text-muted-foreground hover:text-foreground hover:bg-muted/60"
            )}
          >
            <item.icon className="w-[18px] h-[18px] shrink-0" />
            {(sidebarOpen || mobile) && <span className="truncate">{item.label}</span>}
          </NavLink>
        ))}
      </nav>

      {/* Admin Info + Logout */}
      <div className="p-3 border-t border-border/60 space-y-1 shrink-0">
        {adminUser && (sidebarOpen || mobile) && (
          <div className="px-3 py-2.5 rounded-lg bg-muted/40 mb-1">
            <div className="font-semibold text-xs text-foreground truncate">{adminUser.full_name}</div>
            <div className="text-[11px] text-muted-foreground truncate">{adminUser.email}</div>
            <div className="text-[11px] text-primary font-medium capitalize mt-0.5">{adminUser.role}</div>
          </div>
        )}
        <button
          onClick={handleLogout}
          className="flex items-center gap-3 px-3 py-2 rounded-lg text-[13px] font-medium text-destructive hover:bg-destructive/8 w-full transition-all duration-200"
        >
          <LogOut className="w-[18px] h-[18px] shrink-0" />
          {(sidebarOpen || mobile) && <span>Logout</span>}
        </button>
      </div>
    </div>
  );

  return (
    <div className="min-h-screen bg-background flex">
      {/* Desktop Sidebar — fixed position, internally scrollable */}
      <aside
        className={cn(
          "hidden md:flex flex-col border-r border-border bg-card transition-all duration-200 fixed top-0 left-0 bottom-0 z-40",
          sidebarOpen ? "w-56" : "w-14"
        )}
      >
        <SidebarContent scrollRef={sidebarScrollRef} />
      </aside>
      {/* Spacer to push main content right when sidebar is fixed */}
      <div className={cn("hidden md:block shrink-0 transition-all duration-200", sidebarOpen ? "w-56" : "w-14")} />

      {/* Mobile Sidebar Overlay */}
      {mobileSidebarOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/50 md:hidden"
          onClick={() => setMobileSidebarOpen(false)}
        />
      )}
      {/* Mobile Sidebar — always renders w-56, just translated off-screen when closed */}
      <aside
        className={cn(
          "fixed top-0 left-0 bottom-0 z-50 w-56 flex flex-col border-r border-border bg-card transition-transform duration-200 md:hidden",
          mobileSidebarOpen ? "translate-x-0" : "-translate-x-full"
        )}
      >
        <SidebarContent mobile={true} scrollRef={mobileSidebarScrollRef} />
      </aside>

      {/* Main Content */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* Top Bar */}
        <header className="sticky top-0 z-30 h-14 border-b border-border/60 bg-card/80 backdrop-blur-md flex items-center px-5 gap-4 shrink-0">
          <button
            onClick={() => {
              setSidebarOpen((prev) => !prev);
              handleMobileToggle();
            }}
            className="p-1.5 rounded-lg hover:bg-muted text-muted-foreground hover:text-foreground transition-all duration-200"
          >
            {sidebarOpen ? <PanelLeftClose className="w-5 h-5" /> : <PanelLeft className="w-5 h-5" />}
          </button>
          <div className="flex-1">
            <h1 className="text-sm font-bold tracking-tight text-foreground">{currentLabel}</h1>
          </div>
          {adminUser && (
            <div className="flex items-center gap-3">
              <div className="text-right hidden sm:block">
                <div className="text-xs font-semibold text-foreground leading-tight">{adminUser.full_name}</div>
                <div className="text-[11px] text-muted-foreground capitalize leading-tight">{adminUser.role}</div>
              </div>
              <div className="w-8 h-8 rounded-full bg-foreground/10 flex items-center justify-center text-xs font-bold text-foreground shrink-0 ring-1 ring-border/60">
                {adminUser.full_name?.[0]?.toUpperCase() || "A"}
              </div>
            </div>
          )}
        </header>

        {/* Page */}
        <main className="flex-1 overflow-auto p-6">
          <AnimatePresence mode="wait">
            <motion.div
              key={location.pathname}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -4 }}
              transition={{ duration: 0.2, ease: "easeOut" }}
            >
              <Outlet />
            </motion.div>
          </AnimatePresence>
        </main>
      </div>
    </div>
  );
}
