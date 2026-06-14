import React from "react";
import { ScreenRenderer } from "../ScreenRenderer.js";
import demoScreen from "../../../../ui-ir/examples/valid-delete-account.json";
import {
  ALL_TOKENS,
  CATEGORY_ORDER,
  TOKEN_GROUPS,
  tokenByPath,
  cssVarName,
  cssValue,
  aliasesFor,
  bindingsFor,
  dtcgExport,
  type FlatToken,
} from "./token-index.js";

/**
 * Interactive Design Token playground. Pick a token, edit its value, and
 * watch the change flow through each pipeline phase at once:
 *   phase 1 (DTCG source) -> build (CSS variable) -> alias layer ->
 *   phase 2 (component bindings) -> phase 9 (live render).
 *
 * The trick: every component is styled via `var(--token, ...)`, so setting
 * the generated custom property on a wrapper element cascades the edit into
 * the real renderer output with no component changes. We always override
 * the GENERATED var (cssVarName), which aliases resolve through.
 */
const PHASES: Array<{ n: string; label: string; token: boolean }> = [
  { n: "1", label: "Design tokens (DTCG)", token: true },
  { n: "·", label: "Build → CSS variables", token: true },
  { n: "2", label: "Component metadata", token: true },
  { n: "3", label: "Flow definitions", token: false },
  { n: "4", label: "SQLite rule store", token: false },
  { n: "5", label: "MCP server", token: false },
  { n: "6", label: "Agent planner", token: false },
  { n: "7", label: "UI AST", token: false },
  { n: "8", label: "Schema validation", token: false },
  { n: "9", label: "React renderer", token: true },
  { n: "10", label: "Audit logs", token: false },
];

function customProp(name: string, value: string): React.CSSProperties {
  // React.CSSProperties doesn't type arbitrary `--*` keys; cast is required.
  return { [name]: value } as React.CSSProperties;
}

function isColor(token: FlatToken) {
  return token.type === "color";
}

function Panel({ phase, title, children }: { phase?: string; title: string; children: React.ReactNode }) {
  return (
    <section className="tpg-panel">
      <h3>
        {phase && <span className="tpg-phase">phase {phase}</span>}
        {title}
      </h3>
      {children}
    </section>
  );
}

export function TokenPlayground({ initialPath = "color.brand.primary" }: { initialPath?: string }) {
  const [path, setPath] = React.useState(initialPath);
  const [override, setOverride] = React.useState<string | null>(null);
  const [copied, setCopied] = React.useState(false);

  const token = tokenByPath(path) ?? ALL_TOKENS[0];
  const varName = cssVarName(token.path);
  const originalValue = cssValue(token);
  const editedValue = override ?? originalValue;
  const dirty = override !== null && override !== originalValue;
  const aliases = aliasesFor(varName);
  const bindings = bindingsFor(token.path);

  function selectPath(p: string) {
    setPath(p);
    setOverride(null);
    setCopied(false);
  }

  async function copyExport() {
    try {
      await navigator.clipboard?.writeText(dtcgExport(token, editedValue));
      setCopied(true);
    } catch {
      /* clipboard unavailable (e.g. headless) */
    }
  }

  const overrideStyle = dirty ? customProp(varName, editedValue) : undefined;

  return (
    <div className="tpg" data-token={token.path}>
      <header className="tpg-head">
        <div>
          <h1>Design Token Playground</h1>
          <p className="tpg-sub">
            Edit a token and watch it propagate through the pipeline. Components are styled only via
            CSS variables, so one change re-themes every phase below.
          </p>
        </div>
      </header>

      {/* Pipeline rail: where tokens participate across all phases. */}
      <ol className="tpg-rail" aria-label="Pipeline phases">
        {PHASES.map((p) => (
          <li key={p.n + p.label} data-token={p.token} title={p.label}>
            <span className="tpg-rail-n">{p.n}</span>
            <span className="tpg-rail-l">{p.label}</span>
          </li>
        ))}
      </ol>

      <div className="tpg-controls">
        <label className="tpg-field">
          <span>Token</span>
          <select value={token.path} onChange={(e) => selectPath(e.target.value)} className="tpg-select">
            {CATEGORY_ORDER.filter((c) => TOKEN_GROUPS[c]).map((cat) => (
              <optgroup key={cat} label={cat}>
                {TOKEN_GROUPS[cat].map((t) => (
                  <option key={t.path} value={t.path}>
                    {t.path}
                  </option>
                ))}
              </optgroup>
            ))}
          </select>
        </label>

        <label className="tpg-field">
          <span>Value ({token.type})</span>
          <span className="tpg-editor">
            {isColor(token) && (
              <input
                type="color"
                aria-label="Color picker"
                value={/^#[0-9a-f]{6}$/i.test(editedValue) ? editedValue : "#000000"}
                onChange={(e) => setOverride(e.target.value)}
              />
            )}
            <input
              type="text"
              className="tpg-text"
              aria-label="Token value"
              value={editedValue}
              onChange={(e) => setOverride(e.target.value)}
            />
          </span>
        </label>

        <button type="button" className="tpg-reset" onClick={() => setOverride(null)} disabled={!dirty}>
          Reset
        </button>
      </div>

      <div className="tpg-grid">
        <Panel phase="1" title="DTCG source">
          <pre className="tpg-code">
{JSON.stringify(
  {
    [token.path]: {
      $type: token.type,
      $value: token.value,
      ...(token.description ? { $description: token.description } : {}),
    },
  },
  null,
  2,
)}
          </pre>
        </Panel>

        <Panel title="Build → CSS variable">
          <p className="tpg-muted">
            <code>flattenTokens</code> + <code>cssVarName</code>/<code>cssValue</code> emit:
          </p>
          <pre className="tpg-code">
            <span className={dirty ? "tpg-was" : undefined}>
              {varName}: {originalValue};
            </span>
            {dirty && (
              <>
                {"\n"}
                <span className="tpg-now">
                  {varName}: {editedValue};
                </span>
              </>
            )}
          </pre>
        </Panel>

        <Panel title="Alias layer">
          {aliases.length ? (
            <ul className="tpg-list">
              {aliases.map((a) => (
                <li key={a}>
                  <code>{a}</code> → <code>var({varName})</code>
                </li>
              ))}
            </ul>
          ) : (
            <p className="tpg-muted">Not aliased — consumed directly as <code>var({varName})</code>.</p>
          )}
        </Panel>

        <Panel phase="2" title="Component bindings">
          {bindings.length ? (
            <table className="tpg-bind">
              <thead>
                <tr>
                  <th>component</th>
                  <th>variant</th>
                </tr>
              </thead>
              <tbody>
                {bindings.map((b, i) => (
                  <tr key={i}>
                    <td>{b.component}</td>
                    <td>{b.variant}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="tpg-muted">
              No component variant declares this token directly (used via layout or aliases).
            </p>
          )}
        </Panel>

        <Panel title="Round-trip → DTCG">
          <p className="tpg-muted">Paste back into <code>tokens/design-tokens.json</code>:</p>
          <pre className="tpg-code">{dtcgExport(token, editedValue)}</pre>
          <button type="button" className="tpg-copy" onClick={copyExport}>
            {copied ? "Copied ✓" : "Copy"}
          </button>
        </Panel>

        {isColor(token) && (
          <Panel title="Swatch">
            <div className="tpg-swatches">
              <div>
                <span className="tpg-chip" style={customProp("--c", originalValue)} />
                <small>original</small>
              </div>
              <div>
                <span className="tpg-chip" style={customProp("--c", editedValue)} />
                <small>edited</small>
              </div>
            </div>
          </Panel>
        )}
      </div>

      <Panel phase="9" title="Live render — original vs edited">
        <div className="tpg-preview">
          <div className="tpg-col">
            <span className="tpg-tag">original</span>
            <div className="dp-stage tpg-frame">
              <ScreenRenderer ast={demoScreen} />
            </div>
          </div>
          <div className="tpg-col" data-tpg="edited">
            <span className="tpg-tag" data-dirty={dirty}>
              edited
            </span>
            <div className="dp-stage tpg-frame" style={overrideStyle}>
              <ScreenRenderer ast={demoScreen} />
            </div>
          </div>
        </div>
      </Panel>
    </div>
  );
}
