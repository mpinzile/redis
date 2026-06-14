import { motion } from "framer-motion";
import { Link } from "react-router-dom";
import { ArrowUpRight } from "lucide-react";
import Layout from "@/components/layout/Layout";
import { useMeta } from "@/hooks/useMeta";

/**
 * Features index — editorial directory of every Nuru capability.
 * Mirrors the visual language of the landing page (mono kickers,
 * heading scale, hairline grid) so it reads as a premium continuation
 * rather than a separate marketing page.
 */

type Feature = {
  num: string;
  tag: string;
  title: string;
  blurb: string;
  to: string;
  for: string;
};

const features: Feature[] = [
  {
    num: "01",
    tag: "Workspace",
    title: "Event Planning",
    blurb:
      "Open a workspace for any occasion. Budgets, timelines, committees, vendors and contributions · all coordinated in one transparent surface.",
    to: "/features/event-planning",
    for: "Organisers",
  },
  {
    num: "02",
    tag: "Marketplace",
    title: "Vendors & Services",
    blurb:
      "Discover, vet and book photographers, caterers, decorators, venues, MCs and more. Verified profiles, secured payments, no chasing.",
    to: "/features/service-providers",
    for: "Organisers · Vendors",
  },
  {
    num: "03",
    tag: "Guests",
    title: "Invitations & RSVP",
    blurb:
      "Send beautiful invitations, track confirmations in real time, and message guests through the channels they actually use.",
    to: "/features/invitations",
    for: "Organisers · Guests",
  },
  {
    num: "04",
    tag: "Hardware",
    title: "NuruCards (NFC)",
    blurb:
      "Tap-to-share digital identity cards for organisers, vendors and VIP guests. One card, your whole event presence.",
    to: "/features/nfc-cards",
    for: "Everyone",
  },
  {
    num: "05",
    tag: "Money",
    title: "Built-in Payments",
    blurb:
      "Mobile money, cards and bank transfers · held securely, released on milestones, recorded to the shilling.",
    to: "/features/payments",
    for: "Organisers · Vendors · Contributors",
  },
  {
    num: "06",
    tag: "Coordination",
    title: "Built-in Meetings",
    blurb:
      "Spin up secure video rooms tied to the event itself. No external links, no missing context.",
    to: "/features/meetings",
    for: "Organisers · Committees",
  },
  {
    num: "07",
    tag: "Community",
    title: "Event Groups",
    blurb:
      "Public, private and invite-only groups for committees, contributors and guests · with shared files, polls and announcements.",
    to: "/features/event-groups",
    for: "Organisers · Committees",
  },
  {
    num: "08",
    tag: "Revenue",
    title: "Ticketing",
    blurb:
      "Sell tickets directly under your event. Multiple classes, offline-payment claims, tap-to-verify entry.",
    to: "/features/ticketing",
    for: "Organisers · Guests",
  },
  {
    num: "09",
    tag: "Protection",
    title: "Trust & Protection",
    blurb:
      "Identity checks, dispute resolution, audit trails and structured release windows · fairness built into the system.",
    to: "/features/trust",
    for: "Everyone",
  },
];

const FeaturesIndex = () => {
  useMeta({
    title: "Features | Nuru Workspace",
    description:
      "Every Nuru capability in one directory · event planning, vendors, invitations, NFC cards, payments, meetings, groups, ticketing and trust.",
  });

  return (
    <Layout>
      {/* ── Hero ─────────────────────────────────────────────── */}
      <section className="relative border-b border-border/70">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-12 pt-28 lg:pt-40 pb-20 lg:pb-28">
          <div className="grid lg:grid-cols-12 gap-10 items-end">
            <div className="lg:col-span-3 text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono">
              § Index — Features
            </div>
            <div className="lg:col-span-9">
              <motion.h1
                initial={{ opacity: 0, y: 24 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.8, ease: [0.22, 1, 0.36, 1] }}
                className="font-heading font-semibold tracking-[-0.04em] leading-[0.92] text-[clamp(2.5rem,7vw,6rem)] text-foreground"
              >
                Every part of Nuru,
                <br />
                <span className="text-muted-foreground">in one directory.</span>
              </motion.h1>
              <motion.p
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.8, delay: 0.15 }}
                className="mt-8 max-w-2xl text-muted-foreground text-base lg:text-lg leading-relaxed"
              >
                Nine connected capabilities that turn stressful preparation
                into structured progress. Pick the one you want to know more
                about.
              </motion.p>
            </div>
          </div>
        </div>
      </section>

      {/* ── Directory ────────────────────────────────────────── */}
      <section className="relative">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-12 py-16 lg:py-24">
          <ul className="grid sm:grid-cols-2 lg:grid-cols-3 gap-px bg-border/70 border border-border/70 rounded-3xl overflow-hidden">
            {features.map((f, i) => (
              <motion.li
                key={f.to}
                initial={{ opacity: 0, y: 24 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: "-60px" }}
                transition={{ duration: 0.55, delay: (i % 3) * 0.06, ease: [0.22, 1, 0.36, 1] }}
                className="bg-background"
              >
                <Link
                  to={f.to}
                  className="group relative flex flex-col h-full p-8 lg:p-10 transition-colors hover:bg-muted/40 focus:outline-none focus-visible:ring-2 focus-visible:ring-foreground/20"
                >
                  <div className="flex items-start justify-between mb-10">
                    <div>
                      <div className="text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono mb-2">
                        № {f.num} - {f.tag}
                      </div>
                      <div className="text-[10px] tracking-[0.2em] uppercase text-muted-foreground/70 font-mono">
                        For {f.for}
                      </div>
                    </div>
                    <ArrowUpRight className="w-5 h-5 text-foreground/40 transition-all group-hover:text-foreground group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
                  </div>

                  <h2 className="font-heading font-semibold tracking-[-0.025em] leading-[1.05] text-[clamp(1.5rem,2.4vw,2rem)] text-foreground mb-4">
                    {f.title}
                  </h2>
                  <p className="text-muted-foreground text-sm lg:text-base leading-relaxed">
                    {f.blurb}
                  </p>

                  <div className="mt-auto pt-10">
                    <span className="inline-flex items-center gap-1.5 text-sm font-medium text-foreground border-b border-foreground/30 pb-0.5 group-hover:border-foreground transition-colors">
                      Read more
                    </span>
                  </div>

                  {/* hover accent */}
                  <span
                    aria-hidden
                    className="pointer-events-none absolute inset-x-0 bottom-0 h-px bg-gradient-to-r from-transparent via-accent to-transparent opacity-0 group-hover:opacity-100 transition-opacity"
                  />
                </Link>
              </motion.li>
            ))}
          </ul>
        </div>
      </section>

      {/* ── Closing CTA ──────────────────────────────────────── */}
      <section className="relative border-t border-border/70 bg-muted/30">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-12 py-20 lg:py-28">
          <div className="grid lg:grid-cols-12 gap-10 items-end">
            <div className="lg:col-span-8">
              <h2 className="font-heading font-semibold tracking-[-0.03em] leading-[1] text-[clamp(2rem,4vw,3.5rem)] text-foreground">
                Ready to open your first workspace?
              </h2>
              <p className="mt-6 max-w-xl text-muted-foreground text-base lg:text-lg leading-relaxed">
                Start free. Invite your committee. Move every spreadsheet,
                chat thread and paper note into one calm surface.
              </p>
            </div>
            <div className="lg:col-span-4 flex flex-wrap gap-4 lg:justify-end">
              <Link
                to="/register"
                className="inline-flex items-center gap-2 px-6 py-3 rounded-full bg-foreground text-background text-sm font-medium hover:bg-foreground/90 transition-colors"
              >
                Open a workspace
                <ArrowUpRight className="w-4 h-4" />
              </Link>
              <Link
                to="/contact"
                className="inline-flex items-center gap-2 px-6 py-3 rounded-full border border-foreground/20 text-foreground text-sm font-medium hover:bg-foreground/5 transition-colors"
              >
                Talk to us
              </Link>
            </div>
          </div>
        </div>
      </section>
    </Layout>
  );
};

export default FeaturesIndex;
