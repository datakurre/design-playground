/**
 * Generates a visual artifact for every scenario screen.
 *
 * Always: a deterministic, dependency-free SVG screenshot rendered with
 * native SVG primitives (rects + text) using the *resolved* design-token
 * values. Because it uses no <foreignObject>, it rasterizes everywhere
 * (GitHub, resvg, image viewers) and is byte-stable across runs.
 *
 * When available: real PNG screenshots of the live render.html via
 * Playwright's chromium. If the browser is not installed (e.g. the
 * download is blocked) the script reports that and emits SVG only.
 *
 *   pnpm screenshots                 SVGs (+ PNGs if chromium present)
 *   npx playwright install chromium  enable PNG output
 */
import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { repoRoot } from "@design-playground/design-db";
import type { Screen, Node, Field, Button, Dialog } from "@design-playground/ui-ir";

const scenariosRoot = join(repoRoot, "scenarios");
const W = 760;
const PAD = 20;
const GAP = 12;
const CARD_MARGIN = 16;

// ---- token resolution ------------------------------------------------
function loadTokens(): Record<string, string> {
  const css = readFileSync(join(repoRoot, "tokens/css/variables.css"), "utf8");
  const map: Record<string, string> = {};
  for (const m of css.matchAll(/(--[a-z0-9-]+):\s*([^;]+);/g)) map[m[1]] = m[2].trim();
  return map;
}
const TOK = loadTokens();
function color(name: string, fallback: string): string {
  let v = TOK[name] ?? fallback;
  if (v.startsWith("var(")) v = color(v.slice(4, -1), fallback);
  // Trim 8-digit hex alpha to 6 for broad rasterizer support.
  return /^#[0-9a-f]{8}$/i.test(v) ? v.slice(0, 7) : v;
}
const C = {
  brand: color("--color-brand-primary", "#4f46e5"),
  brandText: color("--color-brand-primary-contrast", "#ffffff"),
  danger: color("--color-semantic-danger", "#dc2626"),
  dangerText: color("--color-semantic-danger-contrast", "#ffffff"),
  card: color("--color-surface-card", "#ffffff"),
  bg: color("--color-surface-background", "#f8fafc"),
  text: color("--color-text-primary", "#0f172a"),
  textMuted: color("--color-text-secondary", "#475569"),
  border: color("--color-border-default", "#cbd5e1"),
};
const FONT = "Inter, system-ui, -apple-system, Segoe UI, sans-serif";

// ---- helpers ---------------------------------------------------------
function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
function wrap(text: string, maxChars: number): string[] {
  const words = text.split(/\s+/);
  const lines: string[] = [];
  let line = "";
  for (const w of words) {
    if ((line + " " + w).trim().length > maxChars) {
      if (line) lines.push(line);
      line = w;
    } else line = (line + " " + w).trim();
  }
  if (line) lines.push(line);
  return lines.length ? lines : [""];
}
function txt(x: number, y: number, s: string, opts: { size?: number; weight?: number; fill?: string } = {}): string {
  return `<text x="${x}" y="${y}" font-family="${FONT}" font-size="${opts.size ?? 15}" font-weight="${
    opts.weight ?? 400
  }" fill="${opts.fill ?? C.text}">${esc(s)}</text>`;
}
function rect(x: number, y: number, w: number, h: number, opts: { fill?: string; stroke?: string; r?: number; sw?: number } = {}): string {
  return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${opts.r ?? 0}" fill="${
    opts.fill ?? "none"
  }"${opts.stroke ? ` stroke="${opts.stroke}" stroke-width="${opts.sw ?? 1}"` : ""}/>`;
}

// ---- measure ---------------------------------------------------------
function measure(node: Node, w: number): number {
  switch (node.type) {
    case "Text": {
      const size = node.role === "heading" ? 22 : node.role === "subheading" ? 17 : 15;
      return wrap(node.value, Math.floor(w / (size * 0.5))).length * (size + 6) + 6;
    }
    case "Button":
      return 40 + GAP;
    case "Field":
      return node.inputType === "checkbox" ? 26 + GAP : 22 + 38 + (node.help ? 18 : 0) + GAP;
    case "Stack":
    case "Form": {
      if (node.type === "Stack" && node.direction === "horizontal") {
        return Math.max(...node.children.map((c) => measure(c, w))) ;
      }
      return node.children.reduce((h, c) => h + measure(c, w), 0);
    }
    case "Grid": {
      const rows = Math.ceil(node.children.length / node.columns);
      const cw = (w - GAP * (node.columns - 1)) / node.columns;
      let h = 0;
      for (let r = 0; r < rows; r++) {
        const row = node.children.slice(r * node.columns, (r + 1) * node.columns);
        h += Math.max(...row.map((c) => measure(c, cw))) ;
      }
      return h;
    }
    case "Card": {
      const inner = w - PAD * 2;
      const body = node.children.reduce((h, c) => h + measure(c, inner), 0);
      return PAD * 2 + (node.title ? 30 : 0) + body + CARD_MARGIN;
    }
    case "Dialog": {
      const inner = w - PAD * 2;
      const body = node.children.reduce((h, c) => h + measure(c, inner), 0);
      return PAD * 2 + 34 + body + 52 + CARD_MARGIN;
    }
    case "Nav":
      return 30 + GAP;
    default:
      return 30;
  }
}

// ---- draw ------------------------------------------------------------
function draw(node: Node, x: number, y: number, w: number): string {
  switch (node.type) {
    case "Text": {
      const size = node.role === "heading" ? 22 : node.role === "subheading" ? 17 : 15;
      const fill = node.role === "error" ? C.danger : node.role === "caption" ? C.textMuted : C.text;
      const lines = wrap(node.value, Math.floor(w / (size * 0.5)));
      return lines
        .map((l, i) => txt(x, y + size + i * (size + 6), l, { size, fill, weight: node.role === "heading" ? 700 : 400 }))
        .join("");
    }
    case "Button":
      return drawButton(node, x, y);
    case "Field":
      return drawField(node, x, y, w);
    case "Form":
    case "Stack": {
      if (node.type === "Stack" && node.direction === "horizontal") {
        let cx = x;
        return node.children
          .map((c) => {
            const cw = Math.min(220, (w - GAP * (node.children.length - 1)) / node.children.length);
            const s = draw(c, cx, y, cw);
            cx += cw + GAP;
            return s;
          })
          .join("");
      }
      let cy = y;
      return node.children
        .map((c) => {
          const s = draw(c, x, cy, w);
          cy += measure(c, w);
          return s;
        })
        .join("");
    }
    case "Grid": {
      const cw = (w - GAP * (node.columns - 1)) / node.columns;
      let cy = y;
      let out = "";
      for (let r = 0; r * node.columns < node.children.length; r++) {
        const row = node.children.slice(r * node.columns, (r + 1) * node.columns);
        let rh = 0;
        row.forEach((c, i) => {
          out += draw(c, x + i * (cw + GAP), cy, cw);
          rh = Math.max(rh, measure(c, cw));
        });
        cy += rh;
      }
      return out;
    }
    case "Card":
      return drawContainer(node, x, y, w, false);
    case "Dialog":
      return drawDialog(node, x, y, w);
    case "Nav":
      return node.items
        .map((it, i) => txt(x + i * 110, y + 18, it.label, { fill: it.current ? C.brand : C.textMuted, weight: it.current ? 700 : 400 }))
        .join("");
    default:
      return "";
  }
}

function drawButton(node: Button, x: number, y: number): string {
  const fill = node.variant === "primary" ? C.brand : node.variant === "danger" ? C.danger : C.card;
  const fg = node.variant === "secondary" ? C.text : C.brandText;
  const w = Math.max(140, node.label.length * 9 + 40);
  return (
    rect(x, y, w, 40, { fill, r: 8, stroke: node.variant === "secondary" ? C.border : undefined }) +
    `<text x="${x + w / 2}" y="${y + 25}" text-anchor="middle" font-family="${FONT}" font-size="15" font-weight="600" fill="${fg}">${esc(
      node.label,
    )}</text>`
  );
}

function drawField(node: Field, x: number, y: number, w: number): string {
  if (node.inputType === "checkbox") {
    return rect(x, y + 2, 18, 18, { stroke: C.border, r: 4 }) + txt(x + 26, y + 16, node.label, { size: 14 });
  }
  let out = txt(x, y + 16, node.label + (node.required ? " *" : ""), { size: 13, weight: 600 });
  out += rect(x, y + 22, w, 36, { fill: C.card, stroke: C.border, r: 6 });
  out += txt(x + 10, y + 44, placeholder(node), { size: 13, fill: C.textMuted });
  if (node.help) out += txt(x, y + 74, node.help, { size: 12, fill: C.textMuted });
  return out;
}
function placeholder(node: Field): string {
  if (node.inputType === "select" && node.options?.length) return node.options[0].label;
  if (node.inputType === "password") return "••••••••";
  return node.inputType === "email" ? "name@example.com" : "";
}

function drawContainer(node: { title?: string; role?: string; children: Node[] }, x: number, y: number, w: number, isDialog: boolean): string {
  const h = measureContainer(node, w);
  const isDanger = node.role === "danger-zone";
  const isSummary = node.role === "summary";
  const fill = isDanger ? "#fef2f2" : isSummary ? C.bg : C.card;
  let out = rect(x, y, w, h, { fill, r: 12, stroke: isDanger ? C.danger : C.border });
  let cy = y + PAD;
  const inner = w - PAD * 2;
  if (node.title) {
    out += txt(x + PAD, cy + 16, node.title, { size: 17, weight: 700, fill: isDanger ? C.danger : C.text });
    cy += 30;
  }
  for (const c of node.children) {
    out += draw(c, x + PAD, cy, inner);
    cy += measure(c, inner);
  }
  return out;
}
function measureContainer(node: { title?: string; children: Node[] }, w: number): number {
  const inner = w - PAD * 2;
  return PAD * 2 + (node.title ? 30 : 0) + node.children.reduce((h, c) => h + measure(c, inner), 0);
}

function drawDialog(node: Dialog, x: number, y: number, w: number): string {
  const inner = w - PAD * 2;
  const bodyH = node.children.reduce((h, c) => h + measure(c, inner), 0);
  const h = PAD * 2 + 34 + bodyH + 52;
  let out = rect(x, y, w, h, { fill: C.card, r: 12, stroke: C.border });
  out += rect(x, y, w, 4, { fill: node.destructive ? C.danger : C.brand, r: 0 });
  out += txt(x + PAD, y + PAD + 18, node.title, { size: 18, weight: 700 });
  let cy = y + PAD + 34;
  for (const c of node.children) {
    out += draw(c, x + PAD, cy, inner);
    cy += measure(c, inner);
  }
  // action row, right-aligned
  const confirmFill = node.confirmVariant === "danger" ? C.danger : C.brand;
  const cw = Math.max(120, node.confirmLabel.length * 8 + 32);
  const sw = Math.max(110, node.cancelLabel.length * 8 + 32);
  const by = y + h - 48;
  out += rect(x + w - PAD - cw, by, cw, 38, { fill: confirmFill, r: 8 });
  out += `<text x="${x + w - PAD - cw / 2}" y="${by + 24}" text-anchor="middle" font-family="${FONT}" font-size="14" font-weight="600" fill="${C.brandText}">${esc(node.confirmLabel)}</text>`;
  out += rect(x + w - PAD - cw - GAP - sw, by, sw, 38, { fill: C.card, stroke: C.border, r: 8 });
  out += `<text x="${x + w - PAD - cw - GAP - sw / 2}" y="${by + 24}" text-anchor="middle" font-family="${FONT}" font-size="14" font-weight="600" fill="${C.text}">${esc(node.cancelLabel)}</text>`;
  return out;
}

// ---- screen ----------------------------------------------------------
function renderScreen(screen: Screen, x: number, y: number, w: number): { svg: string; height: number } {
  let cy = y;
  let out = txt(x, cy + 30, screen.title, { size: 26, weight: 700 });
  cy += 48;
  const inner = w;
  for (const c of screen.children) {
    out += draw(c, x, cy, inner);
    cy += measure(c, inner);
  }
  for (const d of screen.dialogs ?? []) {
    out += draw(d, x, cy, inner);
    cy += measure(d, inner);
  }
  return { svg: out, height: cy - y };
}

function buildSvg(screens: Screen[]): string {
  const contentW = W - 64;
  let y = 24;
  let body = "";
  for (const s of screens) {
    body += txt(32, y + 12, `STEP: ${(s.step ?? "").toUpperCase()}`, { size: 11, fill: C.textMuted, weight: 700 });
    y += 26;
    const r = renderScreen(s, 32, y, contentW);
    body += r.svg;
    y += r.height + 24;
    body += `<line x1="0" y1="${y - 12}" x2="${W}" y2="${y - 12}" stroke="${C.border}" stroke-dasharray="4 4"/>`;
  }
  const H = Math.ceil(y);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
<rect width="${W}" height="${H}" fill="${C.bg}"/>
${body}
</svg>`;
}

// ---- main ------------------------------------------------------------
function scenarioDirs(): string[] {
  return readdirSync(scenariosRoot, { withFileTypes: true })
    .filter((d) => d.isDirectory() && !d.name.startsWith("_"))
    .map((d) => d.name)
    .filter((name) => existsSync(join(scenariosRoot, name, "ast.json")))
    .sort();
}

async function tryPlaywright() {
  try {
    const { chromium } = await import("playwright");
    const browser = await chromium.launch();
    const page = await browser.newPage({ viewport: { width: W, height: 1024 } });
    return {
      shot: async (htmlPath: string, out: string) => {
        await page.goto(`file://${htmlPath}`);
        await page.screenshot({ path: out, fullPage: true });
      },
      close: () => browser.close(),
    };
  } catch (err) {
    console.error(`Playwright/chromium unavailable (${(err as Error).message.split("\n")[0]}); SVG screenshots only.`);
    return null;
  }
}

async function main() {
  const dirs = scenarioDirs();
  const pw = await tryPlaywright();
  let png = 0;
  for (const name of dirs) {
    const dir = join(scenariosRoot, name);
    const screens = JSON.parse(readFileSync(join(dir, "ast.json"), "utf8")) as Screen[];
    writeFileSync(join(dir, "screenshot.svg"), buildSvg(screens));
    if (pw && existsSync(join(dir, "render.html"))) {
      await pw.shot(join(dir, "render.html"), join(dir, "screenshot.png"));
      png++;
    }
  }
  if (pw) await pw.close();
  console.log(`Wrote ${dirs.length} SVG screenshots${pw ? ` and ${png} PNGs` : " (no PNG: chromium not installed)"}.`);
}

main();
