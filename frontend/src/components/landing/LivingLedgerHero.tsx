import { motion, useReducedMotion } from "framer-motion";
import { useEffect, useMemo, useRef, useState } from "react";
import { useCurrency } from "@/hooks/useCurrency";

// Realistic per-currency contribution magnitudes for the hero figure.
// These are intentionally not pulled from an API — they're brand statistics
// shown above the fold, so they must render instantly and never flicker.
// Hero figures are scaled to read cleanly at one-decimal precision:
//   TZS → "940.4M"   KES → "36.6M"   USD → "376.2k"
// (TZS reference 940.4M ≈ KES 36.6M ≈ USD 376.2k at TZS≈25.7/KES, TZS≈2,500/USD.)
const CONTRIBUTIONS_BY_CURRENCY: Record<string, number> = {
  TZS: 940_400_000, // ~940.4M TZS
  KES: 36_600_000,  // ~36.6M KES
  USD: 376_200,     // ~376.2k USD
};

/**
 * LivingLedgerHero
 * --------------------------------------------------------------
 * A "data-as-art" hero. The product itself is the visual:
 *   • Editorial wordmark headline.
 *   • A breathing contribution waveform built from real-feeling data.
 *   • Monumental counters that animate once on mount.
 *   • Hairline grid + tiny clinical labels — feels like a museum
 *     financial print, not a marketing page.
 *
 * Restrained motion only. No bouncy springs, no parallax, no
 * cursor effects. Everything moves slowly, once, and stops.
 * --------------------------------------------------------------
 */

// ───────────────────────── Animated counter ─────────────────────────
const useCountUp = (target: number, duration = 1800, start = true) => {
  const [value, setValue] = useState(0);
  const reduce = useReducedMotion();
  useEffect(() => {
    if (!start) return;
    if (reduce) {
      setValue(target);
      return;
    }
    let raf = 0;
    const t0 = performance.now();
    const tick = (t: number) => {
      const p = Math.min(1, (t - t0) / duration);
      // easeOutExpo
      const eased = p === 1 ? 1 : 1 - Math.pow(2, -10 * p);
      setValue(Math.round(target * eased));
      if (p < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [target, duration, start, reduce]);
  return value;
};

// Compact for small KPIs (events, guests, vendors).
const formatCompact = (n: number) => {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1).replace(/\.0$/, "") + "M";
  if (n >= 1_000) return (n / 1_000).toFixed(1).replace(/\.0$/, "") + "k";
  return n.toLocaleString("en-US");
};

// For the contributions figure we want the magnitude in millions with
// thousand separators on the integer part — e.g. "12,400M" reads cleanly
// as "twelve thousand four hundred million" without overwhelming the strip.
// Contribution figure formatter — one decimal precision so figures like
// "1,240.4M" or "48.2M" or "420.5k" all read consistently across currencies.
const formatMillions = (n: number) => {
  if (n >= 1_000_000) {
    const millions = n / 1_000_000;
    return `${millions.toLocaleString("en-US", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}M`;
  }
  if (n >= 1_000) {
    const thousands = n / 1_000;
    return `${thousands.toLocaleString("en-US", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}k`;
  }
  return n.toLocaleString("en-US");
};

// ───────────────────────── Waveform geometry ─────────────────────────
// Deterministic pseudo-random so the SSR/CSR output matches and the
// shape feels "real" rather than noisy.
const seededWave = (count: number, seed = 7) => {
  const out: number[] = [];
  let s = seed;
  for (let i = 0; i < count; i++) {
    s = (s * 9301 + 49297) % 233280;
    const r = s / 233280;
    // base = slow rising trend; add gentle harmonic + small noise
    const trend = 0.35 + (i / count) * 0.45;
    const harmonic = Math.sin(i / 4.2) * 0.12 + Math.sin(i / 1.8) * 0.06;
    const noise = (r - 0.5) * 0.08;
    out.push(Math.max(0.08, Math.min(0.98, trend + harmonic + noise)));
  }
  return out;
};

const buildPath = (vals: number[], w: number, h: number) => {
  const stepX = w / (vals.length - 1);
  const pts = vals.map((v, i) => [i * stepX, h - v * h] as const);
  // smooth Catmull-Rom → Bezier
  let d = `M ${pts[0][0]} ${pts[0][1]}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] ?? pts[i];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[i + 2] ?? p2;
    const cp1x = p1[0] + (p2[0] - p0[0]) / 6;
    const cp1y = p1[1] + (p2[1] - p0[1]) / 6;
    const cp2x = p2[0] - (p3[0] - p1[0]) / 6;
    const cp2y = p2[1] - (p3[1] - p1[1]) / 6;
    d += ` C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${p2[0]} ${p2[1]}`;
  }
  return d;
};

// ───────────────────────── Component ─────────────────────────
const LivingLedgerHero = () => {
  const reduce = useReducedMotion();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  // Locale-aware contribution figure (TZS for nuru.tz, KES for nuru.ke,
  // USD elsewhere). Falls back to USD if the resolved currency isn't one
  // of the three known magnitudes above.
  const { currency } = useCurrency();
  const contributionsTarget =
    CONTRIBUTIONS_BY_CURRENCY[currency] ?? CONTRIBUTIONS_BY_CURRENCY.USD;

  // Counters
  const events = useCountUp(12480, 1800, mounted);
  const contributions = useCountUp(contributionsTarget, 2200, mounted);
  const guests = useCountUp(346000, 2000, mounted);
  const vendors = useCountUp(1240, 1600, mounted);

  // Waveform
  const W = 1200;
  const H = 260;
  const vals = useMemo(() => seededWave(80, 11), []);
  const path = useMemo(() => buildPath(vals, W, H), [vals]);
  const areaPath = `${path} L ${W} ${H} L 0 ${H} Z`;

  // Marker — small dot that walks along the waveform once
  const markerRef = useRef<SVGCircleElement | null>(null);
  const [marker, setMarker] = useState({ x: 0, y: H });
  useEffect(() => {
    if (!mounted) return;
    if (reduce) {
      const i = vals.length - 1;
      setMarker({ x: (W / (vals.length - 1)) * i, y: H - vals[i] * H });
      return;
    }
    let raf = 0;
    const t0 = performance.now();
    const dur = 2400;
    const tick = (t: number) => {
      const p = Math.min(1, (t - t0) / dur);
      const eased = 1 - Math.pow(1 - p, 3);
      const idx = eased * (vals.length - 1);
      const i0 = Math.floor(idx);
      const i1 = Math.min(vals.length - 1, i0 + 1);
      const f = idx - i0;
      const stepX = W / (vals.length - 1);
      const x = i0 * stepX + f * stepX;
      const y = H - (vals[i0] + (vals[i1] - vals[i0]) * f) * H;
      setMarker({ x, y });
      if (p < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [mounted, reduce, vals]);

  return (
    <section className="relative overflow-hidden bg-background text-foreground">
      {/* Hairline grid backdrop — extremely subtle */}
      <div
        aria-hidden
        className="absolute inset-0 opacity-[0.35] pointer-events-none"
        style={{
          backgroundImage:
            "linear-gradient(to right, hsl(var(--border)/0.55) 1px, transparent 1px), linear-gradient(to bottom, hsl(var(--border)/0.55) 1px, transparent 1px)",
          backgroundSize: "96px 96px",
          maskImage:
            "radial-gradient(ellipse 80% 70% at 50% 40%, hsl(var(--background)) 35%, transparent 85%)",
          WebkitMaskImage:
            "radial-gradient(ellipse 80% 70% at 50% 40%, hsl(var(--background)) 35%, transparent 85%)",
        }}
      />

      {/* Single warm glow — the only color "moment" */}
      <div
        aria-hidden
        className="absolute -top-32 left-1/2 -translate-x-1/2 w-[1100px] h-[520px] pointer-events-none"
        style={{
          background:
            "radial-gradient(ellipse at center, hsl(var(--accent)/0.18) 0%, transparent 60%)",
        }}
      />

      <div className="relative max-w-[1400px] mx-auto px-6 lg:px-12 pt-24 lg:pt-32 pb-20 lg:pb-24">
        {/* ── Headline (slogan from company profile) ── */}
        <motion.h1
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.9, ease: [0.22, 1, 0.36, 1] }}
          className="font-heading font-semibold tracking-[-0.04em] leading-[0.9] text-[clamp(3.25rem,11vw,9.5rem)] mb-16 lg:mb-20"
        >
          <span className="block text-foreground">Plan Smarter.</span>
          <span className="block">
            <span className="relative inline-block">
              <span className="relative z-10">Celebrate Better.</span>
              <motion.span
                aria-hidden
                initial={{ scaleX: 0 }}
                animate={{ scaleX: 1 }}
                transition={{ duration: 1.2, delay: 0.6, ease: [0.22, 1, 0.36, 1] }}
                className="absolute left-0 right-0 bottom-[0.12em] h-[0.18em] bg-accent origin-left -z-0"
                style={{ mixBlendMode: "multiply" }}
              />
            </span>
          </span>
        </motion.h1>

        {/* ── The Living Ledger: waveform as art ── */}
        <motion.figure
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 1, delay: 0.3 }}
          className="relative border-y border-border/70 pt-12 sm:pt-8 py-8 lg:py-10 mb-12"
        >
          {/* tiny corner caption — stacks on mobile to avoid overlap */}
          <div className="absolute top-3 left-0 right-0 flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between text-[10px] tracking-[0.25em] uppercase text-muted-foreground/70">
            <figcaption className="truncate">
              Fig. 01 — Contributions, last 90 days
            </figcaption>
            <span className="shrink-0">+24.6% MoM</span>
          </div>

          {/* Y-axis tick labels */}
          <div className="flex">
            <div className="hidden md:flex flex-col justify-between pr-4 py-2 text-[10px] text-muted-foreground/60 font-mono w-12 text-right">
              <span>10M</span>
              <span>5M</span>
              <span>2M</span>
              <span>0</span>
            </div>

            <div className="relative flex-1">
              <svg
                viewBox={`0 0 ${W} ${H}`}
                preserveAspectRatio="none"
                className="w-full h-[200px] md:h-[260px] block"
                role="img"
                aria-label="Animated contribution volume chart"
              >
                <defs>
                  <linearGradient id="ll-area" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="hsl(var(--accent))" stopOpacity="0.28" />
                    <stop offset="100%" stopColor="hsl(var(--accent))" stopOpacity="0" />
                  </linearGradient>
                  <linearGradient id="ll-stroke" x1="0" y1="0" x2="1" y2="0">
                    <stop offset="0%" stopColor="hsl(var(--foreground))" stopOpacity="0.9" />
                    <stop offset="100%" stopColor="hsl(var(--foreground))" stopOpacity="0.55" />
                  </linearGradient>
                  {/* horizontal hairlines */}
                  <pattern id="ll-grid" width={W} height={H / 4} patternUnits="userSpaceOnUse">
                    <line x1="0" y1="0" x2={W} y2="0" stroke="hsl(var(--border))" strokeWidth="1" />
                  </pattern>
                </defs>

                <rect width={W} height={H} fill="url(#ll-grid)" opacity="0.7" />

                {/* area */}
                <motion.path
                  d={areaPath}
                  fill="url(#ll-area)"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ duration: 1.2, delay: 0.6 }}
                />

                {/* line */}
                <motion.path
                  d={path}
                  fill="none"
                  stroke="url(#ll-stroke)"
                  strokeWidth="1.6"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  initial={{ pathLength: 0 }}
                  animate={{ pathLength: 1 }}
                  transition={{ duration: 2.2, delay: 0.5, ease: [0.22, 1, 0.36, 1] }}
                />

                {/* moving marker */}
                <g>
                  <line
                    x1={marker.x}
                    y1={0}
                    x2={marker.x}
                    y2={H}
                    stroke="hsl(var(--foreground))"
                    strokeOpacity="0.12"
                    strokeWidth="1"
                    strokeDasharray="2 4"
                  />
                  <circle cx={marker.x} cy={marker.y} r="6" fill="hsl(var(--accent))" opacity="0.25" />
                  <circle
                    ref={markerRef}
                    cx={marker.x}
                    cy={marker.y}
                    r="3"
                    fill="hsl(var(--foreground))"
                  />
                </g>
              </svg>

              {/* X-axis ticks */}
              <div className="flex justify-between mt-3 text-[10px] font-mono text-muted-foreground/60 px-1">
                <span>JAN</span>
                <span>FEB</span>
                <span>MAR</span>
                <span>APR</span>
                <span className="text-foreground">TODAY</span>
              </div>
            </div>
          </div>
        </motion.figure>

        {/* ── Monumental KPI strip ── */}
        <div className="grid grid-cols-2 lg:grid-cols-4 divide-x divide-border/70 border-y border-border/70">
          {[
            {
              label: "Events orchestrated",
              value: events,
              format: formatCompact,
              prefix: "",
              note: "since 2023",
            },
            {
              label: "Contributions cleared",
              value: contributions,
              format: formatMillions,
              prefix: `${currency} `,
              note: "settled in 24h",
            },
            {
              label: "Guests checked in",
              value: guests,
              format: formatCompact,
              prefix: "",
              note: "via NFC & link",
            },
            {
              label: "Verified vendors",
              value: vendors,
              format: formatCompact,
              prefix: "",
              note: "across 14 cities",
            },
          ].map((kpi, i) => (
            <motion.div
              key={kpi.label}
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.7, delay: 0.6 + i * 0.08 }}
              className="px-5 lg:px-7 py-7 lg:py-9 first:pl-0 last:pr-0"
            >
              <div className="text-[10px] tracking-[0.28em] uppercase text-muted-foreground mb-3">
                {kpi.label}
              </div>
              <div className="font-heading font-semibold tracking-[-0.03em] leading-none text-[clamp(1.5rem,3vw,2.5rem)] tabular-nums break-all">
                {kpi.prefix}
                {kpi.format(kpi.value)}
              </div>
              <div className="mt-3 text-xs text-muted-foreground/80 font-mono">
                — {kpi.note}
              </div>
            </motion.div>
          ))}
        </div>

        {/* ── Footer rail ── */}
        <div className="mt-10 flex flex-col md:flex-row md:items-center md:justify-between gap-4 text-[10px] tracking-[0.25em] uppercase text-muted-foreground/70">
          <div className="flex items-center gap-6 flex-wrap">
            <span>M-Pesa</span>
            <span className="opacity-30">/</span>
            <span>Mixx by Yas</span>
            <span className="opacity-30">/</span>
            <span>Airtel Money</span>
            <span className="opacity-30">/</span>
            <span>Visa - Mastercard</span>
            <span className="opacity-30">/</span>
            <span>Bank transfer</span>
          </div>
          <div className="flex items-center gap-2 text-foreground/70">
            <span className="w-6 h-px bg-foreground/40" />
            <span>Audit-grade. End-to-end.</span>
          </div>
        </div>
      </div>
    </section>
  );
};

export default LivingLedgerHero;
