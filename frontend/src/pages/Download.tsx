import { motion } from "framer-motion";
import { Link } from "react-router-dom";
import { ArrowUpRight, Check } from "lucide-react";
import Layout from "@/components/layout/Layout";
import { useMeta } from "@/hooks/useMeta";
import AppStoreIcon from "@/assets/icons/app-store.svg";
import GooglePlayIcon from "@/assets/icons/google-play.svg";
import {
  APP_STORE_URL,
  PLAY_STORE_URL,
} from "@/components/landing/DownloadAppSection";

const Download = () => {
  useMeta({
    title: "Download Nuru App",
    description:
      "Download Nuru on iOS and Android. Plan events, manage contributions, sell tickets and stay in touch with vendors and guests, all from your phone.",
  });

  const highlights = [
    "Open and manage event workspaces on the go.",
    "Track contributions, payments and tickets in real time.",
    "Chat with vendors, committees and guests in one place.",
    "Scan QR codes for check-in and ticket verification.",
    "Receive instant updates and reminders via push notifications.",
    "Works smoothly on slower connections and modest devices.",
  ];

  const steps = [
    {
      n: "01",
      title: "Open your app store",
      body: "Tap the App Store on iPhone or Google Play on Android using the buttons below.",
    },
    {
      n: "02",
      title: "Install Nuru",
      body: "Search for Nuru or use the direct links. Installation is free and the app size is light.",
    },
    {
      n: "03",
      title: "Sign in or create an account",
      body: "Use your phone number or email. If you already have a Nuru account on the web, the same login works on mobile.",
    },
    {
      n: "04",
      title: "Start planning",
      body: "Open a workspace, join an event, pledge a contribution, or buy a ticket, everything stays in sync with the web.",
    },
  ];

  return (
    <Layout>
      {/* Hero */}
      <section className="relative border-b border-border/70">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-12 pt-32 pb-20 lg:pt-40 lg:pb-28">
          <div className="grid lg:grid-cols-12 gap-10 items-end">
            <div className="lg:col-span-3 text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono">
              § Download
            </div>
            <motion.div
              initial={{ opacity: 0, y: 24 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
              className="lg:col-span-9"
            >
              <h1 className="font-heading font-semibold tracking-[-0.04em] leading-[0.95] text-[clamp(2.5rem,7vw,6rem)] text-foreground">
                Download
                <br />
                <span className="text-muted-foreground">Nuru App</span>
              </h1>
              <p className="mt-8 max-w-2xl text-foreground/80 text-lg lg:text-xl leading-relaxed font-heading">
                Plan smarter and celebrate better, wherever you are. The Nuru app
                brings the full workspace to iOS and Android, with the speed and
                simplicity events demand.
              </p>


              <div className="mt-10 flex flex-wrap gap-4">
                <a
                  href={APP_STORE_URL}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="group flex items-center gap-4 bg-foreground text-background rounded-2xl px-6 py-4 hover:bg-foreground/90 transition-all min-w-[220px]"
                >
                  <img src={AppStoreIcon} alt="" className="w-10 h-10 shrink-0" />
                  <div className="flex flex-col text-left leading-tight">
                    <span className="text-[10px] tracking-[0.18em] uppercase text-background/60 font-mono">
                      Download on the
                    </span>
                    <span className="font-heading font-medium text-lg">
                      App Store
                    </span>
                  </div>
                </a>
                <a
                  href={PLAY_STORE_URL}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="group flex items-center gap-4 bg-foreground text-background rounded-2xl px-6 py-4 hover:bg-foreground/90 transition-all min-w-[220px]"
                >
                  <img src={GooglePlayIcon} alt="" className="icon-original w-10 h-10 shrink-0" />
                  <div className="flex flex-col text-left leading-tight">
                    <span className="text-[10px] tracking-[0.18em] uppercase text-background/60 font-mono">
                      Get it on
                    </span>
                    <span className="font-heading font-medium text-lg">
                      Google Play
                    </span>
                  </div>
                </a>
              </div>
            </motion.div>
          </div>
        </div>
      </section>

      {/* Highlights */}
      <section className="relative">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-12 py-24 lg:py-32">
          <div className="grid lg:grid-cols-12 gap-10">
            <div className="lg:col-span-3 text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono">
              § What you get
            </div>
            <div className="lg:col-span-9">
              <h2 className="font-heading font-semibold tracking-[-0.035em] leading-[1] text-[clamp(2rem,4.5vw,3.5rem)] text-foreground mb-12">
                Everything Nuru does, now on mobile.
              </h2>
              <ul className="grid sm:grid-cols-2 gap-x-10 gap-y-5">
                {highlights.map((h) => (
                  <li
                    key={h}
                    className="flex gap-3 items-start text-foreground/80 text-base lg:text-lg leading-relaxed border-t border-border/70 pt-5"
                  >
                    <Check className="w-5 h-5 text-foreground shrink-0 mt-1" />
                    <span>{h}</span>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* Steps */}
      <section className="relative bg-foreground text-background">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-12 py-24 lg:py-32">
          <div className="grid lg:grid-cols-12 gap-10 mb-16">
            <div className="lg:col-span-3 text-[10px] tracking-[0.28em] uppercase text-background/50 font-mono">
              § How to install
            </div>
            <div className="lg:col-span-9">
              <h2 className="font-heading font-semibold tracking-[-0.035em] leading-[0.95] text-[clamp(2rem,5vw,4rem)]">
                Four steps.
                <br />
                <span className="text-background/40">Under two minutes.</span>
              </h2>
            </div>
          </div>

          <ol className="grid sm:grid-cols-2 lg:grid-cols-4 gap-px bg-background/10 border border-background/10 rounded-2xl overflow-hidden">
            {steps.map((s) => (
              <li key={s.n} className="bg-foreground p-8 lg:p-10">
                <div className="text-[10px] font-mono text-background/40 tracking-[0.28em] mb-6">
                  {s.n}
                </div>
                <h3 className="font-heading font-medium text-xl lg:text-2xl text-background mb-3 tracking-[-0.015em]">
                  {s.title}
                </h3>
                <p className="text-background/60 text-sm lg:text-base leading-relaxed">
                  {s.body}
                </p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      {/* Requirements + closing */}
      <section className="relative border-t border-border/70">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-12 py-24 lg:py-32">
          <div className="grid lg:grid-cols-12 gap-10">
            <div className="lg:col-span-3 text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono">
              § Requirements
            </div>
            <div className="lg:col-span-9 grid sm:grid-cols-2 gap-px bg-border/70 border border-border/70 rounded-2xl overflow-hidden">
              <div className="bg-background p-8">
                <div className="text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono mb-2">
                  iOS
                </div>
                <div className="font-heading text-lg text-foreground">
                  iPhone running iOS 13 or later.
                </div>
              </div>
              <div className="bg-background p-8">
                <div className="text-[10px] tracking-[0.28em] uppercase text-muted-foreground font-mono mb-2">
                  Android
                </div>
                <div className="font-heading text-lg text-foreground">
                  Android 7.0 (Nougat) or later.
                </div>
              </div>
            </div>
          </div>

          <div className="mt-20 pt-10 border-t border-border/70 flex flex-col sm:flex-row sm:items-center gap-6">
            <p className="font-heading font-semibold tracking-[-0.02em] text-2xl lg:text-3xl text-foreground max-w-xl">
              Already on Nuru? Your account is ready on mobile.
            </p>
            <Link
              to="/login"
              className="sm:ml-auto inline-flex items-center justify-center gap-2 bg-foreground text-background px-7 h-12 rounded-full text-sm font-medium hover:bg-foreground/90 transition-colors"
            >
              Sign in
              <ArrowUpRight className="w-4 h-4" />
            </Link>
          </div>
        </div>
      </section>
    </Layout>
  );
};

export default Download;
