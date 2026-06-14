import { motion } from "framer-motion";
import { Link } from "react-router-dom";
import { ArrowUpRight, Check } from "lucide-react";
import Layout from "@/components/layout/Layout";

/**
 * EditorialFeaturePage
 * --------------------------------------------------------------
 * Shared editorial layout for every public feature / service page.
 * Mirrors the "Living Ledger" hero language used on the landing
 * page: hairline rules, mono micro-labels, monumental display
 * type, restrained motion. Every feature page should compose
 * this component instead of inventing its own shell.
 * --------------------------------------------------------------
 */

export interface EditorialFeatureSection {
  /** Mono caption shown above the section title, e.g. "Section 02". */
  caption?: string;
  /** Display heading for the section. */
  title: string;
  /** Optional lead paragraph shown right under the title. */
  lead?: string;
  /** Bullet items rendered as a 2-column hairline list. */
  bullets?: string[];
}

export interface EditorialFeaturePageProps {
  /** Mono kicker shown over the hero title, e.g. "Service - 04". */
  kicker: string;
  /** Hero display title. Use a single short sentence. */
  title: string;
  /** Hero subtitle / lead paragraph. */
  lead: string;
  /** Optional set of "specs" rendered into the hero strip. */
  specs?: { label: string; value: string }[];
  /** Numbered editorial sections. */
  sections: EditorialFeatureSection[];
  /** Final CTA strip. */
  cta?: {
    eyebrow?: string;
    title: string;
    body?: string;
    primary: { label: string; href: string };
    secondary?: { label: string; href: string };
  };
}

const ease = [0.22, 1, 0.36, 1] as const;

const EditorialFeaturePage = ({
  kicker,
  title,
  lead,
  specs,
  sections,
  cta,
}: EditorialFeaturePageProps) => {
  return (
    <Layout>
      {/* ── Hero ─────────────────────────────────────────────── */}
      <section className="relative overflow-hidden bg-background text-foreground border-b border-border/70">
        <div
          aria-hidden
          className="absolute inset-0 opacity-[0.3] pointer-events-none"
          style={{
            backgroundImage:
              "linear-gradient(to right, hsl(var(--border)/0.55) 1px, transparent 1px), linear-gradient(to bottom, hsl(var(--border)/0.55) 1px, transparent 1px)",
            backgroundSize: "96px 96px",
            maskImage:
              "radial-gradient(ellipse 70% 60% at 50% 30%, hsl(var(--background)) 30%, transparent 80%)",
            WebkitMaskImage:
              "radial-gradient(ellipse 70% 60% at 50% 30%, hsl(var(--background)) 30%, transparent 80%)",
          }}
        />
        <div
          aria-hidden
          className="absolute -top-32 left-1/2 -translate-x-1/2 w-[900px] h-[420px] pointer-events-none"
          style={{
            background:
              "radial-gradient(ellipse at center, hsl(var(--accent)/0.16) 0%, transparent 60%)",
          }}
        />

        <div className="relative max-w-[1400px] mx-auto px-6 lg:px-12 pt-20 lg:pt-28 pb-16 lg:pb-20">
          <motion.div
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, ease }}
            className="text-[10px] tracking-[0.3em] uppercase text-muted-foreground/80 font-mono mb-8"
          >
            {kicker}
          </motion.div>

          <motion.h1
            initial={{ opacity: 0, y: 24 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.9, ease }}
            className="font-heading font-semibold tracking-[-0.035em] leading-[0.95] text-[clamp(2.5rem,7vw,5.75rem)] max-w-[16ch]"
          >
            {title}
          </motion.h1>

          <motion.p
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, delay: 0.15, ease }}
            className="mt-8 max-w-2xl text-lg lg:text-xl text-muted-foreground leading-relaxed"
          >
            {lead}
          </motion.p>

          {specs && specs.length > 0 && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ duration: 0.8, delay: 0.3 }}
              className="mt-14 grid grid-cols-2 lg:grid-cols-4 divide-x divide-border/70 border-y border-border/70"
            >
              {specs.map((s) => (
                <div key={s.label} className="px-5 lg:px-7 py-6 first:pl-0 last:pr-0">
                  <div className="text-[10px] tracking-[0.28em] uppercase text-muted-foreground mb-2">
                    {s.label}
                  </div>
                  <div className="font-heading font-semibold tracking-[-0.02em] text-xl lg:text-2xl tabular-nums">
                    {s.value}
                  </div>
                </div>
              ))}
            </motion.div>
          )}
        </div>
      </section>

      {/* ── Sections ─────────────────────────────────────────── */}
      <section className="bg-background">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-12 py-20 lg:py-28 space-y-20 lg:space-y-28">
          {sections.map((s, idx) => (
            <motion.div
              key={s.title}
              initial={{ opacity: 0, y: 24 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-80px" }}
              transition={{ duration: 0.7, ease }}
              className="grid lg:grid-cols-12 gap-8 lg:gap-12 border-t border-border/70 pt-12 lg:pt-16"
            >
              <div className="lg:col-span-4">
                <div className="text-[10px] tracking-[0.3em] uppercase text-muted-foreground/80 font-mono mb-4">
                  {s.caption ?? `Section ${String(idx + 1).padStart(2, "0")}`}
                </div>
                <h2 className="font-heading font-semibold tracking-[-0.025em] leading-[1.05] text-3xl lg:text-4xl">
                  {s.title}
                </h2>
              </div>
              <div className="lg:col-span-8 space-y-8">
                {s.lead && (
                  <p className="text-lg lg:text-xl text-muted-foreground leading-relaxed max-w-2xl">
                    {s.lead}
                  </p>
                )}
                {s.bullets && s.bullets.length > 0 && (
                  <ul className="grid sm:grid-cols-2 gap-x-8 gap-y-0">
                    {s.bullets.map((b, i) => (
                      <li
                        key={i}
                        className="flex items-start gap-3 py-4 border-t border-border/60 first:border-t-0 sm:[&:nth-child(2)]:border-t-0"
                      >
                        <Check className="w-4 h-4 mt-1 text-accent shrink-0" strokeWidth={2.5} />
                        <span className="text-foreground/90 leading-relaxed">{b}</span>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </motion.div>
          ))}
        </div>
      </section>

      {/* ── CTA ──────────────────────────────────────────────── */}
      {cta && (
        <section className="border-t border-border/70 bg-background">
          <div className="max-w-[1400px] mx-auto px-6 lg:px-12 py-20 lg:py-24">
            {cta.eyebrow && (
              <div className="text-[10px] tracking-[0.3em] uppercase text-muted-foreground/80 font-mono mb-6">
                {cta.eyebrow}
              </div>
            )}
            <div className="flex flex-col lg:flex-row lg:items-end lg:justify-between gap-8">
              <div className="max-w-2xl">
                <h2 className="font-heading font-semibold tracking-[-0.03em] leading-[1] text-4xl lg:text-6xl">
                  {cta.title}
                </h2>
                {cta.body && (
                  <p className="mt-6 text-muted-foreground text-lg max-w-xl">{cta.body}</p>
                )}
              </div>
              <div className="flex flex-wrap items-center gap-3">
                <Link
                  to={cta.primary.href}
                  className="group inline-flex items-center gap-2 px-6 py-3.5 rounded-full bg-foreground text-background font-medium hover:opacity-90 transition"
                >
                  {cta.primary.label}
                  <ArrowUpRight className="w-4 h-4 transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
                </Link>
                {cta.secondary && (
                  <Link
                    to={cta.secondary.href}
                    className="inline-flex items-center gap-2 px-6 py-3.5 rounded-full border border-border text-foreground hover:bg-muted/50 transition"
                  >
                    {cta.secondary.label}
                  </Link>
                )}
              </div>
            </div>
          </div>
        </section>
      )}
    </Layout>
  );
};

export default EditorialFeaturePage;
