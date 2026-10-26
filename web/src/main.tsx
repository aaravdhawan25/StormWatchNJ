import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Page } from "./Page";

createRoot(document.getElementById("root")!).render(<StrictMode><Page /></StrictMode>);

// needed to show notifications
if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});
