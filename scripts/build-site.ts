/**
 * Builds the static GitHub Pages site into `site/`.
 *
 * It renders the markdown docs to styled, token-driven HTML, assembles a
 * scenario gallery from the committed artifacts, copies the browsable
 * artifacts (scenarios, governance, schemas, tokens), and bundles the
 * live React renderer under /app. Mermaid diagrams render client-side
 * from a CDN, so the build itself needs no network.
 *
 *   pnpm site        # after `pnpm pipeline && pnpm screenshots`
 */
import { execSync } from "node:child_process";
import { mkdirSync, writeFileSync, readFileSync, cpSync, rmSync, existsSync } from "node:fs";
import { join } from "node:path";
import MarkdownIt from "markdown-it";
import { repoRoot } from "@design-playground/design-db";

const site = join(repoRoot, "site");
const REPO_URL = "https://github.com/datakurre/design-playground";

// ---- markdown --------------------------------------------------------
const md = new MarkdownIt({ html: true, linkify: true });
// Render ```mermaid fences as <div class="mermaid"> (raw, unescaped).
const defaultFence = md.renderer.rules.fence!.bind(md.renderer.rules);
md.renderer.rules.fence = (tokens, idx, options, env, self) => {
  const t = tokens[idx];
  if (t.info.trim() === "mermaid") return `<div class="mermaid">${t.content}</div>`;
  return defaultFence(tokens, idx, options, env, self);
};

// Add slug ids to headings so in-page anchors (#relation-to-standards) work.
const slugify = (s: string) =>
  s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
md.renderer.rules.heading_open = (tokens, idx, options, _env, self) => {
  const inline = tokens[idx + 1];
  const text = inline && inline.type === "inline" ? inline.content : "";
  if (text) tokens[idx].attrSet("id", slugify(text));
  return self.renderToken(tokens, idx, options);
};

// Rewrite intra-repo markdown links to their published equivalents.
const LINK_MAP: Record<string, string> = {
  "docs/architecture.md": "architecture.html",
  "architecture.md": "architecture.html",
  "docs/standards.md": "index.html",
  "standards.md": "index.html",
  "README.md": "readme.html",
  "governance/compliance-report.md": "governance.html#compliance",
  "governance/explainability-report.md": "governance.html#explainability",
};
function rewriteLinks(html: string): string {
  return html.replace(/href="([^"]+)"/g, (m, href) => {
    if (LINK_MAP[href]) return `href="${LINK_MAP[href]}"`;
    return m;
  });
}

function renderMd(relPath: string): string {
  return rewriteLinks(md.render(readFileSync(join(repoRoot, relPath), "utf8")));
}

// ---- layout ----------------------------------------------------------
const NAV = [
  ["index.html", "Overview"],
  ["architecture.html", "Architecture"],
  ["scenarios.html", "Scenarios"],
  ["governance.html", "Governance"],
  ["schemas.html", "Schemas & tokens"],
  ["app/index.html", "Live renderer"],
];

function page(opts: { title: string; active: string; body: string; mermaid?: boolean }): string {
  const nav = NAV.map(
    ([href, label]) =>
      `<a href="${href}"${href === opts.active ? ' aria-current="page"' : ""}>${label}</a>`,
  ).join("");
  const mermaidScript = opts.mermaid
    ? `<script type="module">import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";mermaid.initialize({startOnLoad:true,theme:"neutral"});</script>`
    : "";
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>${opts.title} · Design Playground</title>
<link rel="stylesheet" href="styles.css"/>
</head><body>
<header class="site-header">
  <a class="brand" href="index.html">Design&nbsp;Playground</a>
  <nav>${nav}<a class="ext" href="${REPO_URL}">GitHub ↗</a></nav>
</header>
<main class="content">${opts.body}</main>
<footer class="site-footer">
  Design tokens → SQLite rule store → MCP → agent planner → validated UI AST → React renderer → audit logs.
  Built on open standards (W3C DTCG · JSON Schema · MCP · WCAG/ARIA).
  <a href="${REPO_URL}">Source</a>
</footer>
${mermaidScript}
</body></html>`;
}

// ---- styles ----------------------------------------------------------
const tokensCss = readFileSync(join(repoRoot, "tokens/css/variables.css"), "utf8");
const STYLES = `${tokensCss}
:root{
  --spacing-md:var(--space-4);--spacing-lg:var(--space-6);--spacing-xl:var(--space-8);
}
*{box-sizing:border-box}
body{margin:0;font-family:var(--font-family-base,system-ui,sans-serif);color:var(--color-text-primary,#0f172a);
  background:var(--color-surface-background,#f8fafc);line-height:var(--font-line-height-normal,1.6)}
a{color:var(--color-brand-primary,#4f46e5)}
.site-header{display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap;
  padding:14px 24px;background:var(--color-surface-card,#fff);border-bottom:1px solid var(--color-border-default,#cbd5e1);
  position:sticky;top:0;z-index:10}
.brand{font-weight:800;font-size:18px;text-decoration:none;color:var(--color-text-primary,#0f172a)}
.site-header nav{display:flex;gap:6px;flex-wrap:wrap}
.site-header nav a{text-decoration:none;color:var(--color-text-secondary,#475569);padding:6px 10px;border-radius:8px;font-size:14px;font-weight:600}
.site-header nav a:hover{background:var(--color-surface-background,#f8fafc)}
.site-header nav a[aria-current=page]{background:var(--color-brand-primary,#4f46e5);color:#fff}
.site-header nav a.ext{color:var(--color-brand-primary,#4f46e5)}
.content{max-width:920px;margin:0 auto;padding:32px 24px 64px}
.content h1{font-size:2rem;line-height:1.2}
.content h2{margin-top:2em;border-bottom:1px solid var(--color-border-default,#cbd5e1);padding-bottom:.2em}
.content table{border-collapse:collapse;width:100%;margin:1em 0;font-size:14px}
.content th,.content td{border:1px solid var(--color-border-default,#cbd5e1);padding:8px 10px;text-align:left;vertical-align:top}
.content th{background:var(--color-surface-background,#f8fafc)}
.content code{background:var(--color-surface-background,#eef2f7);padding:1px 6px;border-radius:6px;font-family:var(--font-family-mono,monospace);font-size:.9em}
.content pre{background:#0f172a;color:#e2e8f0;padding:16px;border-radius:12px;overflow:auto}
.content pre code{background:none;color:inherit;padding:0}
.content blockquote{border-left:4px solid var(--color-brand-primary,#4f46e5);margin:1em 0;padding:.2em 1em;color:var(--color-text-secondary,#475569)}
.hero{background:var(--color-surface-card,#fff);border:1px solid var(--color-border-default,#cbd5e1);
  border-radius:16px;padding:32px;margin-bottom:24px;box-shadow:var(--shadow-md,0 4px 12px -2px #0f172a1f)}
.hero h1{margin:0 0 8px}
.hero .pipeline{font-family:var(--font-family-mono,monospace);font-size:13px;color:var(--color-text-secondary,#475569);
  background:var(--color-surface-background,#f8fafc);padding:12px 14px;border-radius:10px;margin-top:12px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px;margin:24px 0}
.card{display:block;text-decoration:none;color:inherit;background:var(--color-surface-card,#fff);
  border:1px solid var(--color-border-default,#cbd5e1);border-radius:12px;padding:18px;transition:border-color .15s}
.card:hover{border-color:var(--color-brand-primary,#4f46e5)}
.card h3{margin:0 0 6px}
.card p{margin:0;color:var(--color-text-secondary,#475569);font-size:14px}
.mermaid{background:var(--color-surface-card,#fff);border:1px solid var(--color-border-default,#cbd5e1);border-radius:12px;padding:16px;margin:1em 0;text-align:center}
.scenario{background:var(--color-surface-card,#fff);border:1px solid var(--color-border-default,#cbd5e1);
  border-radius:14px;padding:20px;margin:20px 0;box-shadow:var(--shadow-sm,0 1px 2px #0f172a14)}
.scenario h2{margin-top:0;border:none}
.scenario .req{color:var(--color-text-secondary,#475569);font-style:italic}
.scenario .shot{border:1px solid var(--color-border-default,#cbd5e1);border-radius:10px;width:100%;margin:12px 0;background:#fff}
.badges a{display:inline-block;font-size:13px;font-weight:600;text-decoration:none;background:var(--color-surface-background,#eef2f7);
  border:1px solid var(--color-border-default,#cbd5e1);border-radius:999px;padding:4px 12px;margin:4px 6px 0 0;color:var(--color-text-secondary,#475569)}
.tag{display:inline-block;font-size:12px;font-weight:700;padding:2px 8px;border-radius:999px;background:var(--color-brand-primary,#4f46e5);color:#fff}
.footnote{color:var(--color-text-secondary,#475569);font-size:14px}
.site-footer{max-width:920px;margin:0 auto;padding:24px;color:var(--color-text-secondary,#475569);font-size:13px;border-top:1px solid var(--color-border-default,#cbd5e1)}
`;

// ---- build -----------------------------------------------------------
function buildIndex() {
  const cards = [
    ["architecture.html", "Architecture", "Pipeline, the three enforcement layers, and the data model — with diagrams."],
    ["scenarios.html", "Scenarios", "Five end-to-end runs plus a rejected plan, with screenshots and traces."],
    ["governance.html", "Governance", "Audit log, decision traces, explainability and compliance reports."],
    ["schemas.html", "Schemas & tokens", "The W3C design tokens and JSON Schemas that define the system."],
    ["app/index.html", "Live renderer", "The React runtime renderer — pick a generated screen and see it rendered."],
    [REPO_URL, "Source", "All code, schemas, and generated artifacts on GitHub."],
  ]
    .map(
      ([href, h, p]) => `<a class="card" href="${href}"><h3>${h} →</h3><p>${p}</p></a>`,
    )
    .join("");
  const hero = `<section class="hero">
  <span class="tag">reference implementation</span>
  <h1>From design intent to agent-managed UI</h1>
  <p>A complete, runnable demonstration on a deliberately lightweight stack — <strong>JSON · SQLite · MCP · React</strong> — where design rules provably shape every generated interface and every decision is auditable.</p>
  <div class="pipeline">Design Tokens → Component Metadata → Flow Definitions → SQLite Rule Store → MCP Design Server → Agent Planner → UI AST → JSON Schema Validation → React Renderer → Audit Logs</div>
</section>
<div class="cards">${cards}</div>`;
  writeFileSync(join(site, "index.html"), page({ title: "Overview", active: "index.html", body: hero + renderMd("docs/standards.md") }));
}

function buildDocPage(file: string, out: string, title: string, active: string, mermaid = false) {
  writeFileSync(join(site, out), page({ title, active, body: renderMd(file), mermaid }));
}

function buildScenarios() {
  const index = JSON.parse(readFileSync(join(repoRoot, "scenarios/index.json"), "utf8")) as Array<{
    id: string;
    title: string;
    request?: string;
    flowId?: string;
    steps?: number;
    valid: boolean;
    errorCount?: number;
  }>;
  let body = `<h1>Demonstration scenarios</h1>
<p>Each scenario runs the full pipeline for one natural-language request. The screenshot is generated from the validated AST using resolved design tokens; the badges link to the committed request, retrieved rules, planning trace, validation output and live HTML render.</p>`;
  for (const s of index) {
    if (s.id === "_rejected") {
      body += `<div class="scenario"><h2>Rejected: malformed plan</h2>
<p>A deliberately rule-violating AST was submitted. The validator <strong>rejected</strong> it (${s.errorCount} errors) and the renderer refused to render it — invalid plans never reach the user.</p>
<div class="badges"><a href="scenarios/_rejected/validation.json">validation.json</a><a href="scenarios/_rejected/ast.json">ast.json</a></div></div>`;
      continue;
    }
    body += `<div class="scenario">
<h2>${s.title} <span class="tag">${s.valid ? "valid" : "invalid"}</span></h2>
<p class="req">“${s.request}” → flow <code>${s.flowId}</code>, ${s.steps} step(s)</p>
<img class="shot" src="scenarios/${s.id}/screenshot.svg" alt="${s.title} rendered screens"/>
<div class="badges">
  <a href="scenarios/${s.id}/render.html">live render.html ↗</a>
  <a href="scenarios/${s.id}/request.json">request</a>
  <a href="scenarios/${s.id}/retrieved-rules.json">retrieved rules</a>
  <a href="scenarios/${s.id}/planning-trace.json">planning trace</a>
  <a href="scenarios/${s.id}/ast.json">AST</a>
  <a href="scenarios/${s.id}/validation.json">validation</a>
</div></div>`;
  }
  writeFileSync(join(site, "scenarios.html"), page({ title: "Scenarios", active: "scenarios.html", body }));
}

function buildGovernance() {
  const body = `<h1>Governance</h1>
<p>Every generated screen is fully explainable. These reports are generated by <code>pnpm governance</code> from the SQLite audit log and the committed scenario outputs.</p>
<div class="badges">
  <a href="governance/audit-log.json">audit-log.json</a>
  <a href="governance/safety-constraints.json">safety-constraints.json</a>
  <a href="governance/decision-traces/">decision traces</a>
</div>
<h2 id="explainability">Explainability report</h2>
${renderMd("governance/explainability-report.md")}
<h2 id="compliance">Compliance report</h2>
${renderMd("governance/compliance-report.md")}`;
  writeFileSync(join(site, "governance.html"), page({ title: "Governance", active: "governance.html", body }));
}

function buildSchemas() {
  const schemas = [
    ["tokens/design-tokens.json", "Design tokens (W3C DTCG)"],
    ["tokens/design-tokens.schema.json", "Design tokens — JSON Schema"],
    ["tokens/css/variables.css", "Generated CSS custom properties"],
    ["ui-ir/ui-ast.schema.json", "UI AST — JSON Schema (2020-12)"],
    ["components/component.schema.json", "Component metadata — JSON Schema"],
    ["flows/flow.schema.json", "Flow definition — JSON Schema"],
    ["rules/design-rules.schema.json", "Design rules — JSON Schema"],
    ["rules/design-rules.json", "Design rules catalogue"],
  ];
  const list = schemas
    .map(([p, label]) => `<li><a href="${p}"><code>${p}</code></a> — ${label}</li>`)
    .join("");
  const examples = ["valid-login", "valid-delete-account", "invalid-structure", "invalid-semantics"]
    .map((e) => `<li><a href="ui-ir/examples/${e}.json"><code>${e}.json</code></a></li>`)
    .join("");
  const body = `<h1>Schemas &amp; tokens</h1>
<p>The system is defined by human- and machine-readable schemas. Everything below is open and standards-based — see <a href="index.html#relation-to-standards">relation to standards</a>.</p>
<h2>Sources of truth</h2><ul>${list}</ul>
<h2>Example ASTs</h2><ul>${examples}</ul>`;
  writeFileSync(join(site, "schemas.html"), page({ title: "Schemas & tokens", active: "schemas.html", body }));
}

function copyArtifacts() {
  for (const dir of ["scenarios", "governance", "tokens", "components", "flows", "rules", "ui-ir"]) {
    cpSync(join(repoRoot, dir), join(site, dir), { recursive: true });
  }
}

function buildApp() {
  console.log("Building React renderer for /app ...");
  execSync("pnpm --filter @design-playground/renderer build", {
    cwd: repoRoot,
    stdio: "inherit",
    env: { ...process.env, VITE_BASE: "./" },
  });
  cpSync(join(repoRoot, "packages/renderer/dist"), join(site, "app"), { recursive: true });
}

function main() {
  rmSync(site, { recursive: true, force: true });
  mkdirSync(site, { recursive: true });
  // Disable Jekyll so files/dirs starting with _ (e.g. scenarios/_rejected) are served.
  writeFileSync(join(site, ".nojekyll"), "");
  writeFileSync(join(site, "styles.css"), STYLES);

  buildIndex();
  buildDocPage("docs/architecture.md", "architecture.html", "Architecture", "architecture.html", true);
  if (existsSync(join(repoRoot, "README.md"))) buildDocPage("README.md", "readme.html", "Readme", "");
  buildScenarios();
  buildGovernance();
  buildSchemas();
  copyArtifacts();
  buildApp();

  console.log(`Site built into ${site}/`);
}

main();
