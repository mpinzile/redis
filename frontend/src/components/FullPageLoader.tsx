// components/ui/FullPageLoader.tsx
import { motion } from "framer-motion";
import nuruLogo from "@/assets/nuru-logo.png";

export default function FullPageLoader() {
  return (
    <div className="fixed inset-0 bg-background flex flex-col items-center justify-center z-50">
      {/* Glowing Halo Behind Logo */}
      <motion.div
        className="absolute w-40 h-40 rounded-full bg-accent/20 blur-3xl"
        animate={{ scale: [0.9, 1.1, 0.9] }}
        transition={{ repeat: Infinity, duration: 2, ease: "easeInOut" }}
      />

      {/* Static Logo */}
      <img
        src={nuruLogo}
        alt="Nuru Logo"
        className="h-24 w-auto max-w-[60vw] object-contain relative z-10"
      />

      {/* Skeleton/Shimmer Loading Bars */}
      <div className="space-y-4 w-80 mt-12">
        {[1, 2, 3].map((i) => (
          <div key={i} className="relative h-4 bg-muted rounded overflow-hidden">
            <motion.div
              className="absolute top-0 left-0 h-full w-1/2 bg-gradient-to-r from-transparent via-accent/40 to-transparent"
              animate={{ x: ["-100%", "100%"] }}
              transition={{ repeat: Infinity, duration: 1.5 }}
            />
          </div>
        ))}
      </div>
    </div>
  );
}
