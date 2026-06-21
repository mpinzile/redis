import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import { installFetchTracer } from "./lib/perf";

// Perf instrumentation (Stage 1) — wraps window.fetch so every API call
// emits a structured perf line tied to the backend X-Request-ID.
installFetchTracer();

// Apply dark mode from localStorage on initial load
const savedTheme = localStorage.getItem('nuru-ui-theme');
if (savedTheme === 'dark') {
  document.documentElement.classList.add('dark');
} else {
  document.documentElement.classList.remove('dark');
}

createRoot(document.getElementById("root")!).render(<App />);
