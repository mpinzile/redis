import { motion } from "framer-motion";
import { Link } from "react-router-dom";
import { ArrowUpRight } from "lucide-react";
import Layout from "@/components/layout/Layout";
import { useMeta } from "@/hooks/useMeta";
import LivingLedgerHero from "@/components/landing/LivingLedgerHero";
import DownloadAppSection from "@/components/landing/DownloadAppSection";

/**
 * Landing page — copy is grounded in the official Nuru Workspace
 * Company Profile (v1.0, 19 Apr 2026). No invented features, no
 * AI-flavoured "step" copy. Slogan: "Plan Smarter. Celebrate Better."
 */

const Index = () => {
  useMeta({
    title: "Nuru Workspace | Plan Smarter. Celebrate Better.",
    description:
      "Nuru Workspace is the event operating system for organisers, vendors, contributors, guests and partners · one connected workspace from first idea to final celebration.",
  });

  // ── §3 The Problem Nuru Solves — verbatim recurring questions ──
  const recurringQuestions = [
    "Who has paid and who has not paid.",
    "Where can trusted vendors be found.",
    "How much money has already been spent.",
    "Who is handling decorations, food, transport, invitations, or entertainment.",
    "Which guest has confirmed attendance.",
    "What happens if a vendor takes money and fails to appear.",
    "How can everyone stay updated without endless phone calls.",
    "How can event money be handled transparently and accountably.",
  ];

  // ── §5–§8 Core experience by audience ──
  const audiences = [
    {
      tag: "For organisers",
      title: "The command centre of your event.",
      body:
        "Open a workspace for a wedding, conference, graduation, exhibition, family celebration or business event. Build budgets, invite guests, coordinate committees, collect contributions, sell tickets, and book vendors · all in one place. Control replaces confusion.",
      points: [
        "Budgets that update in real time, before pressure becomes crisis.",
        "Cleaner RSVP and announcement workflows.",
        "Committees coordinated inside one environment, not scattered chats.",
      ],
      cta: { label: "Open a workspace", href: "/register" },
    },
    {
      tag: "For vendors",
      title: "A growth and trust platform, not a chase.",
      body:
        "List services with pricing, categories, availability and clear booking terms. Photographers, caterers, decorators, venues, MCs, DJs, transport, makeup, security, equipment, accommodation and planners all participate inside a trusted ecosystem with secured payment logic that protects serious work.",
      points: [
        "Professional digital presence with verified profile.",
        "Secured payment arrangements before service begins.",
        "Opportunities arrive through the system, not manual chasing.",
      ],
      cta: { label: "List your services", href: "/register" },
    },
    {
      tag: "For partners",
      title: "Co-host events. Share revenue. See everything.",
      body:
        "Hotels, venues, lodges and tourism operators can co-host events with agreed revenue-sharing logic. Sell room categories · Executive, Deluxe, packages · directly under the event experience, with shared, transparent visibility into sales and revenue performance.",
      points: [
        "Accommodation and packages tied to the event itself.",
        "Transparent revenue sharing both sides can audit.",
        "New demand for hospitality, new income for organisers.",
      ],
      cta: { label: "Become a partner", href: "/contact" },
    },
  ];

  // ── §9 Why Nuru matters in the local market — eight realities ──
  const localTruths = [
    "Family contributions matter.",
    "Community coordination matters.",
    "Vendor trust matters.",
    "Mobile payments matter.",
    "Flexible guest communication matters.",
    "Price sensitivity matters.",
    "Partnership-based events matter.",
    "Local event culture matters.",
  ];

  return (
    <Layout>
      {/* ── 1. Premium "Living Ledger" hero ── */}
      <LivingLedgerHero />

      {/* ── 2. Brand statement (§15) ─────────────────────────────── */}
      <section className="relative border-t border-border/70">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-12 py-24 lg:py-32">
          <div className="grid lg:grid-cols-12 gap-10 items-start">
            <div className="lg:col-span-3 text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono">
              § 01 — Brand
            </div>
            <motion.div
              initial={{ opacity: 0, y: 24 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-100px" }}
              transition={{ duration: 0.8, ease: [0.22, 1, 0.36, 1] }}
              className="lg:col-span-9"
            >
              <p className="font-heading font-medium tracking-[-0.025em] leading-[1.08] text-[clamp(1.75rem,3.5vw,3rem)] text-foreground">
                Nuru is where{" "}
                <span className="text-muted-foreground">planning meets confidence</span>{" "}
                and{" "}
                <span className="text-muted-foreground">celebration meets simplicity.</span>{" "}
                It turns stressful preparation into structured progress, uncertainty
                into visibility, and transactions into trust.
              </p>
              <p className="mt-8 text-sm tracking-[0.2em] uppercase text-muted-foreground/80">
                The name <span className="text-foreground">Nuru</span> means light, clarity, direction.
              </p>
            </motion.div>
          </div>
        </div>
      </section>

      {/* ── 3. The problem — recurring questions as typographic spread (§3) ── */}
      <section className="relative bg-foreground text-background overflow-hidden">
        {/* hairline grid */}
        <div
          aria-hidden
          className="absolute inset-0 opacity-[0.06] pointer-events-none"
          style={{
            backgroundImage:
              "linear-gradient(to right, hsl(var(--background)) 1px, transparent 1px), linear-gradient(to bottom, hsl(var(--background)) 1px, transparent 1px)",
            backgroundSize: "120px 120px",
          }}
        />
        <div className="relative max-w-[1400px] mx-auto px-6 lg:px-12 py-24 lg:py-32">
          <div className="grid lg:grid-cols-12 gap-10 mb-16 lg:mb-20">
            <div className="lg:col-span-3 text-[10px] tracking-[0.28em] uppercase text-background/50 font-mono">
              § 02 — The problem
            </div>
            <div className="lg:col-span-9">
              <h2 className="font-heading font-semibold tracking-[-0.035em] leading-[0.95] text-[clamp(2.25rem,5.5vw,4.5rem)]">
                Most events begin with excitement
                <br />
                <span className="text-background/40">and end in frustration.</span>
              </h2>
              <p className="mt-8 max-w-2xl text-background/60 text-base lg:text-lg leading-relaxed">
                Spreadsheets, paper notes, cash handling, scattered chats, verbal
                promises. Organisers, vendors and contributors keep asking the same
                painful questions, every event, every time.
              </p>
            </div>
          </div>

          <ol className="grid sm:grid-cols-2 lg:grid-cols-2 divide-y divide-background/10 sm:divide-y-0 sm:[&>li:nth-child(odd)]:border-r sm:[&>li]:border-background/10 border-y border-background/10">
            {recurringQuestions.map((q, i) => (
              <motion.li
                key={q}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: "-50px" }}
                transition={{ duration: 0.5, delay: (i % 4) * 0.06 }}
                className="px-2 sm:px-8 py-7 lg:py-8 flex gap-5 items-start"
              >
                <span className="text-[10px] font-mono text-background/40 tabular-nums pt-1.5 w-6 shrink-0">
                  {String(i + 1).padStart(2, "0")}
                </span>
                <span className="font-heading text-lg lg:text-2xl text-background/90 leading-snug tracking-[-0.01em]">
                  {q}
                </span>
              </motion.li>
            ))}
          </ol>

          <div className="mt-16 max-w-3xl">
            <p className="text-background/80 text-lg lg:text-xl leading-relaxed font-heading">
              Nuru replaces all of that with one professional workspace where the
              planning, financial and communication lifecycle of an event lives in
              a single secure environment.
            </p>
          </div>
        </div>
      </section>

      {/* ── 4. What Nuru is for — three audiences (§5, §6, §8) ── */}
      <section className="relative">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-12 py-24 lg:py-32">
          <div className="grid lg:grid-cols-12 gap-10 mb-16 lg:mb-20">
            <div className="lg:col-span-3 text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono">
              § 03 — Built for
            </div>
            <div className="lg:col-span-9">
              <h2 className="font-heading font-semibold tracking-[-0.035em] leading-[0.95] text-[clamp(2.25rem,5.5vw,4.5rem)] text-foreground">
                One workspace.
                <br />
                <span className="text-muted-foreground">Three sides of every event.</span>
              </h2>
              <Link
                to="/features"
                className="mt-8 inline-flex items-center gap-1.5 text-sm font-medium text-foreground border-b border-foreground/30 hover:border-foreground transition-colors pb-0.5"
              >
                Explore all features
                <ArrowUpRight className="w-4 h-4" />
              </Link>
            </div>
          </div>

          <div className="space-y-px bg-border/70 border border-border/70 rounded-3xl overflow-hidden">
            {audiences.map((a, i) => (
              <motion.article
                key={a.tag}
                initial={{ opacity: 0, y: 24 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: "-80px" }}
                transition={{ duration: 0.7, delay: i * 0.08, ease: [0.22, 1, 0.36, 1] }}
                className="bg-background grid lg:grid-cols-12 gap-8 lg:gap-12 px-6 lg:px-12 py-12 lg:py-16 group"
              >
                <div className="lg:col-span-3 flex lg:flex-col justify-between gap-4">
                  <div>
                    <div className="text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono mb-2">
                      0{i + 1}
                    </div>
                    <div className="font-heading text-xl lg:text-2xl font-medium text-foreground">
                      {a.tag}
                    </div>
                  </div>
                  <Link
                    to={a.cta.href}
                    className="self-start inline-flex items-center gap-1.5 text-sm font-medium text-foreground hover:text-foreground/70 transition-colors group/btn"
                  >
                    {a.cta.label}
                    <ArrowUpRight className="w-4 h-4 transition-transform group-hover/btn:translate-x-0.5 group-hover/btn:-translate-y-0.5" />
                  </Link>
                </div>

                <div className="lg:col-span-9">
                  <h3 className="font-heading font-semibold tracking-[-0.025em] leading-[1.05] text-[clamp(1.75rem,3.2vw,2.75rem)] text-foreground mb-6">
                    {a.title}
                  </h3>
                  <p className="text-muted-foreground text-base lg:text-lg leading-relaxed max-w-2xl mb-8">
                    {a.body}
                  </p>
                  <ul className="grid sm:grid-cols-3 gap-6 lg:gap-8 border-t border-border/70 pt-6">
                    {a.points.map((p) => (
                      <li
                        key={p}
                        className="text-sm text-foreground/80 leading-relaxed pl-4 border-l border-accent/70"
                      >
                        {p}
                      </li>
                    ))}
                  </ul>
                </div>
              </motion.article>
            ))}
          </div>
        </div>
      </section>

      {/* ── 5. Trust infrastructure (§7) — quiet, dense, premium ── */}
      <section className="relative border-y border-border/70 bg-muted/30">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-12 py-24 lg:py-32">
          <div className="grid lg:grid-cols-12 gap-10 items-start">
            <div className="lg:col-span-4">
              <div className="text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono mb-6">
                § 04 — Trust infrastructure
              </div>
              <h2 className="font-heading font-semibold tracking-[-0.03em] leading-[1] text-[clamp(2rem,4vw,3.5rem)] text-foreground">
                Most event problems
                <br />
                begin with money.
              </h2>
            </div>
            <div className="lg:col-span-7 lg:col-start-6">
              <p className="text-foreground/80 text-lg lg:text-xl leading-relaxed font-heading">
                A vendor fears non-payment. An organiser fears paying in advance and
                being disappointed. Contributors fear misuse of funds. Buyers fear
                scams. Nuru reduces every one of these fears through structured
                payment flows, clear records, controlled release logic and
                accountability built into the system itself.
              </p>

              <div className="mt-12 grid sm:grid-cols-2 gap-px bg-border/70 border border-border/70 rounded-2xl overflow-hidden">
                {[
                  { k: "Secured", v: "Payment held before service begins." },
                  { k: "Confirmed", v: "Completion windows for both sides." },
                  { k: "Reviewed", v: "Disputes follow a fair process." },
                  { k: "Recorded", v: "Every shilling, audit-grade." },
                ].map((item) => (
                  <div key={item.k} className="bg-background p-6">
                    <div className="text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono mb-2">
                      {item.k}
                    </div>
                    <div className="text-foreground font-heading text-base lg:text-lg leading-snug">
                      {item.v}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ── 6. Built for local realities (§9) ─────────────────────── */}
      <section className="relative bg-foreground text-background overflow-hidden">
        <div className="relative max-w-[1400px] mx-auto px-6 lg:px-12 py-24 lg:py-32">
          <div className="grid lg:grid-cols-12 gap-10 mb-12 lg:mb-16">
            <div className="lg:col-span-3 text-[10px] tracking-[0.28em] uppercase text-background/50 font-mono">
              § 05 — Local realities
            </div>
            <div className="lg:col-span-9">
              <h2 className="font-heading font-semibold tracking-[-0.035em] leading-[0.95] text-[clamp(2.25rem,5.5vw,4.5rem)]">
                Built around how
                <br />
                <span className="text-background/40">our events actually work.</span>
              </h2>
              <p className="mt-8 max-w-2xl text-background/60 text-base lg:text-lg leading-relaxed">
                Many global tools assume universal card usage, highly formalised
                vendor markets and predictable planning culture. Nuru is built on
                a different set of truths.
              </p>
            </div>
          </div>

          <ul className="border-t border-background/10">
            {localTruths.map((t, i) => (
              <motion.li
                key={t}
                initial={{ opacity: 0, x: -16 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true, margin: "-40px" }}
                transition={{ duration: 0.5, delay: i * 0.05 }}
                className="border-b border-background/10 grid grid-cols-12 items-baseline py-5 lg:py-6 group"
              >
                <span className="col-span-2 text-[10px] font-mono text-background/40 tabular-nums">
                  {String(i + 1).padStart(2, "0")}
                </span>
                <span className="col-span-10 font-heading font-medium text-2xl lg:text-4xl tracking-[-0.02em] text-background group-hover:text-accent transition-colors duration-500">
                  {t}
                </span>
              </motion.li>
            ))}
          </ul>
        </div>
      </section>

      {/* ── 7. Long-term vision (§14) + closing identity (§16) ───── */}
      <section className="relative">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-12 py-28 lg:py-40">
          <div className="grid lg:grid-cols-12 gap-10">
            <div className="lg:col-span-3 text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono">
              § 06 — Vision
            </div>
            <div className="lg:col-span-9">
              <h2 className="font-heading font-semibold tracking-[-0.04em] leading-[0.92] text-[clamp(2.5rem,7vw,6rem)] text-foreground mb-12">
                The most trusted
                <br />
                event-infrastructure
                <br />
                <span className="text-muted-foreground">platform in the region.</span>
              </h2>

              <div className="grid sm:grid-cols-2 gap-x-12 gap-y-6 max-w-3xl text-foreground/80 text-base lg:text-lg leading-relaxed">
                <p>A place where any person or organisation can confidently plan, finance, host, monetise and celebrate events of every size.</p>
                <p>A place where vendors grow real businesses and hospitality partners unlock new demand.</p>
                <p>A place where communities coordinate important moments smoothly.</p>
                <p>A place where trust is built into the system itself — not into personal relationships alone.</p>
              </div>

              <div className="mt-20 pt-10 border-t border-border/70">
                <p className="font-heading font-semibold tracking-[-0.03em] text-2xl lg:text-3xl text-foreground max-w-2xl">
                  Nuru Workspace is more than software. It is the future of organised celebration.
                </p>
                <div className="mt-10 flex flex-col sm:flex-row sm:items-center gap-4">
                  <Link
                    to="/register"
                    className="group inline-flex items-center justify-center gap-2 bg-foreground text-background px-7 h-12 rounded-full text-sm font-medium hover:bg-foreground/90 transition-colors"
                  >
                    Get started free
                    <ArrowUpRight className="w-4 h-4 transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
                  </Link>
                  <Link
                    to="/contact"
                    className="inline-flex items-center justify-center h-12 px-6 rounded-full text-sm font-medium border border-border text-foreground hover:bg-muted transition-colors"
                  >
                    Talk to the team
                  </Link>
                  <span className="sm:ml-auto text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono">
                    Plan Smarter. Celebrate Better.
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ── 8. Download app ─────────────────────────────────────── */}
      <DownloadAppSection />
    </Layout>
  );
};

export default Index;
