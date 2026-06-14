import { motion } from "framer-motion";
import { Link } from "react-router-dom";
import Layout from "@/components/layout/Layout";
import { useMeta } from "@/hooks/useMeta";
import { Button } from "@/components/ui/button";
import { useLanguage } from '@/lib/i18n/LanguageContext';

const PrivacyPolicy = () => {
  const { t } = useLanguage();
  useMeta({
    title: "Privacy Policy | Nuru",
    description: "Learn how Nuru Workspace collects, uses, and protects your personal information, including media content, event data, and payment details."
  });

  const sections = [
    {
      title: "Information You Provide",
      content: [
        "Full name, display name, phone number, and email address",
        "Profile photo, bio, and account preferences",
        "Payment and billing details for bookings, tickets, and contributions",
        "Event information including dates, locations, guest lists, and budgets",
        "Service listings, portfolio content (images, videos, descriptions), and intro media",
        "Messages sent through the platform's messaging system",
        "Posts, moments, comments, and social interactions",
        "Support requests and feedback"
      ]
    },
    {
      title: "Information Collected Automatically",
      content: [
        "Device information (type, operating system, browser)",
        "IP address and approximate location",
        "Usage data including pages visited, features used, and time spent",
        "Session information and cookies",
        "Referral source and navigation patterns"
      ]
    },
    {
      title: "Media Content We Store",
      content: [
        "Profile photos and avatar images",
        "Event cover images, gallery photos, and invitation designs",
        "Vendor portfolio images, videos, and intro recordings",
        "Moment photos and videos shared on the social feed",
        "Post images and attachments",
        "Photo Library images shared by Vendors for events"
      ]
    },
    {
      title: "How We Use Your Information",
      content: [
        "Create and manage your account",
        "Process bookings, payments, contributions, and ticket purchases",
        "Facilitate connections between Organisers and Vendors",
        "Send event updates, reminders, and booking notifications",
        "Enable social features (posts, moments, circles, communities)",
        "Deliver and display Photo Libraries and event media",
        "Enable messaging between Users",
        "Process NFC Card issuance and management",
        "Resolve disputes between Users",
        "Improve platform security and prevent fraud",
        "Comply with legal obligations"
      ]
    },
    {
      title: "Media and Content Processing",
      content: [
        "Uploaded images and videos may be compressed, resized, or optimized for performance",
        "Thumbnails and previews are generated automatically from uploaded media",
        "Content visibility depends on privacy settings chosen by the User",
        "When you delete content, we remove it from public visibility promptly",
        "Content shared with or downloaded by other Users cannot be recalled after sharing",
        "Event-related content may be retained for dispute resolution purposes"
      ]
    },
    {
      title: "Third-Party Services",
      content: [
        "We use ipapi.co to detect your approximate country based on your IP address. This is used solely to pre-select your country code when entering a phone number. Your IP address is sent to ipapi.co for this purpose · no other personal data is shared. You can review ipapi.co's privacy policy at ipapi.co/privacy.",
        "We use third-party payment processors to handle transactions securely. Your payment details are processed directly by these providers and are not stored on our servers.",
        "We use cloud infrastructure providers to host and deliver the platform reliably.",
        "We do not sell your personal data to third parties",
        "We do not share your data with advertisers for targeted advertising"
      ]
    },
    {
      title: "Data Sharing",
      content: [
        "Event participants receive necessary information for coordination (e.g., guest lists, RSVP status)",
        "Vendors and Organisers receive relevant data to facilitate bookings",
        "We may share data with law enforcement when required by law or court order"
      ]
    },
    {
      title: "Data Security",
      content: [
        "SSL/TLS encryption for all data in transit",
        "Encrypted data storage with restricted access",
        "Regular security reviews and updates",
        "Secure authentication mechanisms",
        "Access controls limiting employee access to personal data",
        "No system is completely secure, and we cannot guarantee absolute security"
      ]
    },
    {
      title: "Your Rights",
      content: [
        "Access: Request a copy of your personal data held by us",
        "Correction: Request correction of inaccurate or incomplete data",
        "Deletion: Request deletion of your personal data and account",
        "Portability: Request your data in a portable, machine-readable format",
        "Objection: Object to certain processing of your data",
        "Some data may be retained after deletion where required by law or for dispute resolution"
      ]
    }
  ];

  return (
    <Layout>
      <div className="min-h-screen pt-32 pb-24 px-6">
        <div className="max-w-3xl mx-auto">
          {/* Header */}
          <motion.div
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
            className="mb-16"
          >
            <h1 className="text-4xl sm:text-5xl md:text-6xl font-bold text-foreground tracking-tight mb-6">
              Privacy Policy
            </h1>
            <p className="text-muted-foreground">
              Last updated: February 2025
            </p>
          </motion.div>

          {/* Intro */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: 0.1 }}
            className="mb-16"
          >
            <p className="text-lg text-muted-foreground leading-relaxed">
              Your privacy matters to us. This policy explains how Nuru Workspace collects, uses, stores, and protects your personal information when you use our event management platform, including media uploads, social features, payment processing, and all related services.
            </p>
          </motion.div>

          {/* Sections */}
          <div className="space-y-16">
            {sections.map((section, index) => (
              <motion.div
                key={section.title}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5, delay: 0.15 + index * 0.04 }}
              >
                <h2 className="text-2xl font-semibold text-foreground mb-6">
                  {section.title}
                </h2>
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

          {/* Contact */}
          <motion.div
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: 0.5 }}
            className="mt-20 p-8 bg-muted/50 rounded-3xl"
          >
            <h2 className="text-xl font-semibold text-foreground mb-3">
              Questions about privacy?
            </h2>
            <p className="text-muted-foreground mb-6">
              Contact us at privacy@nuru.tz or review our full Terms of Service.
            </p>
            <div className="flex flex-wrap gap-3">
              <Button asChild variant="outline" className="rounded-full h-10 px-6">
                <Link to="/contact">Contact us</Link>
              </Button>
              <Button asChild variant="outline" className="rounded-full h-10 px-6">
                <Link to="/terms">{t("terms_of_service")}</Link>
              </Button>
            </div>
          </motion.div>
        </div>
      </div>
    </Layout>
  );
};

export default PrivacyPolicy;
