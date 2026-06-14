import { motion } from "framer-motion";
import { Link } from "react-router-dom";
import Layout from "@/components/layout/Layout";
import { useMeta } from "@/hooks/useMeta";
import { Button } from "@/components/ui/button";
import { useLanguage } from '@/lib/i18n/LanguageContext';

const CookiePolicy = () => {
  const { t } = useLanguage();
  useMeta({
    title: "Cookie Policy | Nuru",
    description: "Learn how Nuru Workspace uses cookies and similar technologies to improve your experience on the platform."
  });

  const sections = [
    {
      title: "What Are Cookies",
      content: [
        "Cookies are small text files stored on your device when you visit a website.",
        "They help the website remember your preferences and improve your experience.",
        "Nuru uses cookies and similar technologies such as local storage to operate the platform effectively."
      ]
    },
    {
      title: "Essential Cookies",
      content: [
        "These cookies are necessary for the platform to function and cannot be disabled.",
        "They enable core features such as authentication, session management, and security.",
        "Without these cookies, services you have asked for cannot be provided.",
        "Examples: login session tokens, CSRF protection tokens, cookie consent preferences."
      ]
    },
    {
      title: "Functional Cookies",
      content: [
        "These cookies remember your preferences and settings to enhance your experience.",
        "Examples: theme preference (light or dark mode), language settings, recently viewed services.",
        "Disabling these cookies may reduce the quality of your experience but will not prevent platform use."
      ]
    },
    {
      title: "Analytics Cookies",
      content: [
        "These cookies help us understand how users interact with the platform.",
        "They collect information such as pages visited, time spent, and navigation patterns.",
        "Data is aggregated and anonymised · it does not personally identify you.",
        "We use this data to improve platform performance and user experience."
      ]
    },
    {
      title: "How We Use Cookies",
      content: [
        "Keep you signed in securely across sessions.",
        "Remember your display preferences and settings.",
        "Understand which features are most used to guide improvements.",
        "Detect and prevent fraudulent activity.",
        "Ensure the platform loads efficiently and performs well."
      ]
    },
    {
      title: "Third-Party Cookies",
      content: [
        "We may use third-party services that set their own cookies (e.g., payment processors, analytics providers).",
        "These third parties have their own privacy and cookie policies.",
        "We do not allow third-party advertising cookies on the platform.",
        "We do not sell cookie data to any third party."
      ]
    },
    {
      title: "Managing Cookies",
      content: [
        "You can manage cookie preferences through the consent banner when you first visit the platform.",
        "Most web browsers allow you to control cookies through their settings.",
        "You can delete existing cookies and configure your browser to block future cookies.",
        "Blocking essential cookies may prevent you from using certain platform features.",
        "For mobile devices, refer to your device settings for cookie management options."
      ]
    },
    {
      title: "Data Retention",
      content: [
        "Session cookies are deleted when you close your browser.",
        "Persistent cookies remain until they expire or you delete them.",
        "Cookie consent preferences are stored for 12 months before we ask again.",
        "Analytics data derived from cookies is retained in aggregated, anonymised form."
      ]
    },
    {
      title: "Updates to This Policy",
      content: [
        "We may update this Cookie Policy from time to time to reflect changes in our practices or legal requirements.",
        "Significant changes will be communicated through a notice on the platform.",
        "Continued use of the platform after changes constitutes acceptance of the updated policy."
      ]
    }
  ];

  return (
    <Layout>
      <div className="min-h-screen pt-32 pb-24 px-6">
        <div className="max-w-3xl mx-auto">
          <motion.div initial={{ opacity: 0, y: 30 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.6 }} className="mb-16">
            <h1 className="text-4xl sm:text-5xl md:text-6xl font-bold text-foreground tracking-tight mb-6">{t("cookie_policy")}</h1>
            <p className="text-muted-foreground">Last updated: February 2025</p>
          </motion.div>

          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5, delay: 0.1 }} className="mb-16">
            <p className="text-lg text-muted-foreground leading-relaxed">
              This policy explains how Nuru Workspace uses cookies and similar technologies to recognise you when you visit our platform, and what choices you have regarding their use.
            </p>
          </motion.div>

          <div className="space-y-16">
            {sections.map((section, index) => (
              <motion.div key={section.title} initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5, delay: 0.15 + index * 0.03 }}>
                <h2 className="text-2xl font-semibold text-foreground mb-6">{index + 1}. {section.title}</h2>
                <ul className="space-y-4">
                  {section.content.map((item, i) => (
                    <li key={i} className="flex items-start gap-3">
                      <span className="w-1.5 h-1.5 rounded-full bg-muted-foreground mt-2.5 flex-shrink-0" />
                      <span className="text-muted-foreground leading-relaxed">{item}</span>
                    </li>
                  ))}
                </ul>
              </motion.div>
            ))}
          </div>

          <motion.div initial={{ opacity: 0, y: 30 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5, delay: 0.5 }} className="mt-20 p-8 bg-muted/50 rounded-3xl">
            <h2 className="text-xl font-semibold text-foreground mb-3">Questions about cookies?</h2>
            <p className="text-muted-foreground mb-6">Contact us at privacy@nuru.tz or review our Privacy Policy.</p>
            <div className="flex flex-wrap gap-3">
              <Button asChild variant="outline" className="rounded-full h-10 px-6"><Link to="/privacy-policy">{t("privacy_policy")}</Link></Button>
              <Button asChild variant="outline" className="rounded-full h-10 px-6"><Link to="/terms">{t("terms_of_service")}</Link></Button>
            </div>
          </motion.div>
        </div>
      </div>
    </Layout>
  );
};

export default CookiePolicy;
