import { motion } from "framer-motion";
import { useMemo, useState } from "react";
import { Search, Plus, Minus, X } from "lucide-react";
import { Input } from "@/components/ui/input";
import Layout from "@/components/layout/Layout";
import { useMeta } from "@/hooks/useMeta";
import { Link } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

type Topic =
  | "All"
  | "Getting started"
  | "Payments"
  | "Tanzania"
  | "Kenya"
  | "International"
  | "Vendors"
  | "Tickets"
  | "Privacy"
  | "Cards & RSVP";

interface Faq {
  q: string;
  a: string;
  topics: Topic[];
}

const TOPICS: Topic[] = [
  "All",
  "Getting started",
  "Payments",
  "Tanzania",
  "Kenya",
  "International",
  "Vendors",
  "Tickets",
  "Cards & RSVP",
  "Privacy",
];

// Curated FAQ corpus — grounded in the company profile, payment methods,
// and the country footprint (TZ, KE, international USD).
const FAQS: Faq[] = [
  {
    q: "What is Nuru Workspace?",
    a: "Nuru Workspace is the operating platform for every event · weddings, conferences, memorials, fundraisers, corporate events and more, anywhere in the world. Organisers, vendors, contributors and guests work in one place · planning, payments, RSVPs, ticketing and check-ins, recorded with the rigor of a bank.",
    topics: ["Getting started"],
  },
  {
    q: "Is Nuru free to use?",
    a: "Opening a workspace is free. Inviting your committee, building budgets, sending invitations and tracking RSVPs are all free. You only pay a small fee when money moves · contributions, ticket sales or vendor bookings.",
    topics: ["Getting started", "Payments"],
  },
  {
    q: "Which countries does Nuru operate in?",
    a: "Nuru is live in Tanzania (nuru.tz) and Kenya (nuru.ke), with international support for diaspora contributors paying in USD. Local payment methods, currency and language are switched automatically based on your domain.",
    topics: ["Getting started", "Tanzania", "Kenya", "International"],
  },
  {
    q: "Which payment methods are supported in Tanzania?",
    a: "M-Pesa (Vodacom), Airtel Money, Mixx by Yas (formerly Tigo Pesa) and Halopesa for mobile money; Visa and Mastercard for cards; and direct bank transfer with auto-matching references. Contributions, ticket purchases and vendor deposits all use the same checkout.",
    topics: ["Payments", "Tanzania"],
  },
  {
    q: "Which payment methods are supported in Kenya?",
    a: "M-Pesa (Safaricom) and Airtel Money for mobile money; Visa and Mastercard for cards; and bank transfer. International cards are accepted for diaspora contributors paying in USD.",
    topics: ["Payments", "Kenya"],
  },
  {
    q: "Can family or friends abroad contribute in USD?",
    a: "Yes. International contributors can pay by Visa or Mastercard in USD on any contribution page. The amount is settled to the organiser in their local currency (TZS or KES) at the prevailing rate.",
    topics: ["Payments", "International"],
  },
  {
    q: "How fast does money settle to the organiser?",
    a: "Cleared contributions and ticket sales settle within 24 hours. Vendor deposits sit in protected payments until the milestones you agreed to are met · never released blindly.",
    topics: ["Payments"],
  },
  {
    q: "Are payments and contributions secure?",
    a: "Card payments are processed by PCI-DSS aligned partners and Nuru never stores full card details. Mobile money transactions go directly through licensed operators. Every transaction is recorded on a tamper-evident ledger with auto-issued receipts.",
    topics: ["Payments", "Privacy"],
  },
  {
    q: "What if a vendor takes a deposit and disappears?",
    a: "Vendor deposits are held in protected payments and only released as milestones are met. If something goes wrong you can open a structured dispute · both sides submit evidence and a Nuru reviewer mediates. See the Trust & Protection page for details.",
    topics: ["Vendors", "Payments"],
  },
  {
    q: "Can I sell my services on Nuru as a vendor?",
    a: "Yes. Caterers, decorators, photographers, MCs, transport, sound, lighting, entertainment and venues can build a verified Nuru profile, accept bookings and get paid through protected payments. ID and business verification is required before the badge appears.",
    topics: ["Vendors", "Getting started"],
  },
  {
    q: "How are vendors verified?",
    a: "Through national ID or passport, business registration where applicable, and a selfie liveness check. The Nuru badge means an organiser can hire that vendor with the same confidence as a bank counterparty.",
    topics: ["Vendors", "Privacy"],
  },
  {
    q: "Can I sell tickets for an event on Nuru?",
    a: "Yes. Set unlimited tiers (Early, Regular, VIP, Group), accept M-Pesa, Airtel, Mixx by Yas, card and bank, and check buyers in at the door with QR or NFC NuruCards. Sales settle within 24 hours.",
    topics: ["Tickets", "Payments"],
  },
  {
    q: "What are NuruCards?",
    a: "Premium NFC cards branded for your event. One tap shares the invitation, confirms attendance, opens the contribution page or checks the guest in at the door. They feel like an heirloom and work like a key.",
    topics: ["Cards & RSVP"],
  },
  {
    q: "How do I send digital invitations and track RSVPs?",
    a: "Invitations go out by SMS, WhatsApp, email or a personalised short link. Each guest gets their own page. RSVPs land in your dashboard in real time, and you can resend reminders to non-responders only.",
    topics: ["Cards & RSVP"],
  },
  {
    q: "Can multiple organisers and committees coordinate inside one event?",
    a: "Yes. Add organisers, committee leads (food, decor, transport, entertainment) and contributors with role-based access. Each committee gets a sub-budget, a channel, and built-in video meetings · no more chat-app spaghetti.",
    topics: ["Getting started"],
  },
  {
    q: "Does Nuru have built-in video meetings?",
    a: "Yes · HD browser-based video meetings open from any event workspace. No installs, no separate accounts. Decisions made in calls are logged into the event activity automatically.",
    topics: ["Getting started"],
  },
  {
    q: "How is my data protected?",
    a: "Personal information, event data and payment records are stored encrypted. Access is role-based · contributors only see what's appropriate. See the Privacy Policy for the full data lifecycle, retention and deletion rules.",
    topics: ["Privacy"],
  },
  {
    q: "Can I delete my account and data?",
    a: "Yes. You can request account and data deletion at any time from Settings, or by emailing hello@nuru.tz. Financial records may be retained where required by law for tax and audit purposes.",
    topics: ["Privacy"],
  },
  {
    q: "Where can I read the legal terms?",
    a: "Privacy Policy, Terms of Service, Cookie Policy, Cancellation Policy, Vendor Agreement and Organiser Agreement are linked at the bottom of every page.",
    topics: ["Privacy"],
  },
];

const LEGAL_LINKS = [
  { label: "Privacy Policy", to: "/privacy-policy" },
  { label: "Terms of Service", to: "/terms" },
  { label: "Cookie Policy", to: "/cookie-policy" },
  { label: "Cancellation Policy", to: "/cancellation-policy" },
  { label: "Vendor Agreement", to: "/vendor-agreement" },
  { label: "Organiser Agreement", to: "/organiser-agreement" },
];

const FAQs = () => {
  const [searchTerm, setSearchTerm] = useState("");
  const [topic, setTopic] = useState<Topic>("All");
  const [openIndex, setOpenIndex] = useState<number | null>(null);

  useMeta({
    title: "FAQs · Payments, Vendors, RSVP, Tickets | Nuru",
    description:
      "Answers about Nuru Workspace: payments and mobile money in Tanzania (M-Pesa, Airtel, Mixx by Yas) and Kenya, international USD contributions, vendor verification, RSVP, NuruCards, ticketing and privacy.",
  });

  const filteredFAQs = useMemo(() => {
    const q = searchTerm.trim().toLowerCase();
    return FAQS.filter((f) => {
      const topicOk = topic === "All" || f.topics.includes(topic);
      if (!topicOk) return false;
      if (!q) return true;
      return (
        f.q.toLowerCase().includes(q) ||
        f.a.toLowerCase().includes(q) ||
        f.topics.some((t) => t.toLowerCase().includes(q))
      );
    });
  }, [searchTerm, topic]);

  return (
    <Layout>
      <div className="min-h-screen pt-32 pb-24 px-6">
        <div className="max-w-3xl mx-auto">
          {/* Header */}
          <motion.div
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
            className="mb-12"
          >
            <div className="text-[10px] tracking-[0.3em] uppercase text-muted-foreground/80 font-mono mb-6">
              Help Centre — FAQs
            </div>
            <h1 className="text-4xl sm:text-5xl md:text-6xl font-bold text-foreground tracking-tight mb-6">
              Questions?
              <br />
              <span className="text-muted-foreground">Answers.</span>
            </h1>
            <p className="text-lg text-muted-foreground max-w-xl">
              Search by topic, country or payment method. Can't find what you're
              looking for? Our team replies within one business day.
            </p>
          </motion.div>

          {/* Search */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: 0.15 }}
            className="relative mb-5"
          >
            <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-muted-foreground" />
            <Input
              type="text"
              placeholder="Search M-Pesa, KES, vendor, RSVP…"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-12 pr-12 h-14 text-base rounded-2xl border-border bg-muted/50"
            />
            {searchTerm && (
              <button
                onClick={() => setSearchTerm("")}
                className="absolute right-4 top-1/2 -translate-y-1/2 p-1 rounded-full hover:bg-muted text-muted-foreground"
                aria-label="Clear search"
              >
                <X className="w-4 h-4" />
              </button>
            )}
          </motion.div>

          {/* Topic chips */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.5, delay: 0.25 }}
            className="flex flex-wrap gap-2 mb-10"
          >
            {TOPICS.map((t) => {
              const active = topic === t;
              return (
                <button
                  key={t}
                  onClick={() => setTopic(t)}
                  className={cn(
                    "px-3.5 py-1.5 rounded-full text-xs font-medium border transition",
                    active
                      ? "bg-foreground text-background border-foreground"
                      : "bg-transparent text-muted-foreground border-border hover:border-foreground/40 hover:text-foreground"
                  )}
                >
                  {t}
                </button>
              );
            })}
          </motion.div>

          {/* Result count */}
          <div className="text-[11px] tracking-[0.22em] uppercase text-muted-foreground/70 font-mono mb-4">
            {filteredFAQs.length} {filteredFAQs.length === 1 ? "result" : "results"}
            {topic !== "All" && <> - {topic}</>}
            {searchTerm && <> - "{searchTerm}"</>}
          </div>

          {/* FAQ list */}
          <div className="space-y-3">
            {filteredFAQs.map((faq, index) => {
              const open = openIndex === index;
              return (
                <motion.div
                  key={faq.q}
                  initial={{ opacity: 0, y: 12 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.35, delay: Math.min(index * 0.03, 0.3) }}
                >
                  <button
                    onClick={() => setOpenIndex(open ? null : index)}
                    className="w-full text-left p-6 bg-muted/50 rounded-2xl hover:bg-muted transition-colors"
                  >
                    <div className="flex items-start justify-between gap-4">
                      <span className="text-lg font-medium text-foreground pr-8">
                        {faq.q}
                      </span>
                      <div className="flex-shrink-0 w-6 h-6 rounded-full bg-foreground/10 flex items-center justify-center">
                        {open ? (
                          <Minus className="w-3.5 h-3.5 text-foreground" />
                        ) : (
                          <Plus className="w-3.5 h-3.5 text-foreground" />
                        )}
                      </div>
                    </div>
                    <motion.div
                      initial={false}
                      animate={{
                        height: open ? "auto" : 0,
                        opacity: open ? 1 : 0,
                        marginTop: open ? 16 : 0,
                      }}
                      transition={{ duration: 0.25 }}
                      className="overflow-hidden"
                    >
                      <p className="text-muted-foreground leading-relaxed">
                        {faq.a}
                      </p>
                      <div className="mt-4 flex flex-wrap gap-1.5">
                        {faq.topics.map((t) => (
                          <span
                            key={t}
                            className="text-[10px] tracking-[0.15em] uppercase text-muted-foreground/70 font-mono px-2 py-0.5 rounded-full bg-background border border-border"
                          >
                            {t}
                          </span>
                        ))}
                      </div>
                    </motion.div>
                  </button>
                </motion.div>
              );
            })}
          </div>

          {filteredFAQs.length === 0 && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="text-center py-16"
            >
              <p className="text-foreground text-lg mb-2">No matching answers</p>
              <p className="text-sm text-muted-foreground">
                Try a different topic, or {" "}
                <Link to="/contact" className="text-foreground underline underline-offset-4">
                  ask our team
                </Link>
                .
              </p>
            </motion.div>
          )}

          {/* Legal index */}
          <motion.div
            initial={{ opacity: 0, y: 16 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.5 }}
            className="mt-20 pt-10 border-t border-border"
          >
            <div className="text-[10px] tracking-[0.3em] uppercase text-muted-foreground/80 font-mono mb-4">
              Policies & Agreements
            </div>
            <h2 className="font-heading font-semibold tracking-[-0.02em] text-2xl mb-6">
              The full legal index
            </h2>
            <div className="grid sm:grid-cols-2 gap-2">
              {LEGAL_LINKS.map((l) => (
                <Link
                  key={l.to}
                  to={l.to}
                  className="flex items-center justify-between px-4 py-3 rounded-xl border border-border hover:border-foreground/40 hover:bg-muted/40 transition group"
                >
                  <span className="text-sm font-medium text-foreground">{l.label}</span>
                  <span className="text-xs text-muted-foreground group-hover:text-foreground transition">
                    Read →
                  </span>
                </Link>
              ))}
            </div>
          </motion.div>

          {/* Contact CTA */}
          <motion.div
            initial={{ opacity: 0, y: 30 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.5 }}
            className="mt-12 p-8 bg-foreground text-background rounded-3xl text-center"
          >
            <h3 className="text-2xl font-semibold mb-3">
              Still have questions?
            </h3>
            <p className="text-background/60 mb-6">
              Our team is ready to help you get started.
            </p>
            <Button
              asChild
              className="bg-background text-foreground hover:bg-background/90 rounded-full h-12 px-8"
            >
              <Link to="/contact">Get in touch</Link>
            </Button>
          </motion.div>
        </div>
      </div>
    </Layout>
  );
};

export default FAQs;
