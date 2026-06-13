/**
 * Deterministic AST -> static HTML transform. This is NOT the React
 * runtime renderer (packages/renderer); it is a dependency-free,
 * server-side projection used to (a) commit a viewable artifact for
 * every scenario and (b) act as a screenshot fallback when a headless
 * browser cannot be installed. It styles purely with the generated
 * token CSS variables, so the static output matches the live renderer.
 */
import type { Screen, Node, Dialog } from "./types.js";

function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function gapVar(gap?: string): string {
  return `var(--spacing-${gap ?? "md"})`;
}

function renderNode(node: Node): string {
  switch (node.type) {
    case "Text": {
      const tag =
        node.role === "heading" ? `h${node.level ?? 1}` : node.role === "subheading" ? "h3" : "p";
      const cls = node.role === "error" ? ' class="dp-error"' : node.role === "caption" ? ' class="dp-caption"' : "";
      return `<${tag}${cls}>${esc(node.value)}</${tag}>`;
    }
    case "Stack": {
      const dir = node.direction === "horizontal" ? "row" : "column";
      const role = node.role === "danger-zone" ? ' data-role="danger-zone"' : "";
      return `<div class="dp-stack"${role} style="flex-direction:${dir};gap:${gapVar(node.gap)}">${node.children
        .map(renderNode)
        .join("")}</div>`;
    }
    case "Grid":
      return `<div class="dp-grid" style="grid-template-columns:repeat(${node.columns},1fr);gap:${gapVar(
        node.gap,
      )}">${node.children.map(renderNode).join("")}</div>`;
    case "Card": {
      const role = node.role && node.role !== "plain" ? ` data-role="${node.role}"` : "";
      const title = node.title ? `<h3 class="dp-card-title">${esc(node.title)}</h3>` : "";
      return `<section class="dp-card"${role}>${title}${node.children.map(renderNode).join("")}</section>`;
    }
    case "Form":
      return `<form class="dp-form" data-id="${esc(node.id)}">${node.children.map(renderNode).join("")}</form>`;
    case "Field": {
      const id = `f-${esc(node.name)}`;
      const ac = node.autocomplete ? ` autocomplete="${esc(node.autocomplete)}"` : "";
      const req = node.required ? " required" : "";
      const help = node.help ? `<small class="dp-help">${esc(node.help)}</small>` : "";
      let control: string;
      if (node.inputType === "textarea") {
        control = `<textarea id="${id}" name="${esc(node.name)}"${req}></textarea>`;
      } else if (node.inputType === "select") {
        const opts = (node.options ?? [])
          .map((o) => `<option value="${esc(o.value)}">${esc(o.label)}</option>`)
          .join("");
        control = `<select id="${id}" name="${esc(node.name)}"${req}>${opts}</select>`;
      } else if (node.inputType === "checkbox") {
        return `<label class="dp-check"><input type="checkbox" id="${id}" name="${esc(
          node.name,
        )}"${req}/> ${esc(node.label)}</label>${help}`;
      } else {
        control = `<input type="${node.inputType}" id="${id}" name="${esc(node.name)}"${ac}${req}/>`;
      }
      return `<div class="dp-field"><label for="${id}">${esc(node.label)}${
        node.required ? ' <span class="dp-req">*</span>' : ""
      }</label>${control}${help}</div>`;
    }
    case "Button":
      return `<button type="button" class="dp-btn" data-variant="${node.variant}"${
        node.disabled ? " disabled" : ""
      } data-action="${esc(node.action.kind)}${node.action.target ? ":" + esc(node.action.target) : ""}">${esc(
        node.label,
      )}</button>`;
    case "Nav":
      return `<nav class="dp-nav">${node.items
        .map(
          (i) =>
            `<a class="dp-nav-item"${i.current ? ' aria-current="page"' : ""}>${esc(i.label)}</a>`,
        )
        .join("")}</nav>`;
    case "Dialog":
      return renderDialog(node);
  }
}

function renderDialog(d: Dialog): string {
  return `<div class="dp-dialog" data-id="${esc(d.id)}"${d.destructive ? ' data-destructive="true"' : ""} role="dialog" aria-modal="true" aria-label="${esc(
    d.title,
  )}">
  <h2 class="dp-dialog-title">${esc(d.title)}</h2>
  ${d.children.map(renderNode).join("")}
  <div class="dp-stack" style="flex-direction:row;gap:var(--spacing-sm);justify-content:flex-end">
    <button type="button" class="dp-btn" data-variant="secondary">${esc(d.cancelLabel)}</button>
    <button type="button" class="dp-btn" data-variant="${d.confirmVariant ?? "primary"}">${esc(
      d.confirmLabel,
    )}</button>
  </div>
</div>`;
}

const BASE_CSS = `
:root { color-scheme: light; }
* { box-sizing: border-box; }
body { margin:0; font-family: var(--typography-font-family-sans, system-ui, sans-serif);
  color: var(--color-text-primary, #1a1a1a); background: var(--color-surface-muted, #f5f6f8); }
.dp-screen { max-width: 720px; margin: 0 auto; padding: var(--spacing-xl, 32px); }
.dp-screen > h1 { font-size: var(--typography-font-size-2xl, 28px); }
.dp-stack { display:flex; }
.dp-grid { display:grid; }
.dp-card { background: var(--color-surface-default, #fff); border: 1px solid var(--color-border-default, #e2e4e8);
  border-radius: var(--radius-lg, 12px); padding: var(--spacing-lg, 24px);
  box-shadow: var(--shadow-sm, 0 1px 2px rgba(0,0,0,.06)); margin-bottom: var(--spacing-md, 16px); }
.dp-card[data-role="summary"] { background: var(--color-surface-muted, #f5f6f8); }
.dp-card[data-role="danger-zone"], .dp-stack[data-role="danger-zone"] {
  border: 1px solid var(--color-semantic-danger, #c0392b);
  border-radius: var(--radius-lg, 12px); padding: var(--spacing-lg, 24px); }
.dp-card-title { margin-top:0; }
.dp-form { display:flex; flex-direction:column; gap: var(--spacing-md, 16px); }
.dp-field { display:flex; flex-direction:column; gap: var(--spacing-xs, 4px); }
.dp-field label { font-weight:600; font-size: var(--typography-font-size-sm, 14px); }
.dp-field input, .dp-field select, .dp-field textarea {
  padding: var(--spacing-sm, 8px); border:1px solid var(--color-border-default, #e2e4e8);
  border-radius: var(--radius-md, 8px); font:inherit; }
.dp-help, .dp-caption { color: var(--color-text-secondary, #6b7280); font-size: var(--typography-font-size-sm, 13px); }
.dp-req { color: var(--color-semantic-danger, #c0392b); }
.dp-error { color: var(--color-semantic-danger, #c0392b); font-weight:600; }
.dp-btn { padding: var(--spacing-sm, 8px) var(--spacing-lg, 24px); border-radius: var(--radius-md, 8px);
  border:1px solid transparent; font:inherit; font-weight:600; cursor:pointer; min-height:44px; }
.dp-btn[data-variant="primary"] { background: var(--color-brand-primary, #2f6df6);
  color: var(--color-brand-primary-contrast, #fff); }
.dp-btn[data-variant="secondary"] { background: transparent;
  border-color: var(--color-border-default, #e2e4e8); color: var(--color-text-primary, #1a1a1a); }
.dp-btn[data-variant="danger"] { background: var(--color-semantic-danger, #c0392b);
  color: var(--color-semantic-danger-contrast, #fff); }
.dp-nav { display:flex; gap: var(--spacing-md,16px); padding-bottom: var(--spacing-md,16px); }
.dp-nav-item { color: var(--color-text-secondary,#6b7280); text-decoration:none; }
.dp-nav-item[aria-current="page"] { color: var(--color-brand-primary,#2f6df6); font-weight:700; }
.dp-dialog { background: var(--color-surface-default,#fff); border-radius: var(--radius-lg,12px);
  padding: var(--spacing-lg,24px); box-shadow: var(--shadow-lg, 0 12px 32px rgba(0,0,0,.18));
  margin-top: var(--spacing-lg,24px); border-top: 4px solid var(--color-border-default,#e2e4e8); }
.dp-dialog[data-destructive="true"] { border-top-color: var(--color-semantic-danger,#c0392b); }
.dp-dialog-title { margin-top:0; }
.dp-check { display:flex; gap: var(--spacing-sm,8px); align-items:center; }
`;

/** Render a full standalone HTML document for the screen. */
export function astToHtmlDocument(screen: Screen, tokensCss = ""): string {
  const dialogs = (screen.dialogs ?? []).map(renderDialog).join("\n");
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>${esc(screen.title)}</title>
<style>${tokensCss}${BASE_CSS}</style>
</head>
<body>
<main class="dp-screen" data-flow="${esc(screen.flow ?? "")}" data-step="${esc(screen.step ?? "")}">
<h1>${esc(screen.title)}</h1>
${screen.children.map(renderNode).join("\n")}
${dialogs}
</main>
</body>
</html>`;
}

/** Render just the screen body markup (no document chrome). */
export function astToHtmlFragment(screen: Screen): string {
  return `<main class="dp-screen"><h1>${esc(screen.title)}</h1>${screen.children
    .map(renderNode)
    .join("")}${(screen.dialogs ?? []).map(renderDialog).join("")}</main>`;
}
