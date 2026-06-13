import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App.js";
// Generated design tokens as CSS custom properties - the single source
// of styling truth shared with the static renderer.
import "../../../tokens/css/variables.css";
import "./app.css";

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
