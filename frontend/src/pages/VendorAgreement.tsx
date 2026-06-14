import { motion } from "framer-motion";
import { Link } from "react-router-dom";
import Layout from "@/components/layout/Layout";
import { useMeta } from "@/hooks/useMeta";
import { Button } from "@/components/ui/button";
import { useLanguage } from '@/lib/i18n/LanguageContext';

const VendorAgreement = () => {
  const { t } = useLanguage();
  useMeta({
    title: "Vendor Agreement | Nuru",
    description: "Read the Nuru Workspace Vendor Agreement covering service obligations, payment terms, cancellation rules, and platform conduct for vendors."
  });

  const sections = [
    {
      title: "Independent Status",
      content: [
        "You are an independent contractor, not an employee, agent, or representative of Nuru.",
        "Nuru does not control how you deliver your services.",
        "You are solely responsible for your own taxes, licences, permits, and legal compliance.",
        "Nothing in this Agreement creates an employment, partnership, or joint venture relationship between you and Nuru."
      ]
    },
    {
      title: "Service Listings and Portfolio",
      content: [
        "Provide accurate, complete, and up-to-date service descriptions.",
        "Set fair and transparent pricing.",
        "Clearly state your availability and service areas.",
        "Accurately represent your qualifications and experience.",
        "You may upload images, videos, and audio to showcase your work.",
        "You represent and warrant that you own or have the legal right to use all portfolio content you upload.",
        "You must have obtained consent from any individuals appearing in your portfolio media.",
        "Misleading or fraudulent portfolio content may result in account suspension.",
        "Introductory video or audio clips (maximum 1 minute) must be professional and relevant."
      ]
    },
    {
      title: "Service Obligations",
      content: [
        "Deliver services as advertised in your listings.",
        "Honour all confirmed bookings.",
        "Respect agreed timelines, locations, and specifications.",
        "Communicate promptly and professionally with Organisers.",
        "Arrive on time for scheduled engagements.",
        "Failure to deliver may result in refunds, financial penalties, reputation impact, or account suspension."
      ]
    },
    {
      title: "Cancellation Rules",
      content: [
        "You do not set your own cancellation terms. All cancellations are governed by the Nuru Cancellation and Refund Framework.",
        "Your services operate under one of three standardised cancellation tiers (Flexible, Moderate, or Strict) based on your service category.",
        "If you cancel a confirmed booking, the Organiser receives a full 100% refund including any booking deposit.",
        "Cancellation results in a rating penalty and possible account strike.",
        "Repeated cancellations may result in temporary suspension or permanent removal.",
        "You may agree to reschedule a booking instead of cancellation · no penalty applies and funds remain in escrow."
      ]
    },
    {
      title: "Payment Terms",
      content: [
        "Payment is released only after the Organiser confirms satisfactory delivery, or the automatic release period (48 hours after event) expires without dispute.",
        "Nuru may deduct a platform commission from your earnings before payout.",
        "Commission rates are clearly communicated and may vary by service category.",
        "Payouts are made to your registered payment method with processing times varying by provider."
      ]
    },
    {
      title: "Photo Libraries",
      content: [
        "If you provide photography or videography services, you may create Photo Libraries for events you have been booked for.",
        "You are responsible for setting appropriate privacy levels for each Photo Library.",
        "You must have the right to share all images and videos uploaded.",
        "You retain ownership of your creative work unless otherwise agreed with the Organiser."
      ]
    },
    {
      title: "Verification and KYC",
      content: [
        "Nuru may require identity verification and Know Your Customer (KYC) documentation.",
        "You agree to provide accurate verification documents when requested.",
        "Verification status may affect your visibility and booking eligibility.",
        "Providing false verification documents results in immediate account termination."
      ]
    },
    {
      title: "Reviews and Ratings",
      content: [
        "Organisers may leave reviews and ratings after service delivery.",
        "You may respond to reviews professionally.",
        "You may not attempt to manipulate, falsify, or coerce reviews.",
        "Nuru reserves the right to remove reviews that violate platform policies."
      ]
    },
    {
      title: "Prohibited Conduct",
      content: [
        "Soliciting or facilitating off-platform payments for services booked through Nuru.",
        "Providing false or misleading service details.",
        "Cancelling bookings without valid reason or adequate notice.",
        "Uploading content that infringes on third-party intellectual property rights.",
        "Harassing, threatening, or discriminating against Organisers or attendees.",
        "Creating multiple accounts to circumvent restrictions or penalties.",
        "Using the platform to promote services unrelated to events."
      ]
    },
    {
      title: "Security Deposit",
      content: [
        "If applicable, Nuru may require a security deposit from Vendors.",
        "Security deposits may cover penalties for no-shows, fraudulent activity, or significant service quality failures.",
        "Remaining balances are returned upon account closure, subject to any pending disputes."
      ]
    },
    {
      title: "Suspension and Termination",
      content: [
        "Nuru may suspend or terminate your Vendor account for repeated failure to deliver, fraudulent activity, persistent negative reviews, policy violations, or off-platform payment solicitation.",
        "Upon termination, pending payouts may be withheld until all disputes are resolved."
      ]
    },
    {
      title: "Intellectual Property",
      content: [
        "You retain ownership of original content you create and upload.",
        "By uploading content, you grant Nuru a non-exclusive licence to display and distribute it within the platform.",
        "Nuru's platform design, branding, and proprietary content remain the property of Nuru."
      ]
    },
    {
      title: "Liability",
      content: [
        "You are solely liable for the quality and safety of services you provide.",
        "You agree to indemnify Nuru against any claims arising from your services.",
        "Nuru is not liable for any damages resulting from your service delivery or failure to deliver."
      ]
    }
  ];

  return (
    <Layout>
      <div className="min-h-screen pt-32 pb-24 px-6">
        <div className="max-w-3xl mx-auto">
          <motion.div initial={{ opacity: 0, y: 30 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.6 }} className="mb-16">
            <h1 className="text-4xl sm:text-5xl md:text-6xl font-bold text-foreground tracking-tight mb-6">Vendor Agreement</h1>
            <p className="text-muted-foreground">Effective: February 2025</p>
          </motion.div>

          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5, delay: 0.1 }} className="mb-16">
            <p className="text-lg text-muted-foreground leading-relaxed">
              This Vendor Agreement supplements the Nuru Workspace Terms and Conditions. By registering as a Vendor on the platform, you agree to the following terms in addition to the general Terms and Conditions.
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
            <h2 className="text-xl font-semibold text-foreground mb-3">Related Documents</h2>
            <p className="text-muted-foreground mb-4">Review related agreements and policies.</p>
            <div className="flex flex-wrap gap-3 mb-6">
              <Button asChild variant="outline" className="rounded-full h-10 px-6"><Link to="/terms">{t("terms_of_service")}</Link></Button>
              <Button asChild variant="outline" className="rounded-full h-10 px-6"><Link to="/organiser-agreement">Organiser Agreement</Link></Button>
              <Button asChild variant="outline" className="rounded-full h-10 px-6"><Link to="/cancellation-policy">{t("cancellation_policy")}</Link></Button>
            </div>
            <p className="text-sm text-muted-foreground">Questions? Contact our legal team at legal@nuru.tz</p>
          </motion.div>
        </div>
      </div>
    </Layout>
  );
};

export default VendorAgreement;
