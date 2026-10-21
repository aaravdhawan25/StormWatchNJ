import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Page } from "./Page";

createRoot(document.getElementById("root")!).render(<StrictMode><Page /></StrictMode>);

// Needed to show notifications (and the only way to on an iPhone home-screen app).
if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});
