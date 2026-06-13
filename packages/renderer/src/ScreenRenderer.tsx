/**
 * The runtime renderer entry point. It NEVER renders an unvalidated AST:
 * it validates structurally and semantically first, and if the AST is
 * invalid it renders a rejection panel listing the violations instead of
 * the screen. This is the enforcement boundary the acceptance criteria
 * require - invalid plans cannot reach the user as UI.
 */
import React from "react";
import { validateAst, type Screen } from "@design-playground/ui-ir";
import { RenderNode, DialogView } from "./RenderNode.js";

export function ScreenRenderer({ ast }: { ast: unknown }) {
  const result = React.useMemo(() => validateAst(ast), [ast]);

  if (!result.valid) {
    return <RejectionPanel ast={ast} result={result} />;
  }
  const screen = ast as Screen;
  return (
    <main className="dp-screen" data-flow={screen.flow} data-step={screen.step}>
      <h1>{screen.title}</h1>
      {screen.children.map((c, i) => (
        <RenderNode key={i} node={c} />
      ))}
      {(screen.dialogs ?? []).map((d, i) => (
        <DialogView key={i} node={d} />
      ))}
    </main>
  );
}

function RejectionPanel({ ast, result }: { ast: unknown; result: ReturnType<typeof validateAst> }) {
  const title = (ast as { title?: string })?.title ?? "(untitled)";
  return (
    <div className="dp-rejection" role="alert">
      <h2>⛔ AST rejected — not rendered</h2>
      <p>
        The screen <strong>{title}</strong> violates the design system and was refused by the renderer.
      </p>
      {!result.structural.valid && (
        <>
          <h3>Structural errors (schema)</h3>
          <ul>
            {result.structural.errors.map((e, i) => (
              <li key={i}>
                <code>{e.path}</code> — {e.message}
              </li>
            ))}
          </ul>
        </>
      )}
      {result.semantic.findings.length > 0 && (
        <>
          <h3>Design rule violations</h3>
          <ul>
            {result.semantic.findings.map((f, i) => (
              <li key={i}>
                <span className="dp-sev" data-sev={f.severity}>
                  {f.severity}
                </span>{" "}
                <code>{f.check}</code> @ <code>{f.path}</code> — {f.message}
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}
