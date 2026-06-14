import { useState } from "react";
import { motion } from "framer-motion";
import { Trash2, Send, Check, ShieldAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useToast } from "@/hooks/use-toast";
import Layout from "@/components/layout/Layout";
import { useMeta } from "@/hooks/useMeta";
import { accountDeletionApi } from "@/lib/api/accountDeletion";

const DataDeletion = () => {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isSubmitted, setIsSubmitted] = useState(false);
  const [form, setForm] = useState({
    full_name: "",
    email: "",
    phone: "",
    reason: "",
    delete_scope: "account_and_data" as "account_and_data" | "data_only",
  });
  const { toast } = useToast();

  useMeta({
    title: "Request Account & Data Deletion | Nuru",
    description:
      "Request deletion of your Nuru account and personal data. We process all requests within 30 days as required by Google Play and applicable privacy law.",
  });

  const update = (k: keyof typeof form) => (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>,
  ) => setForm((f) => ({ ...f, [k]: e.target.value as any }));

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (isSubmitting) return;
    if (!form.full_name.trim()) {
      toast({ title: "Please share your full name", variant: "destructive" as any });
      return;
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email.trim())) {
      toast({ title: "Please enter a valid email", variant: "destructive" as any });
      return;
    }
    setIsSubmitting(true);
    try {
      const res = await accountDeletionApi.submit({
        full_name: form.full_name.trim().slice(0, 200),
        email: form.email.trim().slice(0, 255),
        phone: form.phone.trim().slice(0, 32) || undefined,
        reason: form.reason.trim().slice(0, 2000) || undefined,
        delete_scope: form.delete_scope,
        source: "web",
      });
      if (res.success) {
        setIsSubmitted(true);
        toast({ title: "Request received", description: "We'll process your request within 30 days." });
      } else {
        toast({ title: res.message || "Couldn't submit your request", variant: "destructive" as any });
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Layout>
      <div className="min-h-screen pt-32 pb-24 px-6">
        <div className="max-w-3xl mx-auto">
          <motion.div initial={{ opacity: 0, y: 30 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5 }} className="mb-10">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-muted text-xs font-medium text-muted-foreground mb-4">
              <ShieldAlert className="w-3.5 h-3.5" /> Privacy Request
            </div>
            <h1 className="text-3xl sm:text-4xl md:text-5xl font-bold text-foreground tracking-tight mb-4">
              Request Account &amp; Data Deletion
            </h1>
            <p className="text-base text-muted-foreground max-w-2xl">
              Use this form to ask Nuru to delete your account and the personal data we hold about you. Requests are
              processed within 30 days. We may retain limited records (such as financial transactions, chargeback
              evidence, fraud-prevention signals, and content required by law) for the periods our policies and the
              law require.
            </p>
          </motion.div>

          <div className="grid sm:grid-cols-2 gap-4 mb-8">
            <div className="p-5 rounded-2xl border border-border bg-muted/40">
              <h3 className="font-semibold mb-1">What gets deleted</h3>
              <ul className="text-sm text-muted-foreground space-y-1 list-disc pl-4">
                <li>Your profile, name, photo, phone &amp; email</li>
                <li>Posts, moments, comments &amp; reactions you created</li>
                <li>Direct messages &amp; uploaded media</li>
                <li>Event RSVPs, contributions &amp; checklists you own</li>
                <li>Device tokens, push subscriptions &amp; sessions</li>
              </ul>
            </div>
            <div className="p-5 rounded-2xl border border-border bg-muted/40">
              <h3 className="font-semibold mb-1">What we may retain</h3>
              <ul className="text-sm text-muted-foreground space-y-1 list-disc pl-4">
                <li>Payment &amp; payout records (legal/tax: up to 7 years)</li>
                <li>Aggregated, de-identified analytics</li>
                <li>Records needed to resolve disputes or fraud</li>
                <li>Content required by law enforcement requests</li>
              </ul>
            </div>
          </div>

          {!isSubmitted ? (
            <form onSubmit={handleSubmit} className="space-y-5 p-6 sm:p-8 rounded-3xl border border-border bg-card">
              <div>
                <label htmlFor="full_name" className="block text-sm font-medium mb-2">Full name *</label>
                <Input id="full_name" required maxLength={200} value={form.full_name} onChange={update("full_name")} placeholder="As shown in your Nuru account" className="h-12 rounded-xl" />
              </div>
              <div className="grid sm:grid-cols-2 gap-4">
                <div>
                  <label htmlFor="email" className="block text-sm font-medium mb-2">Email *</label>
                  <Input id="email" type="email" required maxLength={255} value={form.email} onChange={update("email")} placeholder="The email on your account" className="h-12 rounded-xl" />
                </div>
                <div>
                  <label htmlFor="phone" className="block text-sm font-medium mb-2">Phone (optional)</label>
                  <Input id="phone" type="tel" maxLength={32} value={form.phone} onChange={update("phone")} placeholder="+255…" className="h-12 rounded-xl" />
                </div>
              </div>
              <div>
                <label htmlFor="delete_scope" className="block text-sm font-medium mb-2">What should we delete?</label>
                <select
                  id="delete_scope"
                  value={form.delete_scope}
                  onChange={update("delete_scope")}
                  className="w-full h-12 rounded-xl border border-input bg-background px-3 text-sm"
                >
                  <option value="account_and_data">My account and all my personal data</option>
                  <option value="data_only">Only specific personal data (keep my account)</option>
                </select>
              </div>
              <div>
                <label htmlFor="reason" className="block text-sm font-medium mb-2">Reason / details (optional)</label>
                <Textarea id="reason" maxLength={2000} value={form.reason} onChange={update("reason")} placeholder="Tell us anything that helps us process your request faster · e.g., specific data you want removed." rows={5} className="rounded-xl resize-none" />
              </div>
              <Button type="submit" disabled={isSubmitting} className="w-full sm:w-auto rounded-full h-12 px-8">
                {isSubmitting ? (
                  <span className="flex items-center gap-2">
                    <motion.div animate={{ rotate: 360 }} transition={{ duration: 1, repeat: Infinity, ease: "linear" }} className="w-4 h-4 border-2 border-current border-t-transparent rounded-full" />
                    Submitting…
                  </span>
                ) : (
                  <span className="flex items-center gap-2"><Trash2 className="w-4 h-4" /> Submit deletion request <Send className="w-4 h-4" /></span>
                )}
              </Button>
              <p className="text-xs text-muted-foreground">
                Submitting this form does not immediately delete your account. We will email you to confirm your
                identity before processing the request.
              </p>
            </form>
          ) : (
            <motion.div initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} className="text-center py-16 px-8 rounded-3xl border border-border bg-muted/40">
              <div className="w-16 h-16 rounded-full bg-foreground flex items-center justify-center mx-auto mb-6">
                <Check className="w-8 h-8 text-background" />
              </div>
              <h3 className="text-2xl font-semibold mb-2">Request received</h3>
              <p className="text-muted-foreground mb-2">We've logged your deletion request and will email you within 30 days.</p>
              <p className="text-sm text-muted-foreground">
                Need anything else? Email <a href="mailto:privacy@nuru.tz" className="underline">privacy@nuru.tz</a>.
              </p>
            </motion.div>
          )}

          <div className="mt-12 text-sm text-muted-foreground space-y-2">
            <p><strong>Developer:</strong> Nuru — Arusha, Tanzania.</p>
            <p><strong>Privacy contact:</strong> <a href="mailto:privacy@nuru.tz" className="underline">privacy@nuru.tz</a></p>
            <p><strong>Privacy policy:</strong> <a href="/privacy-policy" className="underline">/privacy-policy</a></p>
          </div>
        </div>
      </div>
    </Layout>
  );
};

export default DataDeletion;