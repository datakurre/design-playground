/**
 * React bindings for the UI AST. Every node type maps to a component
 * styled exclusively through the generated design-token CSS variables,
 * so a rendered screen is consistent with the design system by
 * construction. There is no path from the AST to raw HTML/markup: a
 * node type outside the closed vocabulary simply does not render.
 */
import React from "react";
import type { Node, Dialog, Field } from "@design-playground/ui-ir";

const gap = (g?: string) => `var(--spacing-${g ?? "md"})`;

function FieldControl({ node }: { node: Field }) {
  const id = `f-${node.name}`;
  const common = { id, name: node.name, required: node.required };
  if (node.inputType === "checkbox") {
    return (
      <label className="dp-check">
        <input type="checkbox" {...common} /> {node.label}
      </label>
    );
  }
  if (node.inputType === "textarea") return <textarea {...common} />;
  if (node.inputType === "select") {
    return (
      <select {...common}>
        {(node.options ?? []).map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    );
  }
  return <input type={node.inputType} autoComplete={node.autocomplete} {...common} />;
}

export function RenderNode({ node }: { node: Node }): React.ReactElement | null {
  switch (node.type) {
    case "Text": {
      if (node.role === "heading") {
        const lvl = Math.min(Math.max(node.level ?? 1, 1), 6);
        return React.createElement(`h${lvl}`, null, node.value);
      }
      if (node.role === "subheading") return <h3>{node.value}</h3>;
      const cls = node.role === "error" ? "dp-error" : node.role === "caption" ? "dp-caption" : undefined;
      return <p className={cls}>{node.value}</p>;
    }
    case "Stack":
      return (
        <div
          className="dp-stack"
          data-role={node.role}
          style={{ flexDirection: node.direction === "horizontal" ? "row" : "column", gap: gap(node.gap) }}
        >
          {node.children.map((c, i) => (
            <RenderNode key={i} node={c} />
          ))}
        </div>
      );
    case "Grid":
      return (
        <div className="dp-grid" style={{ gridTemplateColumns: `repeat(${node.columns},1fr)`, gap: gap(node.gap) }}>
          {node.children.map((c, i) => (
            <RenderNode key={i} node={c} />
          ))}
        </div>
      );
    case "Card":
      return (
        <section className="dp-card" data-role={node.role}>
          {node.title && <h3 className="dp-card-title">{node.title}</h3>}
          {node.children.map((c, i) => (
            <RenderNode key={i} node={c} />
          ))}
        </section>
      );
    case "Form":
      return (
        <form className="dp-form" data-id={node.id} onSubmit={(e) => e.preventDefault()}>
          {node.children.map((c, i) => (
            <RenderNode key={i} node={c} />
          ))}
        </form>
      );
    case "Field":
      return (
        <div className="dp-field">
          {node.inputType !== "checkbox" && (
            <label htmlFor={`f-${node.name}`}>
              {node.label}
              {node.required && <span className="dp-req"> *</span>}
            </label>
          )}
          <FieldControl node={node} />
          {node.help && <small className="dp-help">{node.help}</small>}
        </div>
      );
    case "Button":
      return (
        <button
          type="button"
          className="dp-btn"
          data-variant={node.variant}
          disabled={node.disabled}
          data-action={`${node.action.kind}${node.action.target ? ":" + node.action.target : ""}`}
        >
          {node.label}
        </button>
      );
    case "Nav":
      return (
        <nav className="dp-nav">
          {node.items.map((it, i) => (
            <a key={i} className="dp-nav-item" aria-current={it.current ? "page" : undefined}>
              {it.label}
            </a>
          ))}
        </nav>
      );
    case "Dialog":
      return <DialogView node={node} />;
    default:
      return null;
  }
}

export function DialogView({ node }: { node: Dialog }) {
  return (
    <div
      className="dp-dialog"
      data-id={node.id}
      data-destructive={node.destructive ? "true" : undefined}
      role="dialog"
      aria-modal="true"
      aria-label={node.title}
    >
      <h2 className="dp-dialog-title">{node.title}</h2>
      {node.children.map((c, i) => (
        <RenderNode key={i} node={c} />
      ))}
      <div className="dp-stack" style={{ flexDirection: "row", gap: "var(--spacing-sm)", justifyContent: "flex-end" }}>
        <button type="button" className="dp-btn" data-variant="secondary">
          {node.cancelLabel}
        </button>
        <button type="button" className="dp-btn" data-variant={node.confirmVariant ?? "primary"}>
          {node.confirmLabel}
        </button>
      </div>
    </div>
  );
}
