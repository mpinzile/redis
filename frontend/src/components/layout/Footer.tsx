import { Link } from "react-router-dom";
import nuruLogo from "@/assets/nuru-logo.png";

const featureLinks = [
  { label: "All features", to: "/features" },
  { label: "Event Planning", to: "/features/event-planning" },
  { label: "Vendors & Services", to: "/features/service-providers" },
  { label: "Invitations & RSVP", to: "/features/invitations" },
  { label: "NuruCards (NFC)", to: "/features/nfc-cards" },
  { label: "Built-in Payments", to: "/features/payments" },
  { label: "Built-in Meetings", to: "/features/meetings" },
  { label: "Event Groups", to: "/features/event-groups" },
  { label: "Ticketing", to: "/features/ticketing" },
  { label: "Trust & Protection", to: "/features/trust" },
];

const Footer = () => {
  const currentYear = new Date().getFullYear();

  return (
    <footer className="bg-foreground text-background">
      <div className="max-w-7xl mx-auto px-6 lg:px-8 py-16 md:py-24">
        <div className="grid grid-cols-2 md:grid-cols-5 gap-12 md:gap-8 mb-16">
          {/* Brand */}
          <div className="col-span-2">
            <img
              src={nuruLogo}
              alt="Nuru"
              className="h-8 w-auto brightness-0 invert mb-6"
            />
            <p className="text-background/60 text-sm leading-relaxed max-w-xs">
              Plan smarter. Celebrate Better. The operating workspace for every
              event — weddings, conferences, memorials and more.
            </p>
          </div>

          {/* Product / Features */}
          <div className="col-span-2 md:col-span-2">
            <h3 className="font-medium text-sm tracking-[0.18em] uppercase text-background/80 mb-6">
              Product
            </h3>
            <ul className="grid grid-cols-2 gap-y-3 gap-x-6">
              {featureLinks.map((f) => (
                <li key={f.to}>
                  <Link
                    to={f.to}
                    className="text-sm text-background/60 hover:text-background transition-colors"
                  >
                    {f.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>

          {/* Company + Legal */}
          <div>
            <h3 className="font-medium text-sm tracking-[0.18em] uppercase text-background/80 mb-6">
              Company
            </h3>
            <ul className="space-y-3 mb-8">
              <li>
                <Link
                  to="/contact"
                  className="text-sm text-background/60 hover:text-background transition-colors"
                >
                  Contact
                </Link>
              </li>
              <li>
                <Link
                  to="/faqs"
                  className="text-sm text-background/60 hover:text-background transition-colors"
                >
                  FAQs
                </Link>
              </li>
            </ul>
            <h3 className="font-medium text-sm tracking-[0.18em] uppercase text-background/80 mb-6">
              Legal
            </h3>
            <ul className="space-y-3">
              <li>
                <Link
                  to="/privacy-policy"
                  className="text-sm text-background/60 hover:text-background transition-colors"
                >
                  Privacy
                </Link>
              </li>
              <li>
                <Link
                  to="/terms"
                  className="text-sm text-background/60 hover:text-background transition-colors"
                >
                  Terms
                </Link>
              </li>
              <li>
                <Link
                  to="/cookie-policy"
                  className="text-sm text-background/60 hover:text-background transition-colors"
                >
                  Cookies
                </Link>
              </li>
              <li>
                <Link
                  to="/vendor-agreement"
                  className="text-sm text-background/60 hover:text-background transition-colors"
                >
                  Vendor Agreement
                </Link>
              </li>
              <li>
                <Link
                  to="/organiser-agreement"
                  className="text-sm text-background/60 hover:text-background transition-colors"
                >
                  Organiser Agreement
                </Link>
              </li>
            </ul>
          </div>
        </div>

        {/* Bottom */}
        <div className="pt-8 border-t border-background/10 flex flex-col md:flex-row justify-between items-center gap-6">
          <p className="text-sm text-background/40">
            © {currentYear} Nuru Workspace - SEWMR Technologies
          </p>
          <div className="flex items-center gap-8 flex-wrap justify-center">
            <a
              href="mailto:hello@nuru.tz"
              className="text-sm text-background/60 hover:text-background transition-colors"
            >
              hello@nuru.tz
            </a>
            <a
              href="tel:+255653750805"
              className="text-sm text-background/60 hover:text-background transition-colors"
            >
              +255 653 750 805
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
};

export default Footer;
